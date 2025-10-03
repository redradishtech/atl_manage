#shellcheck shell=bash

if [[ -v ATL_ENVDIR && ! -v ATL_SHORTNAME && -r "$ATL_ENVDIR" ]]; then
	# If our script was invoked as non-root, it won't have any ATL vars, but $ATL_MANAGE/lib/remote/run will at least have set ATL_ENVDIR, telling us where, should
	# we have permission, we could source .env from. If we do have permission (e.g. sudo'd) then source $ATL_ENVDIR
	. "$ATL_ENVDIR"
fi

log() {
	echo >&2 "$*"
}
warn() {
	echo >&2 "!! $*"
}

fail() {
	echo >&2 "$*"
	exit 1
}

error() {
	echo >&2 "$*"
	exit 1
}

gethomedir() {
	# https://unix.stackexchange.com/questions/247576/how-to-get-home-given-user
	getent passwd "$1" | cut -d: -f6
}

# Export these vars so they pass through ./sync to ../lib/remote/run
export destination_type=backupmirror
export destination_type_rootdir="$ATL_APPDIR/backups"
export SOURCE=ATL_BACKUPMIRROR_SOURCE
export DESTINATION=ATL_BACKUPMIRROR_DESTINATION
export SOURCE_HOST=ATL_BACKUPMIRROR_SOURCE_HOST
export SOURCE_HOST_UNAME=ATL_BACKUPMIRROR_SOURCE_HOST_UNAME
export SOURCE_SYNCUSER=ATL_BACKUPMIRROR_SOURCE_SYNCUSER
export DESTINATION_SYNCUSER=ATL_BACKUPMIRROR_DESTINATION_SYNCUSER
export DESTINATION_HOST=ATL_BACKUPMIRROR_DESTINATION_HOST
export DESTINATION_PORT=ATL_BACKUPMIRROR_DESTINATION_PORT
export DESTINATION_HOST_UNAME=ATL_BACKUPMIRROR_DESTINATION_HOST_UNAME
export DESTINATION_APPDIR_BASE=ATL_BACKUPMIRROR_DESTINATION_APPDIR_BASE

issource() { [[ -v $SOURCE ]]; }
isdestination() { [[ -v $DESTINATION ]]; }
is_source_or_destination() {
	if ! issource && ! isdestination; then
		# This is normal for apps that don't use backup mirrors, but still have backups-mirror in their patchqueue
		return 1
	fi
}

if issource && isdestination; then
	error "Error: can't be both primary and standby (both $SOURCE (${!SOURCE}) and $DESTINATION (${!DESTINATION}) vars set)"
fi

hassource() { [[ -v $SOURCE_HOST ]]; }
hasdestination() { [[ -v $DESTINATION_HOST ]]; }

# Our replication system mirrors the primary $ATL_DATADIR to this directory on the standby, before then syncing it to the standby ATL_DATADIR.
# This is a directory inside $ATL_DATADIR so that if using ZFS, with a complete ZFS filesystem per version, our mirror is in the same filesystem as its ultimate destination, so that the final copy (with hardlinks) works. The directory is hidden (starts with .) so 'cp -al' in events/install-post/replication omits it
# This path is used in a few scripts (replication/sync_filesystem, events/install-post/replication, backupmirror/sync_backup, monitoring/plugins/check_replication_filesystem) but we don't hardcode it in atl_profile because our default value depends on ATL_REPLICATION_PRIMARY_HOST, which (in our current atl_profile implementation) isn't known till after the defaults are set when all profile files (such as '[org=foo]') are sourced.
# Defined canonically in $ATL_MANAGE/replication/common.sh
if [[ -v ATL_REPLICATION_PRIMARY_HOST_UNAME ]]; then
	ATL_REPLICATION_STANDBY_MIRRORDIR=".mirror-from-$ATL_REPLICATION_PRIMARY_HOST_UNAME"
fi
