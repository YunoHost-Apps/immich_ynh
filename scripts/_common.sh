#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

# Fail2ban
failregex="$app-server.*Failed login attempt for user.+from ip address\s?<ADDR>"

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

# Add swap if needed
myynh_add_swap() {
	# Remove existing SWAP
		ynh_del_swap
	# Retrieve RAM needed in G
		local ram_needed_full=$(ynh_read_manifest "integration.ram.build")
		local ram_needed_value=${ram_needed_full::-1}
		local ram_needed_unit=${ram_needed_full:1}
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
			ynh_add_swap --size=$swap_needed_M
		fi
}

# Install immich
myynh_install_immich() {
	# Thanks to https://github.com/arter97/immich-native, https://github.com/community-scripts/ProxmoxVE/blob/main/install/immich-install.sh, https://github.com/loeeeee/immich-in-lxc/blob/main/install.sh
	# Check https://github.com/immich-app/base-images/blob/main/server/Dockerfile for changes

	# Add jellyfin-ffmpeg direcotry to $PATH
		PATH="/usr/lib/jellyfin-ffmpeg/:$PATH"

	# Define nodejs options
		ram_G=$((($(ynh_get_ram --free) - (1024/2))/1024))
		ram_G=$(($ram_G > 1 ? $ram_G : 1))
		ram_G=$(($ram_G*1024))
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
			grep -Rl "/usr/src" | xargs -n1 sed -i -e "s@/usr/src@$install_dir@g"
		# Replace /build
			grep -RlE "\"/build\"|'/build'" \
				| xargs -n1 sed -i -e "s@\"/build\"@\"$install_dir/app\"@g" -e "s@'/build'@'$install_dir/app'@g"
		# Definie pnpm options
			export PNPM_HOME="$source_dir/pnpm"
		# Build server
			cd "$source_dir/server"
   			export SHARP_IGNORE_GLOBAL_LIBVIPS=true
			ynh_hide_warnings pnpm --filter immich --frozen-lockfile build
 			ynh_hide_warnings pnpm --filter immich --frozen-lockfile --prod deploy "$install_dir/app/"

			cp "$install_dir/app/package.json" "$install_dir/app/bin"
			ynh_replace --match="^start" --replace="./start" --file="$install_dir/app/bin/immich-admin"
		# Build openapi & web
			cd "$source_dir"
			ynh_hide_warnings pnpm --filter @immich/sdk --filter immich-web --frozen-lockfile --force install
			ynh_hide_warnings pnpm --filter @immich/sdk --filter immich-web build
			cp -a web/build "$install_dir/app/www"
		# Build cli
			ynh_hide_warnings pnpm --filter @immich/sdk --filter @immich/cli --frozen-lockfile install
			ynh_hide_warnings pnpm --filter @immich/sdk --filter @immich/cli build
			ynh_hide_warnings pnpm --filter @immich/cli --prod --no-optional deploy "$install_dir/app/cli"
			ln -s "$install_dir/app/cli/bin/immich" "$install_dir/app/bin/immich"
		# Copy remaining assets
			cp -a LICENSE "$install_dir/app/"
		# Install custom start.sh script
			ynh_safe_rm "$install_dir/app/bin/start.sh"
			ynh_config_add --template="$app-server-start.sh" --destination="$install_dir/app/bin/start.sh"
		# Cleanup
			ynh_hide_warnings pnpm prune
			ynh_hide_warnings pnpm store prune
			unset PNPM_HOME
 			unset SHARP_IGNORE_GLOBAL_LIBVIPS

	# Install immich-machine-learning
		cd "$source_dir/machine-learning"
		mkdir -p "$install_dir/app/machine-learning"
		# Install uv
			PIPX_HOME="/opt/pipx" PIPX_BIN_DIR="/usr/local/bin" pipx install uv --force 2>&1
			PIPX_HOME="/opt/pipx" PIPX_BIN_DIR="/usr/local/bin" pipx upgrade uv --force 2>&1
			local uv="/usr/local/bin/uv"
		# Execute in a subshell
		(
			# Define some options for uv
				export UV_PYTHON_INSTALL_DIR="$install_dir/app/machine-learning"
				export UV_NO_CACHE=true
				export UV_NO_MODIFY_PATH=true
			# Create the virtual environment
				python_version=$(cat "$source_dir/machine-learning/Dockerfile" \
					| grep "FROM python:" | head -n1 | cut -d':' -f2 | cut -d'-' -f1) # 3.11
				ynh_app_setting_set --key=python_version --value=$python_version
				"$uv" venv --quiet "$install_dir/app/machine-learning/venv" --python "$python_version"
			# Activate the virtual environment
				set +o nounset
				source "$install_dir/app/machine-learning/venv/bin/activate"
				set -o nounset
			# Add pip
				"$uv" pip --quiet --no-cache-dir install --upgrade pip
			# Add uv
				ynh_hide_warnings "$install_dir/app/machine-learning/venv/bin/pip" install --no-cache-dir --upgrade uv
			# Install with uv
				ynh_hide_warnings "$install_dir/app/machine-learning/venv/bin/uv" sync --quiet --no-install-project --no-install-workspace --extra cpu --no-cache --active --link-mode=copy
			# Clear uv options
				unset UV_PYTHON_INSTALL_DIR
				unset UV_NO_CACHE
				unset UV_NO_MODIFY_PATH
		)
		# Copy built files
			cp -a "$source_dir/machine-learning/ann" "$install_dir/app/machine-learning/"
			cp -a "$source_dir/machine-learning/immich_ml" "$install_dir/app/machine-learning/"
		# Install custom start.sh script
			ynh_config_add --template="$app-machine-learning-start.sh" --destination="$install_dir/app/machine-learning/ml_start.sh"
		# Create the cache direcotry
			mkdir -p "$install_dir/.cache_ml"

	# Install geonames
		mkdir -p "$source_dir/geonames"
		cd "$source_dir/geonames"
		# Download files
			curl -LO "https://download.geonames.org/export/dump/cities500.zip" 2>&1
			curl -LO "https://download.geonames.org/export/dump/admin1CodesASCII.txt" 2>&1
			curl -LO "https://download.geonames.org/export/dump/admin2Codes.txt" 2>&1
			curl -LO "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson" 2>&1
			unzip "cities500.zip"
		# Copy built files
			mkdir -p "$install_dir/app/geodata/"
			cp -a "$source_dir/geonames/cities500.txt" "$install_dir/app/geodata/"
			cp -a "$source_dir/geonames/admin1CodesASCII.txt" "$install_dir/app/geodata/"
			cp -a "$source_dir/geonames/admin2Codes.txt" "$install_dir/app/geodata/"
			cp -a "$source_dir/geonames/ne_10m_admin_0_countries.geojson" "$install_dir/app/geodata/"
		# Update geodata-date
			date --iso-8601=seconds | tr -d "\n" > "$install_dir/app/geodata/geodata-date.txt"

	# Cleanup
		ynh_safe_rm "$source_dir"
}

# Execute a psql command as root user
# usage: myynh_execute_psql_as_root [--command=command] --sql=sql [--options=options] [--database=database]
# | arg: -c, --command=     - the psql command to run (default: psql)
# | arg: -s, --sql=         - the SQL command to execute
# | arg: -o, --options=     - the options to add to psql
# | arg: -d, --database=    - the database to connect to
myynh_execute_psql_as_root() {
	# Declare an array to define the options of this helper.
	local legacy_args=sod
	local -A args_array=([c]=command= [s]=sql= [o]=options= [d]=database=)
	local command
	local sql
	local options
	local database
	# Manage arguments with getopts
	ynh_handle_getopts_args "$@"
	command="${command:-psql}"
	sql="${sql:-}"
	options="${options:-}"
	database="${database:-}"
	if [ -n "$sql" ]
	then
		sql="--command=$sql"
	fi
	if [ -n "$database" ]
	then
		database="--dbname=$database"
	fi

	LC_ALL=C sudo --login --user=postgres PGUSER=postgres PGPASSWORD="$(cat $PSQL_ROOT_PWD_FILE)" \
		$command --cluster="$db_cluster" $options "$database" "$sql"
}

# Create the cluster
myynh_create_psql_cluster() {
	if [[ -z `pg_lsclusters | grep "$db_cluster"` ]]
	then
		pg_createcluster ${db_cluster/\// } --start
	else
		myynh_update_psql_db
	fi
}

# Install the database
myynh_create_psql_db() {
	db_pwd=$(ynh_app_setting_get --key=db_pwd)

	myynh_execute_psql_as_root --sql="CREATE DATABASE $app;"
	myynh_execute_psql_as_root --sql="CREATE USER $app WITH ENCRYPTED PASSWORD '$db_pwd';" --database="$app"
	myynh_execute_psql_as_root --sql="GRANT ALL PRIVILEGES ON DATABASE $app TO $app;" --database="$app"
	myynh_execute_psql_as_root --sql="ALTER USER $app WITH SUPERUSER;" --database="$app"
	myynh_execute_psql_as_root --sql="CREATE EXTENSION IF NOT EXISTS vector;" --database="$app"
}

# Update the database
myynh_update_psql_db() {
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
}

# Remove the database
myynh_drop_psql_db() {
	myynh_execute_psql_as_root --sql="REVOKE CONNECT ON DATABASE $app FROM public;"
	myynh_execute_psql_as_root --sql="SELECT pg_terminate_backend (pg_stat_activity.pid) FROM pg_stat_activity \
										WHERE pg_stat_activity.datname = '$app' AND pid <> pg_backend_pid();"
	myynh_execute_psql_as_root --sql="DROP DATABASE $app;"
	myynh_execute_psql_as_root --sql="DROP USER $app;"
}

# Dump the database
myynh_dump_psql_db() {
	myynh_execute_psql_as_root --command="pg_dump" --database="$app" > db.sql
}

# Restore the database
myynh_restore_psql_db() {
	# https://github.com/immich-app/immich/issues/5630#issuecomment-1866581570
	ynh_replace --match="SELECT pg_catalog.set_config('search_path', '', false);" \
		--replace="SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);" --file="db.sql"

	myynh_execute_psql_as_root --database="$app" < ./db.sql
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
	db_port=$(myynh_execute_psql_as_root --sql="\echo :PORT")
	ynh_app_setting_set --key=db_port --value=$db_port
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
		"$install_dir/app/start.sh"
		"$install_dir/app/bin/start.sh"
		"$install_dir/app/machine-learning/start.sh"
		"$install_dir/app/machine-learning/ml_start.sh"
	)
	for file in "${FILE_LIST[@]}"; do
		test -f "$file" && chmod +x "$file"
	done

	chown -R $app: "$data_dir"
	chmod u=rwX,g=rX,o= "$data_dir"
	chmod -R o-rwx "$data_dir"
	setfacl --modify u:$app:rwX,g:$app:rwX "$data_dir/backups/restore_immich_db_backup.sh"

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
myynh_add_swap() {
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

myynh_del_swap() {
	# If there a swap at this place
	if [ -e "/swap_$app" ]; then
		# Clean the fstab
		sed -i "/#Swap added by $app/d" /etc/fstab
		# Desactive the swap file
		swapoff "/swap_$app" 2> /dev/null
		# And remove it
		rm "/swap_$app"
	fi
}

