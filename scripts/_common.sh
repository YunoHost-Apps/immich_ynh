#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

# Postgresql version
psql_version=17
db_cluster="$psql_version/main"

# Fail2ban
failregex="$app-server.*Failed login attempt for user.+from ip address\s?<ADDR>"

# App path
app_dir="$install_dir/immich/app"

# Check hardware requirements
myynh_check_hardware() {
	# Definie local var
	local file_test

	# CPU: Prebuilt binaries for linux-x64 require v2 microarchitecture
	file_test="/lib64/ld-linux-x86-64.so.2"
	if [ -f "$file_test" ]
	then
		if ! $file_test --help | grep -q "x86-64-v2 (supported"
		then
			ynh_die "Your CPU is too old and not supported. Installation of $app is not possible on your system."
		fi
	fi
}

# Install geonames
mynh_install_geodata() {
	# Definie local var
	local tempdir

	# Create the temporary directory
	tempdir="$(mktemp -d)"
	cd "$tempdir"

	# Download files
	curl -LO "https://download.geonames.org/export/dump/cities500.zip" 2>&1
	curl -LO "https://download.geonames.org/export/dump/admin1CodesASCII.txt" 2>&1
	curl -LO "https://download.geonames.org/export/dump/admin2Codes.txt" 2>&1
	curl -LO "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson" 2>&1
	unzip "cities500.zip"

	# Copy built files
	mkdir -p "$app_dir/geodata/"
	cp -a "cities500.txt" "$app_dir/geodata/"
	cp -a "admin1CodesASCII.txt" "$app_dir/geodata/"
	cp -a "admin2Codes.txt" "$app_dir/geodata/"
	cp -a "ne_10m_admin_0_countries.geojson" "$app_dir/geodata/"

	# Update geodata-date
	date --iso-8601=seconds | tr -d "\n" > "$app_dir/geodata/geodata-date.txt"

	# Cleanup
	cd -
	ynh_safe_rm "$tempdir"
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
	local legacy_args=tsocd
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

	LC_ALL=C sudo --login --user=postgres PGUSER=postgres PGPASSWORD="$(cat "$PSQL_ROOT_PWD_FILE")" \
		"$tool" "$cluster" $options "$database" "$sql"
}

# For bookworm > Add postgresql packages from postgresql repo
myynh_install_postgresql() {
	ynh_print_info "Installing postgresql $psql_version..."
	ynh_apt_install_dependencies_from_extra_repository \
		--repo="deb https://apt.postgresql.org/pub/repos/apt $YNH_DEBIAN_VERSION-pgdg main $psql_version" \
		--key="https://www.postgresql.org/media/keys/ACCC4CF8.asc" \
		--package="libpq5 libpq-dev postgresql-$psql_version postgresql-$psql_version-pgvector postgresql-client-$psql_version"
}

# For bookworm > Provisionning the database on right postgresql cluster
myynh_provision_postgresql() {
	# Definie local var
	local db_pwd

	ynh_print_info "Provisionning database on postgresql $psql_version..."

	# Create the cluster if not existing
	if ! pg_lsclusters | grep -q "$db_cluster"
	then
		pg_createcluster ${db_cluster/\// } --start
	fi

	# Create the database in the cluster if not existing
	if [[ -z $(myynh_execute_psql_as_root --sql="\list $app" --options="--tuples-only --no-align" --database="postgres") ]]
	then
		db_pwd=$(ynh_app_setting_get --key=db_pwd)
		myynh_execute_psql_as_root --sql="CREATE DATABASE $app;"
		myynh_execute_psql_as_root --sql="CREATE USER $app WITH ENCRYPTED PASSWORD '$db_pwd';" --database="$app"
		myynh_execute_psql_as_root --sql="GRANT ALL PRIVILEGES ON DATABASE $app TO $app;" --database="$app"
	fi
}

# Set default cluster back to debian and remove autoprovisionned database and user created on wrong cluster
myynh_set_default_back_to_debian() {
	# Definie local var
	local default_port
	local config_file

	ynh_print_info "Setting default postgresql cluster back to debian default..."

	default_port=5432
	config_file="/etc/postgresql-common/user_clusters"

		# Retrieve informations about default psql cluster
		default_db_cluster=$(pg_lsclusters --no-header | grep "$default_port" | cut -d' ' -f1)
		default_psql_cluster=$(pg_lsclusters --no-header | grep "$default_port" | cut -d' ' -f2)
		default_psql_database=$(pg_lsclusters --no-header | grep "$default_port" | cut -d' ' -f5)

		# Remove non commented lines
		sed -i'.bak' -e '/^#/!d' "$config_file"

		# Add new line USER  GROUP   VERSION CLUSTER DATABASE
		echo -e "* * $default_db_cluster $default_psql_cluster $default_psql_database" >> "$config_file"

		# Remove the autoprovisionned database and user created on wrong cluster
		if ynh_psql_database_exists "$app"
		then
			ynh_psql_drop_db "$app"
		fi
		if ynh_psql_user_exists "$app"
		then
			ynh_psql_drop_user "$app"
		fi
}

# Add VectorChord package
mynh_add_vectorchord() {
	# Definie local var
	local tempdir

	ynh_print_info "Adding VectorChord postgresql extension..."

	# Create the temporary directory
	tempdir="$(mktemp -d)"

	# Download the deb files
	ynh_setup_source --dest_dir="$tempdir" --source_id="vchord"

	# Install the packages. Allow downgrades because apt decided bullseye > bookworm
	_ynh_apt_install --allow-downgrades "$tempdir/postgresql-17-vchord.deb"

	# The doc says it should be called only once, but the code says multiple calls are supported.
	# Also, they're already installed so that should be quasi instantaneous.
	ynh_apt_install_dependencies "postgresql-17-vchord"

	# Mark packages as dependencies, to allow automatic removal
	apt-mark auto "postgresql-17-vchord"

	# Include the extension
	myynh_execute_psql_as_root --sql="ALTER SYSTEM SET shared_preload_libraries = 'vchord'"
		ynh_systemctl --service="postgresql" --action="restart"

	# Cleanup
	ynh_safe_rm "$tempdir"
}

# Update the database
myynh_update_psql_db() {
	# Definie local var
	local current_db_cluster
	#local db_port -> should be global

	# On upgrade, check if the db is not yet on psql_version cluster and if no migrate it (aka dumb and restore the db to 17 + delete the db on 16)
	current_db_cluster=$(ynh_app_setting_get --key=db_cluster)
	if [[ -n ${YNH_APP_UPGRADE_TYPE:-} \
	&& $current_db_cluster != "$psql_version/main" ]]
	then
		ynh_print_info "Migrating database to new cluster..."
		# Dump db on old cluster
		myynh_dump_psql_db --cluster="$current_db_cluster"
		# Restore db on new cluster
		myynh_restore_psql_db --cluster="$psql_version/main"
		# Drop db on old cluster
		myynh_drop_psql_db --cluster="$current_db_cluster"
	fi

	# Fix collation version mismatch
	ynh_print_info "Updating databse..."
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

	# Give superuser permissions to immich user in immich db
	myynh_execute_psql_as_root --sql="ALTER USER $app WITH SUPERUSER;" --database="$app"

	# Retrieve and save the postgresql port of the cluster and save it in settings
	db_port=$(myynh_execute_psql_as_root --sql="\echo :PORT")
	ynh_app_setting_set --key=db_port --value="$db_port"

	# Save the cluster in the settings
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

	# Definie local var
	local db_pwd

	# Adjust the content cf. https://github.com/immich-app/immich/issues/5630#issuecomment-1866581570
	ynh_replace --match="SELECT pg_catalog.set_config('search_path', '', false);" \
		--replace="SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);" --file="db.sql"

	# Restore the db
	ynh_hide_warnings myynh_execute_psql_as_root --cluster="$cluster" --database="$app" < ./db.sql

	# Restore the password
	db_pwd="$(ynh_app_setting_get --key=db_pwd)"
	myynh_execute_psql_as_root --cluster="$cluster" --sql="ALTER USER $app WITH ENCRYPTED PASSWORD '$db_pwd';" --database="$app"
}

# Set permissions
myynh_set_permissions() {
	# Definie local var
	local files_list

	# Update permissions
	chown -R "$app:" "$install_dir"
	chmod u=rwX,g=rX,o= "$install_dir"
	chmod -R o-rwx "$install_dir"

	files_list=(
		"$app_dir/start.sh"
		"$app_dir/bin/start.sh"
		"$app_dir/machine-learning/start.sh"
		"$app_dir/machine-learning/ml_start.sh"
	)
	for file in "${files_list[@]}"; do
		if [ -f "$file" ]
		then
			chmod +x "$file"
		fi
	done

	if [[ -z ${YNH_APP_UPGRADE_TYPE:-} ]]
	then
		chown -R "$app:" "$data_dir"
		chmod u=rwX,g=rX,o= "$data_dir"
		chmod -R o-rwx "$data_dir"
	fi

	chown "$app:" "$data_dir/backups/restore_immich_db_backup.sh"
	chmod u=rwX,g=rX,o=X "$data_dir/backups/restore_immich_db_backup.sh"

	chown -R "$app:" "/var/log/$app"
	chmod u=rw,g=r,o= "/var/log/$app"

	# Upgade user groups
	if [ -n "$(getent group video)" ]
	then
		adduser --quiet "$app" video 2>&1
	fi
	if [ -n "$(getent group render)" ]
	then
		adduser --quiet "$app" render 2>&1
	fi
}
