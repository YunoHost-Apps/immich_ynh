#!/bin/bash

source /etc/yunohost/apps/immich/scripts/_common.sh
YNH_HELPERS_VERSION="2.1" source /usr/share/yunohost/helpers

YNH_STDINFO=1
backup_files=( *.sql.gz )

PS3="Select backup file to restore, or 0 to exit:"
select backup_file in "${backup_files[@]}"
do
	if [[ $REPLY == "0" ]]
	then
			ynh_print_info "[####################] Bye!"
			exit
	elif [[ -z $backup_file ]]; then
				ynh_print_info "[....................] Invalid choice, try again"
	else
			break
	fi
done

cat << EOF

You select "$backup_file".

To proceed we are going to:
 1) stop immich
 2) drop the curent database
 3) restore the databse with the selected backup
 4) restart immich

EOF

read -r -p "Are you sure you want to continue restoring? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
	app="__APP__"
	db_cluster="__DB_CLUSTER__"
	db_name="__APP__"

	ynh_print_info "[+...................] Stopping immich..."
	ynh_systemctl --service="$app-server" --action="stop"

	ynh_print_info "[#+..................] Droping current immich db..."
	myynh_drop_psql_db 1>/dev/null

	ynh_print_info "[##+.................] Creating an empty immich db..."
	myynh_update_psql_db 1>/dev/null
	myynh_create_psql_db 1>/dev/null

	ynh_print_info "[###++++++++++++++++.] Restoring immich db backup... (Depending on your database size, this may take a long while)"
	{
		gunzip --stdout "$backup_file" > "db.sql"
		myynh_restore_psql_db
		ynh_safe_rm "db.sql"
		set +o xtrace
	} &>/dev/null

	ynh_print_info "[###################+] Restarting immich..."
	ynh_systemctl --service="$app-server" --action="start"

	ynh_print_info "[####################] Restoration of the immich db backup completed!"
else
	ynh_print_info "[####################] Bye!"
fi
