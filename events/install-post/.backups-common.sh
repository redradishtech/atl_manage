#!/bin/bash -eu

create_backup_directories() {
	create_or_complain() {
		if [[ ! -d $1 ]]; then
			$SUDO install -d "$1" -o root -g root -m 750
		else
			$SUDO chown root:root "$1"
			chmod 750 "$1"
			if [[ ! -w $1 ]]; then
				error "Cannot write to $1"
			fi
		fi
	}
	if [[ -v ATL_ZFS ]]; then
		setup_or_migrate_zfs_backupdir
	else
		install -d -g root -m 750 "$ATL_BACKUP_ROOT"
	fi
	# rsnapshot stores the db dump here.
	install -d -g root -m 750 "$ATL_BACKUP_TMP"
	install -d -g root -m 750 "$ATL_BACKUP_DATABASEDUMP"
	# We used to have to ensure that the 'postgres' user had write permission in ATL_BACKUP_DATABASEDUMP, because backups were done as 'postgres' on localhost. That is no longer the case now $ATL_MANAGE/lib/backup_database connects using the SUPERUSER account.

	# Nuke the database dump directory. Our lib/backup_database script (invoked via backups/rsnapshot.conf) will create subdirectories for each backed-up database, but this root might contain obsolete stuff.
	# Also flock it in case /etc/cron.d/*-backup-rsnapshot is busy using it
	# Print a warning if the lock is held, as otherwise we just block without explanation
	flock --nonblock -E123 "$ATL_LOCKDIR"/backup.lock true || {
		if [[ $? = 123 ]]; then
			warn "Waiting on a backup (holding lockfile $ATL_LOCKDIR/backup.lock) to finish before we can nuke the database dump dir: $ATL_BACKUP_DATABASEDUMP. The process holding the lock is: $(lsof "$ATL_LOCKDIR"/backup.lock)"
		fi
	}
	[[ -d "$ATL_LOCKDIR" ]] || fail "ATL_LOCKDIR ${ATL_LOCKDIR:-} does not exist. It should be created by the lib/appfetcher/ machinery, in particular by $ATL_MANAGE/lib/appfetcher.sh customize_atlmanage_apps()"
	flock -x "$ATL_LOCKDIR"/backup.lock rm -rf "${ATL_BACKUP_DATABASEDUMP?}"/*
	#install -d ${ATL_BACKUP_ROOT}/{home,database} -o root -g $ATL_GROUP -m 770
	# -g is 'FILE exists and is set-group-ID
	#test -g ${ATL_BACKUP_TMP}/latest-database-dump || $SUDO chmod g+s ${ATL_BACKUP_TMP}/latest-database-dump	# Ensure that backups are always readable but NOT writeable by $ATL_USER
	umask 0002 # Files should be group-writable. Note that is just new files created, not rsync'ed files, which should retain their native permissions.
}


setup_or_migrate_zfs_backupdir() {
	. "$ATL_MANAGE/lib/zfs.sh"
	local zfspool="${ATL_ZFSPOOL_BACKUPS:-$ATL_ZFSPOOL}"   # Allow for a different ZFS pool e.g. on a slower disk
	local zfsfs="${zfspool}$ATL_BACKUP_ROOT"
	if ! zfs_filesystem_exists "$zfsfs"; then
		if [[ -d $ATL_BACKUP_ROOT ]]; then
			migrate_backups_to_zfs
		else
			zfs_create_filesystem_if_not_exists "$zfsfs"
			[[ -d $ATL_BACKUP_ROOT ]] || fail "We created (?) ZFS filesystem $zfsfs, but that didn't seem to result in $ATL_BACKUP_ROOT existing"
			chmod 750 "$ATL_BACKUP_ROOT"
		fi
	fi
}

migrate_backups_to_zfs() {
	local zfsfs="${zfspool}${ATL_BACKUP_ROOT}"
	local zfsfs_tmp="${zfspool}${ATL_BACKUP_ROOT}-migratingtozfs"
	echo "$ATL_BACKUP_ROOT is not a dedicated filesystem. We want it to be, so we can avoid snapshotting it."
	read -rp "Do you want to migrate $ATL_BACKUP_ROOT to a dedicated filesystem now? (y/N) " yesno
	if [[ $yesno =~ [yY] ]]; then
		# rsync may fail e.g. if we run out of disk space, so copy to a 'migratingtozfs' dir until we're complete
		zfs_create_filesystem_if_not_exists "${zfsfs_tmp}"
		[[ -d $ATL_BACKUP_ROOT-migratingtozfs ]] || fail "Failed to create ZFS fs $zfsfs_tmp for backup. Please create it manually and move the contents of $ATL_BACKUP_ROOT into it"   # this shouldn't ever happen..
		echo "Now moving backups to the ZFS filesystem $zfsfs_tmp"
		set -x
		# Note the -H for preserving hardlinks between rsnapshot backups
		rsync -raH "${ATL_BACKUP_ROOT}/" "${ATL_BACKUP_ROOT}-migratingtozfs"
		rm -rf "$ATL_BACKUP_ROOT"
		zfs rename "${zfsfs_tmp}" "${zfsfs}"
		[[ -d $ATL_BACKUP_ROOT ]] || fail "Something went wrong. ZFS filesystem $zfsfs should be mounted at ATL_BACKUP_ROOT $ATL_BACKUP_ROOT"
		set +x
		echo "Backups moved to $ATL_BACKUP_ROOT"
	fi
}

dirempty() {
	[[ -z "$(find "$1" -mindepth 1 -print -quit)" ]]
}
check_backup_permissions() {
	#can_access_database()
	#{
	#	local user=$1
	#	usercount=$(echo "select count(*) from pg_user where usename='$user';" | $SUDO su - postgres -c "psql -tAq")
	#	[[ $usercount != 0 ]]
	#}
	test -r "$ATL_BACKUP_ROOT" || error "User $USER cannot access ATL_BACKUP_ROOT directory, $ATL_BACKUP_ROOT"

	if [[ $USER != root ]] && ! id -nG "$USER" | grep -qw "$ATL_USER"; then
		warn "$USER is not in $ATL_USER group, and so may not have access to the filesystem and $ATL_DATABASE database."
	fi
}

# vim: set ft=sh:
