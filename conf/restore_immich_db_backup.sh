#!/bin/bash

source /etc/yunohost/apps/__APP__/scripts/_common.sh
source /usr/share/yunohost/helpers

backup_files=( "__DATA_DIR__/backups/"*.sql.gz )

PS3='Select file to restore, or 0 to exit: '
select backup_file in "${backup_files[@]}"
do
	if [[ $REPLY == "0" ]]
	then
		echo 'Bye!' >&2
		exit
	elif [[ -z $backup_file ]]; then
		echo 'Invalid choice, try again' >&2
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
	app=__APP__
	db_cluster=__DB_CLUSTER__
	db_name=__APP__

	ynh_systemctl --service="$app-server" --action="stop"

	myynh_drop_psql_db

	gunzip --stdout "$backup_file" > db.sql
	myynh_restore_psql_db
	ynh_safe_rm db.sql

	ynh_systemctl --service="$app-server" --action="start"

	echo 'Done!' >&2
	exit
else
	echo 'Bye!' >&2
	exit
fi
