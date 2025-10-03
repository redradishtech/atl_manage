#!/bin/bash

###################################################
# ZFS
###################################################

zfs_datadir_filesystem() {
	local fs=${ATL_ZFSPOOL}$ATL_DATADIR
	zfs_filesystem_exists "$fs" || fail "Could not find ZFS filesystem for ATL_DATADIR: $fs"
	echo "$fs"
}

zfs_filesystem_mounted_at() {
	local fs
	fs=$(zfs list -H -r -o mountpoint,name "$ATL_ZFSPOOL" | awk -v mount="$1" '$1==mount {print $2}')
	[[ -n $fs ]] && echo "$fs" || {
		echo >&2 "No ZFS filesystem is mounted at $1"
		return 1
	}
}

zfs_delete_snapshot_if_exists() {
	local snapshot_name="$1"
	while read -r name; do
		if [[ "$name" = "$snapshot_name" ]]; then
			zfs destroy "$snapshot_name"
		fi
		# If the snapshot doesn't exist, 'zfs list' returns false which triggers the nonzero exit handler - hence the '|| true'
	done < <(zfs list -Ht snapshot -o name "$snapshot_name" 2>/dev/null || true)
}

zfs_delete_snapshot_and_dependents_if_exists() {
	local snapshot_name="$1"
	while read -r name; do
		if [[ "$name" = "$snapshot_name" ]]; then
			zfs destroy -R "$snapshot_name"
		fi
		# If the snapshot doesn't exist, 'zfs list' returns false which triggers the nonzero exit handler - hence the '|| true'
	done < <(zfs list -Ht snapshot -o name "$snapshot_name" 2>/dev/null || true)
}

zfs_filesystem_exists() {
	local filesystem_name="$1"
	[[ "$filesystem_name" = "$(zfs list -Ht filesystem -o name "$filesystem_name" 2>/dev/null)" ]]
}

zfs_snapshot_exists() {
	local snapshot_name="$1"
	[[ "$snapshot_name" = "$(zfs list -Ht snapshot -o name "$snapshot_name" 2>/dev/null)" ]]
}

zfs_delete_filesystem_if_exists() {
	local filesystem_name="$1"
	if zfs_filesystem_exists "$filesystem_name"; then
		zfs destroy -r "$filesystem_name" # Note: recursive, to include -workingcopy variants
		#zfs destroy "$filesystem_name"  # Note: recursive, to include -workingcopy variants
	fi
}

zfs_create_filesystem_if_not_exists() {
	local filesystem_name="$1"
	local filesystem_parent
	if ! zfs_filesystem_exists "$filesystem_name"; then
		fileystem_name="$(echo "$filesystem_name" | sed 's:/*$::')" # Trim trailing slashes
		filesystem_parent="${filesystem_name%/*}"
		if ! zfs_filesystem_exists "$filesystem_parent"; then
			echo >&2 "Cannot create ZFS filesystem '$filesystem_name', as its parent '$filesystem_parent' does not exist. Please manually create it. We cannot do so automatically as that would require ensuring all path components in '$filesystem_parent' have clean (empty) mountpoints"
			return 1
		fi
		#	ACLs so we can have locked-down permissions yet still grant rX permission as needed with setfacl -m u:user:rX
		# TODO: perhaps set exec=off here, and have another variant of this function that sets exec=on?
		# Note: no -p. Say we have ZFS filesystem tank2002/home/jturner/ with subdirectory 'redradishtech/'. Now we run 'zfs create -p tank2020/home/jturner/redradishtech/clients/newclient'. This mounts a blank filesystem over /home/jturner/redradishtech (and every subdir), masking the real contents!
		# The overlay=off means this fs cannot be mounted in a populated directory, which would seem to be the safe default. For some reason overay=on on systems I've checked.
		zfs create -o overlay=off -o acltype=posixacl "$filesystem_name" # Note: recursive, to include -workingcopy variants
		_zfs_create_sanoid_snapshots "$filesystem_name"
		#zfs destroy "$filesystem_name"  # Note: recursive, to include -workingcopy variants
	fi
}

zfs_snapshot() {
	local tag="$1"
	zfs_delete_snapshot_if_exists "$tag"
	zfs snapshot "$tag"
}

# Takes snapshot $3 of filesystem $1, and clone it to $2, with all sanoid snapshots
zfs_clone() {
	local x
	(( $# == 3 )) || fail "Usage: zfs_clone SRC DEST SNAPSHOTNAME"
	local srcfs="$1"
	local destfs="$2"
	local snapshotname="$3"
	zfs_filesystem_exists "$srcfs" || fail "Asked to clone $srcfs, but it does not exist"
	! zfs_filesystem_exists "$destfs" || fail "Asked to clone $srcfs to $destfs, but $destfs already exists"
	[[ $srcfs =~ ^$ATL_ZFSPOOL ]] || fail "$srcfs is not in pool $ATL_ZFSPOOL"
	[[ $destfs =~ ^$ATL_ZFSPOOL ]] || fail "$destfs is not in pool $ATL_ZFSPOOL"
	(( ${#snapshotname} > 3 )) || fail "ZFS snapshot name '$snapshotname' is too short"
	local snap="$srcfs@$snapshotname"
	! zfs_snapshot_exists "$snap" || fail "ZFS snapshot '$snap' already exists, so we can't create it for a clone operation"
	zfs_snapshot	"$snap"
	zfs clone		"$snap"	"$destfs"
	_zfs_create_sanoid_snapshots "$destfs"

}

# Create Sanoid-like snapshots, to prevent sanoid --monitor-snapshots complaining that they are missing. 
_zfs_create_sanoid_snapshots() {
	local fs="$1"
	# Note: if you're wondering why sanoid isn't noticing the new snapshots, run sanoid --force-update
	zfs snapshot "$fs@$(date +autosnap_%Y-%m-%d_%H:%M:%S_hourly)"
	zfs snapshot "$fs@$(date +autosnap_%Y-%m-%d_%H:%M:%S_daily)"
	zfs snapshot "$fs@$(date +autosnap_%Y-%m-%d_%H:%M:%S_weekly)"
	zfs snapshot "$fs@$(date +autosnap_%Y-%m-%d_%H:%M:%S_monthly)"

}
