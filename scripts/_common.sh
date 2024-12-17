#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

# App version
## yq is not a dependencie of yunohost package so tomlq command is not available
## (see https://github.com/YunoHost/yunohost/blob/dev/debian/control)
app_version() { \
	ynh_read_manifest "version" \
	| cut -d'~' -f1 \
} #1.101.0

# NodeJS required version
nodejs_version=22

# Fail2ban
failregex="$app-server.*Failed login attempt for user.+from ip address\s?<ADDR>"

# PostgreSQL required version
postgresql_version() { \
	ynh_read_manifest "resources.apt.extras.postgresql.packages" \
	| grep -o 'postgresql-[0-9][0-9]-pgvector' \
	| head -n1 \
	| cut -d'-' -f2 \
}
postgresql_cluster_port() { \
	pg_lsclusters --no-header \
	| grep "^$postgresql_version" \
	| cut -d' ' -f3 \
}

# Python required version
py_required_major() { \
	curl -Ls "https://raw.githubusercontent.com/immich-app/immich/refs/tags/v$app_version/machine-learning/Dockerfile " \
	| grep "FROM python:" \
	| head -n1 \
	| cut -d':' -f2 \
	| cut -d'-' -f1 \
} #3.11

# Install immich
myynh_install_immich() {
	# Thanks to https://github.com/arter97/immich-native
	# Check https://github.com/immich-app/base-images/blob/main/server/Dockerfile for changes

	# Add ffmpeg-static direcotry to $PATH
		PATH="$ffmpeg_static_dir:$PATH"

	# Define nodejs options
		ram_G=$((($(ynh_get_ram --total) - (1024/2))/1024))
		ram_G=$(($ram_G > 1 ? $ram_G : 1))
		export NODE_OPTIONS="--max_old_space_size=$(($ram_G*1024))"

	# Use 127.0.0.1
		cd "$source_dir"
		find . -type f \( -name '*.ts' -o -name '*.js' \) \
			-exec grep app.listen {} + \
			| sed 's/.*app.listen//' | grep -v '()' \
			| grep '^(' \
			| tr -d "[:blank:]" | awk -F"[(),]" '{print $2}' \
			| sort \
			| uniq \
			| while read port; do
				find . -type f \( -name '*.ts' -o -name '*.js' \) \
					-exec sed -i -e "s@app.listen(${port})@app.listen(${port}, '127.0.0.1')@g" {} +
			done
		find . -type f \( -name '*.ts' -o -name '*.js' \) \
			-exec sed -i -e "s@PrometheusExporter({ port })@PrometheusExporter({ host: '127.0.0.1', port: port })@g" {} +
		grep -RlE "\"0\.0\.0\.0\"|'0\.0\.0\.0'" \
			| xargs -n1 sed -i -e "s@'0\.0\.0\.0'@'127.0.0.1'@g" -e 's@"0\.0\.0\.0"@"127.0.0.1"@g'

	# Replace /usr/src
		cd "$source_dir"
		grep -Rl "/usr/src" | xargs -n1 sed -i -e "s@/usr/src@$install_dir@g"
		mkdir -p "$install_dir/cache"
		grep -RlE "\"/cache\"|'/cache'" \
			| xargs -n1 sed -i -e "s@\"/cache\"@\"$install_dir/cache\"@g" -e "s@'/cache'@'$install_dir/cache'@g"
		grep -RlE "\"/build\"|'/build'" \
			| xargs -n1 sed -i -e "s@\"/build\"@\"$install_dir/app\"@g" -e "s@'/build'@'$install_dir/app'@g"

	# Install immich-server
		cd "$source_dir/server"
		ynh_hide_warnings npm ci
		ynh_hide_warnings npm run build
		ynh_hide_warnings npm prune --omit=dev --omit=optional

		cd "$source_dir/open-api/typescript-sdk"
		ynh_hide_warnings npm ci
		ynh_hide_warnings npm run build

		cd "$source_dir/web"
		ynh_hide_warnings npm ci
		ynh_hide_warnings npm run build

		mkdir -p "$install_dir/app/"
		cp -a "$source_dir/server/node_modules" "$install_dir/app/"
		cp -a "$source_dir/server/dist" "$install_dir/app/"
		cp -a "$source_dir/server/bin" "$install_dir/app/"
		cp -a "$source_dir/web/build" "$install_dir/app/www"
		cp -a "$source_dir/server/resources" "$install_dir/app/"
		cp -a "$source_dir/server/package.json" "$install_dir/app/"
		cp -a "$source_dir/server/package-lock.json" "$install_dir/app/"
		cp -a "$source_dir/LICENSE" "$install_dir/app/"
		cp -a "$source_dir/i18n" "$install_dir/"
		# Install custom start.sh script
		ynh_config_add --template="$app-server-start.sh" --destination="$install_dir/app/start.sh"
		cd "$install_dir/app/"
		ynh_hide_warnings npm cache clean --force

	# Install immich-machine-learning
		cd "$source_dir/machine-learning"
		mkdir -p "$install_dir/app/machine-learning"
		python3 -m venv "$install_dir/app/machine-learning/venv"
		(
			# activate the virtual environment
			set +o nounset
			source "$install_dir/app/machine-learning/venv/bin/activate"
			set -o nounset

			# add poetry
			ynh_hide_warnings "$install_dir/app/machine-learning/venv/bin/pip3" install --upgrade poetry

			# poetry install
			ynh_hide_warnings "$install_dir/app/machine-learning/venv/bin/poetry" install --no-root --with dev --with cpu
		)
		cp -a "$source_dir/machine-learning/ann" "$install_dir/app/machine-learning/"
		cp -a "$source_dir/machine-learning/log_conf.json" "$install_dir/app/machine-learning/"
		cp -a "$source_dir/machine-learning/gunicorn_conf.py" "$install_dir/app/machine-learning/"
 		cp -a "$source_dir/machine-learning/app" "$install_dir/app/machine-learning/"
		# Install custom start.sh script
			ynh_config_add --template="$app-machine-learning-start.sh" --destination="$install_dir/app/machine-learning/start.sh"

	# Install geonames
		mkdir -p "$source_dir/geonames"
		cd "$source_dir/geonames"
		curl -LO "https://download.geonames.org/export/dump/cities500.zip" 2>&1
		curl -LO "https://download.geonames.org/export/dump/admin1CodesASCII.txt" 2>&1
		curl -LO "https://download.geonames.org/export/dump/admin2Codes.txt" 2>&1
		curl -LO "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson" 2>&1
		unzip "cities500.zip"
		mkdir -p "$install_dir/app/geodata/"
		cp -a "$source_dir/geonames/cities500.txt" "$install_dir/app/geodata/"
		cp -a "$source_dir/geonames/admin1CodesASCII.txt" "$install_dir/app/geodata/"
		cp -a "$source_dir/geonames/admin2Codes.txt" "$install_dir/app/geodata/"
		cp -a "$source_dir/geonames/ne_10m_admin_0_countries.geojson" "$install_dir/app/geodata/"
		date --iso-8601=seconds | tr -d "\n" > "$install_dir/app/geodata/geodata-date.txt"

	# Install sharp
		cd "$install_dir/app"
		ynh_hide_warnings npm install sharp

	# Retrieve dependencies version
		ffmpeg_version=$("$install_dir/ffmpeg-static/ffmpeg" -version | grep "ffmpeg version" | cut -d" " -f3)

	# Cleanup
		ynh_safe_rm "$source_dir"
}

# Execute a psql command as root user
# usage: myynh_execute_psql_as_root --sql=sql [--database=database]
# | arg: -s, --sql=         - the SQL command to execute
# | arg: -d, --database=    - the database to connect to
myynh_execute_psql_as_root() {
	# Declare an array to define the options of this helper.
	local legacy_args=sd
	local -A args_array=([s]=sql= [d]=database=)
	local sql
	local database
	# Manage arguments with getopts
	ynh_handle_getopts_args "$@"
	database="${database:-}"

	if [ -n "$database" ]
	then
		database="--dbname=$database"
	fi

	LC_ALL=C sudo --login --user=postgres PGUSER=postgres PGPASSWORD="$(cat $PSQL_ROOT_PWD_FILE)" \
		psql --cluster="$(postgresql_version)/main" "$database" --command="$sql"
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
	databases=$(myynh_execute_psql_as_root --sql="SELECT datname FROM pg_database WHERE datistemplate = false OR datname = 'template1';" --database="postgres")

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
	sudo --login --user=postgres pg_dump --cluster="$(postgresql_version)/main" --dbname="$app" > db.sql
}

# Restore the database
myynh_restore_psql_db() {
	# https://github.com/immich-app/immich/issues/5630#issuecomment-1866581570
	ynh_replace --match="SELECT pg_catalog.set_config('search_path', '', false);" \
		--replace="SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);" --file="db.sql"

	sudo --login --user=postgres PGUSER=postgres PGPASSWORD="$(cat $PSQL_ROOT_PWD_FILE)" \
		psql --cluster="$(postgresql_version)/main" --dbname="$app" < ./db.sql
}


# Set permissions
myynh_set_permissions() {
	chown -R $app: "$install_dir"
	chmod u=rwX,g=rX,o= "$install_dir"
	chmod -R o-rwx "$install_dir"

	chmod +x "$install_dir/app/start.sh"
	chmod +x "$install_dir/app/machine-learning/start.sh"

	chown -R $app: "$data_dir"
	chmod u=rwX,g=rX,o= "$data_dir"
	chmod -R o-rwx "$data_dir"

	chown -R $app: "/var/log/$app"
	chmod u=rw,g=r,o= "/var/log/$app"
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
}
