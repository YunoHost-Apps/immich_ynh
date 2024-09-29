#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

# NodeJS required version
nodejs_version=20
npm_with_node_options="node --max-old-space-size=$((($(ynh_get_ram --free) - (1024/2))/1024*1024)) $(which npm)"

# Fail2ban
failregex="immich-server.*Failed login attempt for user.+from ip address\s?<ADDR>"

# PostgreSQL required version
postgresql_version() {
	ynh_read_manifest "resources.apt.extras.postgresql.packages" \
	| grep -o 'postgresql-[0-9][0-9]-pgvector' | head -n1 | cut -d'-' -f2
}

# Retrieve full latest python version from major version
# usage: py_latest_from_major --python="3.8"
# | arg: -p, --python=    - the major python version
myynh_py_latest_from_major() {
	# Declare an array to define the options of this helper.
	local legacy_args=u
	local -A args_array=( [p]=python= )
	local python
	# Manage arguments with getopts
	ynh_handle_getopts_args "$@"

	py_required_version=$(curl -Ls https://www.python.org/ftp/python/ \
						| grep '>'$python  | cut -d '/' -f 2 \
						| cut -d '>' -f 2 | sort -rV | head -n 1)
}

# Install specific python version
# usage: myynh_install_python --python="3.8.6"
# | arg: -p, --python=    - the python version to install
myynh_install_python() {
	# Declare an array to define the options of this helper.
	local legacy_args=u
	local -A args_array=( [p]=python= )
	local python
	# Manage arguments with getopts
	ynh_handle_getopts_args "$@"

	# Check python version from APT
	local py_apt_version=$(python3 --version | cut -d ' ' -f 2)

	# Usefull variables
	local python_major=${python%.*}

	# Check existing built version of python in /usr/local/bin
	if [ -e "/usr/local/bin/python$python_major" ]
	then
		local py_built_version=$(/usr/local/bin/python$python_major --version \
			| cut -d ' ' -f 2)
	else
		local py_built_version=0
	fi

	# Compare version
	if $(dpkg --compare-versions $py_apt_version ge $python)
	then
		# APT >= Required
		ynh_print_info "Using OS provided python3..."

		py_app_version="python3"

	else
		# Either python already built or to build
		if $(dpkg --compare-versions $py_built_version ge $python)
		then
			# Built >= Required
			py_app_version="/usr/local/bin/python${py_built_version%.*}"

			ynh_print_info "Using already python3 built version: $py_app_version"

		else
			# APT < Minimal & Actual < Minimal => Build & install Python into /usr/local/bin
			ynh_print_info "Building python3 : $python (may take a while)..."

			# Store current direcotry
			local MY_DIR=$(pwd)

			# Create a temp direcotry
			tmpdir_py="$(mktemp --directory)"
			cd "$tmpdir_py"

			# Download
			wget --output-document="Python-$python.tar.xz" \
				"https://www.python.org/ftp/python/$python/Python-$python.tar.xz" 2>&1

			# Extract
			tar xf "Python-$python.tar.xz"

			# Install
			cd "Python-$python"
			./configure --enable-optimizations
			ynh_hide_warnings make -j4
			ynh_hide_warnings make altinstall

			# Go back to working directory
			cd "$MY_DIR"

			# Clean
			ynh_safe_rm "$tmpdir_py"

			# Set version
			py_app_version="/usr/local/bin/python$python_major"
		fi
	fi
	# Save python version in settings
	ynh_app_setting_set --key=python --value="$python"

	# Print some version information
	ynh_print_info "Python version: $($py_app_version -VV)"
	ynh_print_info "Pip version: $($py_app_version -m pip -V)"
}

# Install immich
myynh_install_immich() {
	# Thanks to https://github.com/arter97/immich-native
	# Check https://github.com/immich-app/base-images/blob/main/server/Dockerfile for changes

	# Add ffmpeg-static direcotry to $PATH
		PATH="$ffmpeg_static_dir:$PATH"

	# Use ynh nodejs helper

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
		ynh_hide_warnings "$npm_with_node_options" ci
		ynh_hide_warnings "$npm_with_node_options" run build
		ynh_hide_warnings "$npm_with_node_options" prune --omit=dev --omit=optional

		cd "$source_dir/open-api/typescript-sdk"
		ynh_hide_warnings "$npm_with_node_options" ci
		ynh_hide_warnings "$npm_with_node_options" run build

		cd "$source_dir/web"
		ynh_hide_warnings "$npm_with_node_options" ci
		ynh_hide_warnings "$npm_with_node_options" run build

		mkdir -p "$install_dir/app/"
		cp -a "$source_dir/server/node_modules" "$install_dir/app/"
		cp -a "$source_dir/server/dist" "$install_dir/app/"
		cp -a "$source_dir/server/bin" "$install_dir/app/"
		cp -a "$source_dir/web/build" "$install_dir/app/www"
		cp -a "$source_dir/server/resources" "$install_dir/app/"
		cp -a "$source_dir/server/package.json" "$install_dir/app/"
		cp -a "$source_dir/server/package-lock.json" "$install_dir/app/"
		cp -a "$source_dir/LICENSE" "$install_dir/app/"
		# Install custom start.sh script
			ynh_config_add --template="immich-server-start.sh" --destination="$install_dir/app/start.sh"
		cd "$install_dir/app/"
		ynh_hide_warnings "$npm_with_node_options" cache clean --force

	# Install immich-machine-learning
		cd "$source_dir/machine-learning"
		mkdir -p "$install_dir/app/machine-learning"
		$py_app_version -m venv "$install_dir/app/machine-learning/venv"
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
 		cp -a "$source_dir/machine-learning/app" "$install_dir/app/machine-learning/"
		# Install custom start.sh script
			ynh_config_add --template="immich-machine-learning-start.sh" --destination="$install_dir/app/machine-learning/start.sh"

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
		ynh_hide_warnings "$npm_with_node_options" install sharp

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
}

# Update the database
myynh_update_psql_db() {
	for db in postgres "$app"
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
	local db_port=$(ynh_app_setting_get --key=psql_port)

	sudo --login --user=postgres pg_dump --port="$db_port" --dbname="$app" > db.sql
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
myynh_set_permissions () {
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
