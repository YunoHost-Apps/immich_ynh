### Proper backups

Always follow [3-2-1](https://www.backblaze.com/blog/the-3-2-1-backup-strategy/) backup plan for your precious photos and videos!

### Automatic Database Dumps (see [here](https://immich.app/docs/administration/backup-and-restore/#automatic-database-dumps))

In order to restore a backup done by __APP__ itself, use:

- embeded tool in [Maintenance](https://__DOMAIN__/admin/maintenance)

Or

- the homemade script with following commands: 

  1. Open an shell session using **root**[^1]: `sudo su`

  2. Go to the backups folder: `cd __DATA_DIR__/backups`

  3. Restore a backup by launching that script: `bash restore_immich_db_backup.sh`

[^1]: you may still be able to login using `root` from the local network - or from a direct console on the server.
