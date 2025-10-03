# shellcheck shell=bash

# Creates $ATL_DATADIR_BASE, and $ATL_DATADIR if set (i.e. if $ATL_VER is set)
_atl_create_new_datadir() {
	if [[ ! -d "$ATL_DATADIR_BASE" ]]; then
		if [[ -v ATL_ZFS ]]; then
			zfs_create_filesystem_if_not_exists "${ATL_ZFSPOOL}$ATL_DATADIR_BASE"
			# Set noexec - we don't want hackers dropping binaries in our home dir.
			zfs set exec=off "${ATL_ZFSPOOL}$ATL_DATADIR_BASE"
			chown "root:$ATL_GROUP" "$ATL_DATADIR_BASE"
		else
			install -d "$ATL_DATADIR_BASE" -o root -g "$ATL_GROUP"
		fi
	else
		if [[ -v ATL_ZFS ]]; then
			zfs_filesystem_exists "${ATL_ZFSPOOL}$ATL_DATADIR_BASE" || fail "The ATL_DATADIR_BASE directory $ATL_DATADIR_BASE exists but isn't under ZFS control - therefore we can't make a ZFS filesystem for our version beneath it"
		fi
	fi

	if [[ "${ATL_DATADIR_VERSIONED:-}" = true ]]; then
		if [[ -n ${ATL_VER-} && ! -d ${ATL_DATADIR:?} ]]; then
			if [[ -v ATL_ZFS ]]; then
				# From lib/zfs.sh
				zfs_create_filesystem_if_not_exists "${ATL_ZFSPOOL}$ATL_DATADIR"
				# Set noexec - we don't want hackers dropping binaries in our home dir.
				zfs set exec=off "${ATL_ZFSPOOL}$ATL_DATADIR"
				chown "$ATL_USER:$ATL_GROUP" "$ATL_DATADIR"
			else
				log "Creating $ATL_DATADIR"
				# Use our default 027 umask. This means data is inaccessible to non-root, non-$ATL_USER account, and special provision will have to be made .e.g. for nagios scripts running as other accounts (in events/*/*.sh scripts).
				install -d "$ATL_DATADIR" -o "$ATL_USER" -g "$ATL_GROUP"
			fi
			(
				cd "$ATL_DATADIR_BASE"
				if [[ ! -L current ]]; then
					ln -s "$ATL_VER" current
				fi
			)
		fi
	fi
}
