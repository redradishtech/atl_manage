#shellcheck shell=bash

# shellcheck source=/opt/atl_manage/lib/zfs.sh
source "$ATL_MANAGE/lib/zfs.sh" --

if [[ -v ATL_ZFS ]]; then
	zfs_create_archive() {
		local base="$1"
		echo "**** Creating $1/old"
		zfs_create_filesystem_if_not_exists "${ATL_ZFSPOOL}$base/old"
		# Syncoid shouldn't back up this directory.
		zfs set syncoid:sync=false "${ATL_ZFSPOOL}$base/old"
	}

	# Used by $ATL_MANAGE/bin/switchver to move a version of a ZFS filesystem from $base/$oldver to $base/old/$oldver
	zfs_archive_oldversion() {
		local base="$1"
		local oldver="$2"
		set -x
		echo "*** Moving $base/$oldver to old/"
		zfs_delete_filesystem_if_exists "${ATL_ZFSPOOL}$base/old/$oldver"
		if [[ -L $base/old/$oldver ]]; then
			# This is what I would consider the normal case
			rm "$base/old/$oldver"
		fi
		if zfs_filesystem_exists "${ATL_ZFSPOOL}$base/$oldver"; then
			# 'unshare -m' is for https://github.com/openzfs/zfs/issues/6119
			unshare -m zfs rename "${ATL_ZFSPOOL}$base/$oldver" "${ATL_ZFSPOOL}$base/old/$oldver"
			zfs mount "${ATL_ZFSPOOL}$base/old/$oldver"
		else
			if [[ -d $base/$oldver ]]; then
				log "$base/$oldver is not its own ZFS filesystem (no ${ATL_ZFSPOOL}$base/$oldver), despite ATL_ZFS being set. Creating a ZFS filesystem under old/, and archiving contents there.."
				set -x
				zfs_create_filesystem_if_not_exists "${ATL_ZFSPOOL}$base/old/$oldver"
				rsync -ra "$base/$oldver/" "$base/old/$oldver"
				rm -r "${base:?}/$oldver"
				set +x
			fi
		fi
		set +x
	}

	# Used by $ATL_MANAGE/bin/switchver to move an old version of a ZFS filesystem from $base/old/$oldver to $base/$oldver
	zfs_unarchive_oldversion() {
		local base="$1"
		local oldver="$2"
		echo "*** Moving old/$oldver to $base"
		zfs_filesystem_exists "${ATL_ZFSPOOL}$base" || fail "We really really expected ${ATL_ZFSPOOL}$base to be a ZFS filesystem"
		if zfs_filesystem_exists "${ATL_ZFSPOOL}$base/$oldver"; then
			fail "While restoring $oldver from old/ archive, we unexpectedly have a ${ATL_ZFSPOOL}$base/$oldver ZFS filesystem, that would have been overwritten by that under old/$oldver"
		fi
		#zfs_delete_filesystem_if_exists "${ATL_ZFSPOOL}$base/old/$oldver"
		if [[ -L $base/$oldver ]]; then
			# This is what I would consider the normal case - a symlink to the old/$oldver directory
			rm "$base/$oldver"
		fi
		if zfs_filesystem_exists "${ATL_ZFSPOOL}$base/old/$oldver"; then
			# The usual case
			unshare -m zfs rename "${ATL_ZFSPOOL}$base/old/$oldver" "${ATL_ZFSPOOL}$base/$oldver"
			zfs mount "${ATL_ZFSPOOL}$base/$oldver"
		else
			if [[ -d $base/old/$oldver ]]; then
				log "$base/old/$oldver is not its own ZFS filesystem (no ${ATL_ZFSPOOL}$base/$oldver), despite ATL_ZFS being set. Creating a ZFS filesystem under old/, and unarchiving contents there.."
				set -x
				zfs_create_filesystem_if_not_exists "${ATL_ZFSPOOL}$base/$oldver"
				rsync -ra "$base/old/$oldver/" "$base/$oldver"
				rm -r "${base:?}/old/$oldver"
				set +x
			fi
		fi
		set +x
	}

	create_archive() {
		local base="$1"
		if zfs_filesystem_exists "${ATL_ZFSPOOL}$base"; then
			zfs_create_archive "$@"
		else
			_create_archive "$@"
		fi
	}
	archive_oldversion() {
		local base="$1"
		local oldver="$2"
		if zfs_filesystem_exists "${ATL_ZFSPOOL}$base/$oldver"; then
			zfs_archive_oldversion "$@"
		else
			_archive_oldversion "$@"
		fi
	}

	unarchive_oldversion() {
		local base="$1"
		local oldver="$2"
		if zfs_filesystem_exists "${ATL_ZFSPOOL}$base/old/$oldver"; then
			zfs_unarchive_oldversion "$@"
		else
			_unarchive_oldversion "$@"
		fi
	}

else
	create_archive() { _create_archive "$@"; }
	archive_oldversion() { _archive_oldversion "$@"; }
	unarchive_oldversion() { _unarchive_oldversion "$@"; }
fi

# shellcheck source=/opt/atl_manage/lib/versioned_directories/switchver
. "$ATL_MANAGE/lib/versioned_directories/switchver"
