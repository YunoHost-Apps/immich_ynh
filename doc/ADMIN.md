### No HEIC/HEIF support

This package provides support for the JPEG, PNG, WebP, AVIF (limited to 8-bit depth), TIFF, GIF and SVG (input) image formats.
**HEIC/HEIF file format is not supported** (see cf. https://github.com/YunoHost-Apps/immich_ynh/issues/40#issuecomment-2096788600).

### Proper backups

Always follow [3-2-1](https://www.backblaze.com/blog/the-3-2-1-backup-strategy/) backup plan for your precious photos and videos!

### Automatic Database Dumps (see [here](https://immich.app/docs/administration/backup-and-restore/#automatic-database-dumps))

In order to restore a backup done by __APP__ itself:
1. Open an shell session using **root**[^1]: `sudo su`

2. Go to the backups folder: `cd __DATA_DIR__/backups`

3. Restore a backup by launching that script: `bash restore_immich_db_backup.sh`

[^1]: you may still be able to login using `root` from the local network - or from a direct console on the server.
