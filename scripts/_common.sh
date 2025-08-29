#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

# App version
app_version() {
	ynh_read_manifest "version" \
	| cut -d'~' -f1
} # 1.101.0

# NodeJS required version
app_node_version() {
	cat "$source_dir/server/.nvmrc" \
	| cut -d '.' -f1
} # 22

# pnpm required version
app_pnpm_version() {
	cat "$source_dir/package.json" \
	| jq -r '.packageManager | split("@")[1] | split(".")[0]'
} #10

# Fail2ban
failregex="$app-server.*Failed login attempt for user.+from ip address\s?<ADDR>"

# PostgreSQL required version
app_psql_version() {
	ynh_read_manifest "resources.apt.extras.postgresql.packages" \
	| grep -o 'postgresql-[0-9][0-9]-pgvector' \
	| head -n1 \
	| cut -d'-' -f2
} #16
app_psql_port() {
	pg_lsclusters --no-header \
	| grep "^$(app_psql_version)" \
	| cut -d' ' -f3
} # 5433

# Python required version
app_py_version() {
	cat "$source_dir/machine-learning/Dockerfile" \
	| grep "FROM python:" \
	| head -n1 \
	| cut -d':' -f2 \
	| cut -d'-' -f1
} # 3.11

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

# Install immich
myynh_install_immich() {
	# Thanks to https://github.com/arter97/immich-native, https://github.com/community-scripts/ProxmoxVE/blob/main/install/immich-install.sh, https://github.com/loeeeee/immich-in-lxc/blob/main/install.sh
	# Check https://github.com/immich-app/base-images/blob/main/server/Dockerfile for changes

	# Add jellyfin-ffmpeg direcotry to $PATH
		PATH="/usr/lib/jellyfin-ffmpeg/:$PATH"

	# Define nodejs options
		ram_G=$((($(ynh_get_ram --total) - (1024/2))/1024))
		ram_G=$(($ram_G > 1 ? $ram_G : 1))
		ram_G=$(($ram_G*1024))
		export NODE_OPTIONS="--max_old_space_size=$ram_G"
		export NODE_ENV=production

	# Install pnpm
		ynh_hide_warnings npm install --global corepack@latest
		export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
		export CI=1
		ynh_hide_warnings corepack enable pnpm
		ynh_hide_warnings corepack use pnpm@latest-$(app_pnpm_version)

	# Print versions
		echo "node version: {$(node -v)}"
		echo "npm version: {$(npm -v)}"
		echo "pnpm version: {$(pnpm -v)}"

	# Install immich-server
		# Replace /usr/src
			cd "$source_dir"
			grep -Rl "/usr/src" | xargs -n1 sed -i -e "s@/usr/src@$install_dir@g"
		# Replace /build
			grep -RlE "\"/build\"|'/build'" \
				| xargs -n1 sed -i -e "s@\"/build\"@\"$install_dir/app\"@g" -e "s@'/build'@'$install_dir/app'@g"
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
			# Create the virtual environment
				"$uv" venv --quiet "$install_dir/app/machine-learning/venv" --python "$(app_py_version)"
			# activate the virtual environment
				set +o nounset
				source "$install_dir/app/machine-learning/venv/bin/activate"
				set -o nounset
			# add pip
				"$uv" pip --quiet --no-cache-dir install --upgrade pip
			# add uv
				ynh_hide_warnings "$install_dir/app/machine-learning/venv/bin/pip" install --no-cache-dir --upgrade uv
			# uv install
				ynh_hide_warnings "$install_dir/app/machine-learning/venv/bin/uv" sync --quiet --no-install-project --no-install-workspace --extra cpu --no-cache --active --link-mode=copy
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

	# Retrieve dependencies version
		ffmpeg_version=$(/usr/lib/jellyfin-ffmpeg/ffmpeg -version | grep "ffmpeg version" | cut -d" " -f3)

	# Cleanup
		ynh_safe_rm "$source_dir"
}

# Execute a psql command as root user
# usage: myynh_execute_psql_as_root --sql=sql [--options=options] [--database=database]
# | arg: -s, --sql=         - the SQL command to execute
# | arg: -o, --options=     - the options to add to psql
# | arg: -d, --database=    - the database to connect to
myynh_execute_psql_as_root() {
	# Declare an array to define the options of this helper.
	local legacy_args=sod
	local -A args_array=([s]=sql= [o]=options= [d]=database=)
	local sql
	local options
	local database
	# Manage arguments with getopts
	ynh_handle_getopts_args "$@"
	options="${options:-}"
	database="${database:-}"
	if [ -n "$database" ]
	then
		database="--dbname=$database"
	fi

	LC_ALL=C sudo --login --user=postgres PGUSER=postgres PGPASSWORD="$(cat $PSQL_ROOT_PWD_FILE)" \
		psql --cluster="$(app_psql_version)/main" $options "$database" --command="$sql"
}

# Drop default db & user created by [resources.database] in manifest
myynh_deprovision_default() {
	ynh_psql_database_exists $app && ynh_psql_drop_db $app || true
	ynh_psql_user_exists $app && ynh_psql_drop_user $app || true
}

# Create the cluster
myynh_create_psql_cluster() {
	if [[ -z `pg_lsclusters | grep $(app_psql_version)` ]]
	then
		pg_createcluster $(app_psql_version) main --start
	fi
}

# Install the database
myynh_create_psql_db() {
	myynh_execute_psql_as_root --sql="CREATE DATABASE $app;"
	myynh_execute_psql_as_root --sql="CREATE USER $app WITH ENCRYPTED PASSWORD '$db_pwd';" --database="$app"
	myynh_execute_psql_as_root --sql="GRANT ALL PRIVILEGES ON DATABASE $app TO $app;" --database="$app"
	myynh_execute_psql_as_root --sql="ALTER USER $app WITH SUPERUSER;" --database="$app"
	myynh_execute_psql_as_root --sql="CREATE EXTENSION IF NOT EXISTS vector;" --database="$app"
}

# Update the database
myynh_update_psql_db() {
	databases=$(myynh_execute_psql_as_root --sql="SELECT datname FROM pg_database WHERE datistemplate = false OR datname = 'template1';" \
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
	sudo --login --user=postgres pg_dump --cluster="$(app_psql_version)/main" --dbname="$app" > db.sql
}

# Restore the database
myynh_restore_psql_db() {
	# https://github.com/immich-app/immich/issues/5630#issuecomment-1866581570
	ynh_replace --match="SELECT pg_catalog.set_config('search_path', '', false);" \
		--replace="SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);" --file="db.sql"

	sudo --login --user=postgres PGUSER=postgres PGPASSWORD="$(cat $PSQL_ROOT_PWD_FILE)" \
		psql --cluster="$(app_psql_version)/main" --dbname="$app" < ./db.sql
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

	chown -R $app: "/var/log/$app"
	chmod u=rw,g=r,o= "/var/log/$app"

	# Upgade user groups
	local user_groups=""
	[ -n $(getent group video) ] && adduser --quiet "$app" video 2>&1
	[ -n $(getent group render) ] && adduser --quiet "$app" render 2>&1
}

myynh_set_default_psql_cluster_to_debian_default() {
	local default_port=5432
	local config_file="/etc/postgresql-common/user_clusters"

	#retrieve informations about default psql cluster
	default_psql_version=$(pg_lsclusters --no-header | grep "$default_port" | cut -d' ' -f1)
	default_psql_cluster=$(pg_lsclusters --no-header | grep "$default_port" | cut -d' ' -f2)
	default_psql_database=$(pg_lsclusters --no-header | grep "$default_port" | cut -d' ' -f5)

	# Remove non commented lines
	sed -i'.bak' -e '/^#/!d' "$config_file"

	# Add new line USER  GROUP   VERSION CLUSTER DATABASE
	echo -e "* * $default_psql_version $default_psql_cluster $default_psql_database" >> "$config_file"

	# Remove the autoprovisionned db if not on right cluster
	if [ "$(app_psql_port)" -ne "$default_port" ]
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
