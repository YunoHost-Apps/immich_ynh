#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

# Postgresql version
psql_bookworm=16
psql_trixie=17
if [[ $YNH_DEBIAN_VERSION == "bookworm" ]]
then
	psql_version=$psql_bookworm
elif [[ $YNH_DEBIAN_VERSION == "trixie" ]]
then
	psql_version=$psql_trixie
fi

# Fail2ban
failregex="$app-server.*Failed login attempt for user.+from ip address\s?<ADDR>"

# App path
app_dir="$install_dir/immich/app"

# Check hardware requirements
myynh_check_hardware() {
	# CPU: Prebuilt binaries for linux-x64 require v2 microarchitecture
		local file_test="/lib64/ld-linux-x86-64.so.2"
		if [ -f "$file_test" ]
		then
			if [ -z "$( $file_test --help | grep 'x86-64-v2 (supported' )" ]
			then
				ynh_die "Your CPU is too old and not supported. Installation of $app is not possible on your system."
			fi
		fi
}

# Add postgresql packages from postgresql repo if needed
myynh_install_postgresql_packages() {
	if [[ $YNH_DEBIAN_VERSION == "bookworm" ]]
	then
		ynh_apt_install_dependencies_from_extra_repository \
			--repo="deb https://apt.postgresql.org/pub/repos/apt $YNH_DEBIAN_VERSION-pgdg main $psql_version" \
			 --key="https://www.postgresql.org/media/keys/ACCC4CF8.asc" \
			 --package="libpq5 libpq-dev postgresql-$psql_version postgresql-$psql_version-pgvector postgresql-client-$psql_version"
		db_cluster="$psql_version/main"
	elif [[ $YNH_DEBIAN_VERSION == "trixie" ]]
	then
		YNH_APT_INSTALL_DEPENDENCIES_REPLACE="false" ynh_apt_install_dependencies "postgresql-$psql_version-pgvector"
		db_cluster="$psql_version/main"
	fi
}

# Add swap if needed
myynh_add_swap() {
	# Remove existing SWAP
		ynh_del_swap_fixed
	# Retrieve RAM needed in G
		local ram_needed_full=$(ynh_read_manifest "integration.ram.build")
		local ram_needed_value=${ram_needed_full::-1}
		local ram_needed_unit=${ram_needed_full: -1}
		if [ $ram_needed_unit = "M" ]
		then
			ram_needed_G=$(($ram_needed_value/1024))
		else
			ram_needed_G=$(($ram_needed_value))
		fi
	# Retrieve free RAM in G
		local ram_free_G=$(($(ynh_get_ram --free)/1024))
	# Check and add right amount of SWAP if needed
		local swap_needed_M=0
		if [ $ram_free_G -lt $ram_needed_G ]
		then
			swap_needed_M=$((($ram_needed_G-$ram_free_G)*1024))
		fi
		if [ $swap_needed_M -gt 0 ]
		then
			ynh_print_info "Adding $swap_needed_M Mb to swap..."
			ynh_add_swap_fixed --size=$swap_needed_M
		fi
	# Recheck free RAM in G
		local ram_free_G=$(($(ynh_get_ram --free)/1024))
		if [ $ram_free_G -lt $ram_needed_G ]
		then
			# Remove existing SWAP
				ynh_del_swap_fixed
			# Terminate install/upgarde script
				ynh_die "There is no enough free memory on your system ($ram_needed_G GB are needed to build successfully $app). You need to either add RAM or manually add swap to your system."
		fi
}

# Install libheif and libvips from source for HEIC support
# Based on https://github.com/community-scripts/ProxmoxVE/blob/main/install/immich-install.sh
# and https://github.com/immich-app/base-images/blob/main/server/Dockerfile
myynh_install_libvips() {
	local build_dir="$source_dir/vips-build"
	local libs_dir="$install_dir/vips"
	ynh_safe_rm "$libs_dir"
	mkdir -p "$build_dir" "$libs_dir" "$build_dir/libheif"
	pushd "$build_dir"

	# Build libheif
		ynh_print_info "Building libheif for HEIC support..."
		ynh_setup_source --source_id="libheif" --dest_dir="$build_dir/libheif"
		pushd libheif
		mkdir -p build
		cd build
		ynh_hide_warnings cmake --preset=release-noplugins \
			-DCMAKE_INSTALL_PREFIX="$libs_dir" \
			-DWITH_DAV1D=ON \
			-DENABLE_PARALLEL_TILE_DECODING=ON \
			-DWITH_LIBSHARPYUV=ON \
			-DWITH_LIBDE265=ON \
			-DWITH_AOM_DECODER=OFF \
			-DWITH_AOM_ENCODER=ON \
			-DWITH_X265=OFF \
			-DWITH_EXAMPLES=OFF \
			..
		ynh_hide_warnings make -j "$(nproc)"
		ynh_hide_warnings make install
		popd

	# Build libvips
		ynh_print_info "Building libvips with HEIC support..."
		export PKG_CONFIG_PATH="$libs_dir/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
		export LD_LIBRARY_PATH="$libs_dir/lib:${LD_LIBRARY_PATH:-}"
		ynh_setup_source --source_id="libvips" --dest_dir="$build_dir/libvips"
		pushd libvips
		ynh_hide_warnings meson setup build --buildtype=release \
			--prefix="$libs_dir" \
			--libdir=lib \
			-Dintrospection=disabled \
			-Dtiff=disabled
		cd build
		ynh_hide_warnings ninja install
		popd

	# Return to original directory
		popd

	# Save versions in settings
		ynh_app_setting_set --key=libheif_version --value=$(ynh_read_manifest "resources.sources.libheif.url")
		ynh_app_setting_set --key=libvips_version --value=$(ynh_read_manifest "resources.sources.libvips.url")

	# Cleanup
		ynh_print_info "Cleaning up libvips build directory..."
		ynh_safe_rm "$build_dir"
}

# Install immich
myynh_install_immich() {
	# Thanks to https://github.com/arter97/immich-native, https://github.com/community-scripts/ProxmoxVE/blob/main/install/immich-install.sh, https://github.com/loeeeee/immich-in-lxc/blob/main/install.sh
	# Check https://github.com/immich-app/base-images/blob/main/server/Dockerfile for changes

	# Set $home to $source_dir for pnpm and mise
		export HOME="$source_dir"
	# Add jellyfin-ffmpeg direcotry to $PATH
		PATH="/usr/lib/jellyfin-ffmpeg/:$PATH"
	# Add mise shims direcotry to $PATH
		PATH="$HOME/.local/share/mise/shims:$PATH"

	# Build libvips with HEIC support
		if [[ ! -d "$install_dir/vips" \
		|| $(ynh_read_manifest "resources.sources.libheif.url") != $(ynh_app_setting_get --key=libheif_version) \
		|| $(ynh_read_manifest "resources.sources.libvips.url") != $(ynh_app_setting_get --key=libvips_version) ]]
		then
			myynh_install_libvips
		else
			ynh_print_info "Current libheif and libvips are up-to-date for HEIC support, no need to rebuild them..."
		fi
		export LD_LIBRARY_PATH="$install_dir/vips/lib:${LD_LIBRARY_PATH:-}"
		export PKG_CONFIG_PATH="$install_dir/vips/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

	# Define nodejs options
		local ram_free_G=$((($(ynh_get_ram --free) - (1024/2))/1024))
		ram_free_G=$((ram_free_G > 1 ? ram_free_G : $ram_needed_G))
		ram_free_G=$((ram_free_G > 8 ? 8 : ram_free_G))
		local ram_G=$((ram_free_G*1024))
		export NODE_OPTIONS="${NODE_OPTIONS:-} --max_old_space_size=$ram_G"
		export NODE_ENV=production

	# Install pnpm
		ynh_hide_warnings npm install --global corepack@latest
		export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
		export CI=1
		pnpm_version=$(cat "$source_dir/package.json" \
			| jq -r '.packageManager | split("@")[1] | split(".")[0]') #10
		ynh_hide_warnings corepack enable pnpm
		ynh_hide_warnings corepack use pnpm@latest-$pnpm_version

	# Print versions
		echo "node version: $(node -v)"
		echo "npm version: $(npm -v)"
		echo "pnpm version: $(pnpm -v)"

	# Install immich-server
		# Replace /usr/src
			cd "$source_dir"
			grep -Rl "/usr/src" | xargs -n1 sed -i -e "s@/usr/src@$install_dir/immich@g"
		# Replace /build
			grep -RlE "\"/build\"|'/build'" \
				| xargs -n1 sed -i -e "s@\"/build\"@\"$app_dir\"@g" -e "s@'/build'@'$app_dir'@g"
		# Build server
			ynh_print_info "Building immich server..."
			cd "$source_dir/server"
			export SHARP_IGNORE_GLOBAL_LIBVIPS=true
			ynh_hide_warnings pnpm --filter immich --frozen-lockfile build
			unset SHARP_IGNORE_GLOBAL_LIBVIPS
			export SHARP_FORCE_GLOBAL_LIBVIPS=true
			ynh_hide_warnings pnpm --filter immich --frozen-lockfile --prod --no-optional deploy "$app_dir/"
			cp "$app_dir/package.json" "$app_dir/bin"
			ynh_replace --match="^start" --replace="./start" --file="$app_dir/bin/immich-admin"
		# Build openapi & web
			ynh_print_info "Building immich openapi & web interface..."
			cd "$source_dir"
			ynh_hide_warnings pnpm --filter @immich/sdk --filter immich-web --frozen-lockfile --force install
			unset SHARP_FORCE_GLOBAL_LIBVIPS
			export SHARP_IGNORE_GLOBAL_LIBVIPS=true
			ynh_hide_warnings pnpm --filter @immich/sdk --filter immich-web build
			cp -a web/build "$app_dir/www"
		# Build cli
			ynh_print_info "Building immich cli..."
			cd "$source_dir"
			ynh_hide_warnings pnpm --filter @immich/sdk --filter @immich/cli --frozen-lockfile install
			ynh_hide_warnings pnpm --filter @immich/sdk --filter @immich/cli build
			ynh_hide_warnings pnpm --filter @immich/cli --prod --no-optional deploy "$app_dir/cli"
			ln -s "$app_dir/cli/bin/immich" "$app_dir/bin/immich"
		# Build plugins
			ynh_print_info "Building immich plugins..."
			cd "$source_dir"
			mkdir -p "$app_dir/corePlugin"
			if [[ $YNH_DEBIAN_VERSION == "bookworm" ]]
			then
				ynh_replace \
					--match="github:extism/js-pdk" \
					--replace="github:ewilly/js-pdk" \
					--file="$source_dir/plugins/mise.toml"
			fi
			ynh_hide_warnings mise trust --ignore ./mise.toml
			ynh_hide_warnings mise trust ./plugins/mise.toml
			cd "$source_dir/plugins"
			ynh_hide_warnings mise install
			ynh_hide_warnings mise run build
			mkdir -p "$app_dir/corePlugin"
			cp -r dist "$app_dir/corePlugin/dist"
			cp manifest.json "$app_dir/corePlugin"
		# Copy remaining assets
			cp -a LICENSE "$app_dir/"
		# Install custom start.sh script
			ynh_safe_rm "$app_dir/bin/start.sh"
			ynh_config_add --template="$app-server-start.sh" --destination="$app_dir/bin/start.sh"

	# Install immich-machine-learning
		ynh_print_info "Building immich machine learning..."
		cd "$source_dir/machine-learning"
		local ml_dir="$app_dir/machine-learning"
		mkdir -p "$ml_dir"
		# Retive python needed version
			python_version=$(cat "$source_dir/machine-learning/Dockerfile" \
				| grep "FROM python:" | head -n1 | cut -d':' -f2 | cut -d'-' -f1) # 3.11
			ynh_app_setting_set --key=python_version --value=$python_version
		# Install uv
			mise use uv@latest --quiet
		# Install with uv in a subshell
			(
				export UV_PYTHON_INSTALL_DIR="$ml_dir"
				uv venv "$ml_dir/venv" --quiet --no-cache --python "$python_version" --managed-python
				source "$ml_dir/venv/bin/activate"
				uv sync --quiet --no-cache --frozen --extra cpu --active
			)
		# Copy built files
			cp -a "$source_dir/machine-learning/ann" "$ml_dir/"
			cp -a "$source_dir/machine-learning/immich_ml" "$ml_dir/"
		# Install custom start.sh script
			ynh_config_add --template="$app-machine-learning-start.sh" --destination="$ml_dir/ml_start.sh"
		# Create the cache direcotry
			mkdir -p "$install_dir/immich/.cache_ml"

	# Install geonames
		ynh_print_info "Adding geonames capabilities..."
		mkdir -p "$source_dir/geonames"
		cd "$source_dir/geonames"
		# Download files
			curl -LO "https://download.geonames.org/export/dump/cities500.zip" 2>&1
			curl -LO "https://download.geonames.org/export/dump/admin1CodesASCII.txt" 2>&1
			curl -LO "https://download.geonames.org/export/dump/admin2Codes.txt" 2>&1
			curl -LO "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson" 2>&1
			unzip "cities500.zip"
		# Copy built files
			mkdir -p "$app_dir/geodata/"
			cp -a "$source_dir/geonames/cities500.txt" "$app_dir/geodata/"
			cp -a "$source_dir/geonames/admin1CodesASCII.txt" "$app_dir/geodata/"
			cp -a "$source_dir/geonames/admin2Codes.txt" "$app_dir/geodata/"
			cp -a "$source_dir/geonames/ne_10m_admin_0_countries.geojson" "$app_dir/geodata/"
		# Update geodata-date
			date --iso-8601=seconds | tr -d "\n" > "$app_dir/geodata/geodata-date.txt"

	# Cleanup
		ynh_print_info "Cleaning up immich source directory..."
		ynh_safe_rm "$source_dir"
}

# Execute a psql command as root user
# usage: myynh_execute_psql_as_root [--tool=tool] --sql=sql [--options=options] [--cluster=cluster] [--database=database]
# | arg: -t, --tool=        - the psql tool to run (default: psql)
# | arg: -s, --sql=         - the SQL command to execute
# | arg: -o, --options=     - the options to add to psql
# | arg: -c, --cluster=     - the cluster to connect to (default: current cluster)
# | arg: -d, --database=    - the database to connect to
myynh_execute_psql_as_root() {
	# Declare an array to define the options of this helper.
	local legacy_args=sod
	local -A args_array=([t]=tool= [s]=sql= [o]=options= [c]=cluster= [d]=database=)
	local tool
	local sql
	local options
	local cluster
	local database
	# Manage arguments with getopts
	ynh_handle_getopts_args "$@"
	tool="${tool:-psql}"
	sql="${sql:-}"
	options="${options:-}"
	cluster="${cluster:-$db_cluster}"
	database="${database:-}"
	if [ -n "$sql" ]
	then
		sql="--command=$sql"
	fi
	cluster="--cluster=$cluster"
	if [ -n "$database" ]
	then
		database="--dbname=$database"
	fi

	LC_ALL=C sudo --login --user=postgres PGUSER=postgres PGPASSWORD="$(cat $PSQL_ROOT_PWD_FILE)" \
		$tool "$cluster" $options "$database" "$sql"
}

# Create the cluster
myynh_create_psql_cluster() {
	if [[ -z `pg_lsclusters | grep "$db_cluster"` ]]
	then
		pg_createcluster ${db_cluster/\// } --start
	fi
}

# Install the database
myynh_create_psql_db() {
	# Declare an array to define the options of this helper.
	local legacy_args=sod
	local -A args_array=([c]=cluster=)
	local cluster
	# Manage arguments with getopts
	ynh_handle_getopts_args "$@"
	cluster="${cluster:-$db_cluster}"

	db_pwd=$(ynh_app_setting_get --key=db_pwd)

	myynh_execute_psql_as_root --cluster="$cluster" --sql="CREATE DATABASE $app;"
	myynh_execute_psql_as_root --cluster="$cluster" --sql="CREATE USER $app WITH ENCRYPTED PASSWORD '$db_pwd';" --database="$app"
	myynh_execute_psql_as_root --cluster="$cluster" --sql="GRANT ALL PRIVILEGES ON DATABASE $app TO $app;" --database="$app"
}

# Update the database
myynh_update_psql_db() {
	# Fix collation version mismatch
	databases=$(myynh_execute_psql_as_root \
		--sql="SELECT datname FROM pg_database WHERE datistemplate = false OR datname = 'template1';" \
		--options="--tuples-only --no-align" --database="postgres")

	for db in $databases
	do
		if ynh_hide_warnings myynh_execute_psql_as_root --sql=";" --database="$db" \
		   | grep -q "collation version mismatch"
		then
			ynh_hide_warnings myynh_execute_psql_as_root --sql="REINDEX DATABASE $db;" --database="$db"
			myynh_execute_psql_as_root --sql="ALTER DATABASE $db REFRESH COLLATION VERSION;" --database="$db"
		fi
	done

	# Tune immich db
	myynh_execute_psql_as_root --sql="ALTER USER $app WITH SUPERUSER;" --database="$app"
	ynh_hide_warnings myynh_execute_psql_as_root --sql="CREATE EXTENSION IF NOT EXISTS vector;" --database="$app"

	# Retrive and save the postgresql port of the cluster and save it in settings
	myynh_retrieve_psql_port

	# Save settings
	ynh_app_setting_set --key=db_cluster --value="$db_cluster"
}

# Remove the database
# usage: myynh_drop_psql_db [--cluster=cluster]
# | arg: -c, --cluster=     - the cluster to connect to (default: current cluster)
myynh_drop_psql_db() {
	# Declare an array to define the options of this helper.
	local legacy_args=sod
	local -A args_array=([c]=cluster=)
	local cluster
	# Manage arguments with getopts
	ynh_handle_getopts_args "$@"
	cluster="${cluster:-$db_cluster}"

	myynh_execute_psql_as_root --cluster="$cluster" --sql="REVOKE CONNECT ON DATABASE $app FROM public;"
	myynh_execute_psql_as_root --cluster="$cluster" --sql="SELECT pg_terminate_backend (pg_stat_activity.pid) FROM pg_stat_activity \
															WHERE pg_stat_activity.datname = '$app' AND pid <> pg_backend_pid();"
	myynh_execute_psql_as_root --cluster="$cluster" --sql="DROP DATABASE $app;"
	myynh_execute_psql_as_root --cluster="$cluster" --sql="DROP USER $app;"
}

# Dump the database
# usage: myynh_dump_psql_db [--cluster=cluster]
# | arg: -c, --cluster=     - the cluster to connect to (default: current cluster)
myynh_dump_psql_db() {
	# Declare an array to define the options of this helper.
	local legacy_args=sod
	local -A args_array=([c]=cluster=)
	local cluster
	# Manage arguments with getopts
	ynh_handle_getopts_args "$@"
	cluster="${cluster:-$db_cluster}"

	myynh_execute_psql_as_root --tool="pg_dump" --cluster="$cluster" --database="$app" > db.sql
}

# Restore the database
# usage: myynh_restore_psql_db [--cluster=cluster]
# | arg: -c, --cluster=     - the cluster to connect to (default: current cluster)
myynh_restore_psql_db() {
	# Declare an array to define the options of this helper.
	local legacy_args=sod
	local -A args_array=([c]=cluster=)
	local cluster
	# Manage arguments with getopts
	ynh_handle_getopts_args "$@"
	cluster="${cluster:-$db_cluster}"

	# Adjust the content cf. https://github.com/immich-app/immich/issues/5630#issuecomment-1866581570
	ynh_replace --match="SELECT pg_catalog.set_config('search_path', '', false);" \
		--replace="SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);" --file="db.sql"

	# Restore the db
	myynh_execute_psql_as_root --cluster="$cluster" --database="$app" < ./db.sql

	# Restore the password
	db_pwd="$(ynh_app_setting_get --key=db_pwd)"
	myynh_execute_psql_as_root --cluster="$cluster" --sql="ALTER USER $app WITH ENCRYPTED PASSWORD '$db_pwd';" --database="$app"
}

# Retrieve the postgresql port of the cluster
myynh_retrieve_psql_port() {
# usage: myynh_dump_psql_db [--cluster=cluster]
# | arg: -c, --cluster=     - the cluster to connect to (default: current cluster)
	# Declare an array to define the options of this helper.
	local legacy_args=sod
	local -A args_array=([c]=cluster=)
	local cluster
	# Manage arguments with getopts
	ynh_handle_getopts_args "$@"
	cluster="${cluster:-$db_cluster}"

	db_port=$(myynh_execute_psql_as_root --cluster="$cluster" --sql="\echo :PORT")
	ynh_app_setting_set --key=db_port --value=$db_port
}

# Set default cluster back to debian and remove autoprovisionned db if not on right cluster
myynh_set_default_psql_cluster_to_debian_default() {
	local default_port=5432
	local config_file="/etc/postgresql-common/user_clusters"

	# Retrieve informations about default psql cluster
	default_db_cluster=$(pg_lsclusters --no-header | grep "$default_port" | cut -d' ' -f1)
	default_psql_cluster=$(pg_lsclusters --no-header | grep "$default_port" | cut -d' ' -f2)
	default_psql_database=$(pg_lsclusters --no-header | grep "$default_port" | cut -d' ' -f5)

	# Remove non commented lines
	sed -i'.bak' -e '/^#/!d' "$config_file"

	# Add new line USER  GROUP   VERSION CLUSTER DATABASE
	echo -e "* * $default_db_cluster $default_psql_cluster $default_psql_database" >> "$config_file"

	# Remove the autoprovisionned db if not on right cluster
	myynh_retrieve_psql_port
	if [[ $db_port -ne $default_port ]]
	then
		if ynh_psql_database_exists "$app"
		then
			ynh_psql_drop_db "$app"
		fi
		if ynh_psql_user_exists "$app"
		then
			ynh_psql_drop_user "$app"
		fi
	fi
}

# Set permissions
myynh_set_permissions() {
	chown -R $app: "$install_dir"
	chmod u=rwX,g=rX,o= "$install_dir"
	chmod -R o-rwx "$install_dir"

	FILE_LIST=(
		"$app_dir/start.sh"
		"$app_dir/bin/start.sh"
		"$app_dir/machine-learning/start.sh"
		"$app_dir/machine-learning/ml_start.sh"
	)
	for file in "${FILE_LIST[@]}"; do
		test -f "$file" && chmod +x "$file"
	done

	if [[ -z ${YNH_APP_UPGRADE_TYPE:-} ]]
	then
		chown -R $app: "$data_dir"
		chmod u=rwX,g=rX,o= "$data_dir"
		chmod -R o-rwx "$data_dir"
	fi

	chown $app: "$data_dir/backups/restore_immich_db_backup.sh"
	chmod u=rwX,g=rX,o=X "$data_dir/backups/restore_immich_db_backup.sh"

	chown -R $app: "/var/log/$app"
	chmod u=rw,g=r,o= "/var/log/$app"

	# Upgade user groups
	local user_groups=""
	[ -n $(getent group video) ] && adduser --quiet "$app" video 2>&1
	[ -n $(getent group render) ] && adduser --quiet "$app" render 2>&1
}

# Add swap
#
# usage: ynh_add_swap --size=SWAP in Mb
# | arg: -s, --size= - Amount of SWAP to add in Mb.
ynh_add_swap_fixed() {
	if systemd-detect-virt --container --quiet; then
		ynh_print_warn "You are inside a container/VM. swap will not be added, but that can cause troubles for the app $app. Please make sure you have enough RAM available."
		return
	fi

	# Declare an array to define the options of this helper.
	declare -Ar args_array=([s]=size=)
	local size
	# Manage arguments with getopts
	ynh_handle_getopts_args "$@"

	local swap_max_size=$((size * 1024))

	local free_space=$(df --output=avail / | sed 1d)
	# Because we don't want to fill the disk with a swap file, divide by 2 the available space.
	local usable_space=$((free_space / 2))

	SD_CARD_CAN_SWAP=${SD_CARD_CAN_SWAP:-0}

	# Swap on SD card only if it's is specified
	if ynh_is_main_device_a_sd_card && [ "$SD_CARD_CAN_SWAP" == "0" ]; then
		ynh_print_warn "The main mountpoint of your system '/' is on an SD card, swap will not be added to prevent some damage of this one, but that can cause troubles for the app $app. If you still want activate the swap, you can relaunch the command preceded by 'SD_CARD_CAN_SWAP=1'"
		return
	fi

	# Compare the available space with the size of the swap.
	# And set a acceptable size from the request
	if [ $usable_space -ge $swap_max_size ]; then
		local swap_size=$swap_max_size
	elif [ $usable_space -ge $((swap_max_size / 2)) ]; then
		local swap_size=$((swap_max_size / 2))
	elif [ $usable_space -ge $((swap_max_size / 3)) ]; then
		local swap_size=$((swap_max_size / 3))
	elif [ $usable_space -ge $((swap_max_size / 4)) ]; then
		local swap_size=$((swap_max_size / 4))
	else
		echo "Not enough space left for a swap file" >&2
		local swap_size=0
	fi

	# If there's enough space for a swap, and no existing swap here
	if [ $swap_size -ne 0 ] && [ ! -e "/swap_$app" ]; then
		# Create file
		truncate -s 0 "/swap_$app"

		# try to set the No_COW attribute on the swapfile with chattr (depending of the filesystem type)
		if grep -qs ' / .*btrfs' /proc/mounts; then
			chattr +C "/swap_$app"
		fi

		# Preallocate space for the swap file, fallocate may sometime not be used, use dd instead in this case
		if ! fallocate -l ${swap_size}K "/swap_$app"; then
			dd if=/dev/zero of="/swap_$app" bs=1024 count=${swap_size}
		fi
		chmod 0600 "/swap_$app"
		# Create the swap
		mkswap "/swap_$app"
		# And activate it
		swapon "/swap_$app"
		# Then add an entry in fstab to load this swap at each boot.
		echo -e "/swap_$app swap swap defaults 0 0 #Swap added by $app" >> /etc/fstab
	fi
}

ynh_del_swap_fixed() {
	# If there a swap at this place
	if [ -e "/swap_$app" ]; then
		# Clean the fstab
		sed -i "/#Swap added by $app/d" /etc/fstab
		# Desactive the swap file if active
		if grep -qs "/swap_$app" /proc/swaps; then
			swapoff "/swap_$app"
		fi
		# And remove it
		rm "/swap_$app"
	fi
}
