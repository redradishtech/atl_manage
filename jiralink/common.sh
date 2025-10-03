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
export destination_type=jiralink
export destination_type_rootdir="$ATL_APPDIR/jiralink"
export SOURCE=ATL_JIRALINK_SOURCE
export DESTINATION=ATL_JIRALINK_DESTINATION
export SOURCE_HOST=ATL_JIRALINK_SOURCE_HOST
export SOURCE_HOST_UNAME=ATL_JIRALINK_SOURCE_HOST_UNAME
export SOURCE_SYNCUSER=ATL_JIRALINK_SOURCE_SYNCUSER
export DESTINATION_SYNCUSER=ATL_JIRALINK_DESTINATION_SYNCUSER
export DESTINATION_HOST=ATL_JIRALINK_DESTINATION_HOST
export DESTINATION_PORT=ATL_JIRALINK_DESTINATION_PORT
export DESTINATION_HOST_UNAME=ATL_JIRALINK_DESTINATION_HOST_UNAME
export DESTINATION_APPDIR_BASE=ATL_JIRALINK_DESTINATION_APPDIR_BASE
export SYNCUSER=ATL_JIRALINK_SYNCUSER
[[ ! -v $SOURCE_SYNCUSER || ${!SOURCE_SYNCUSER} == root ]] || fail "$SOURCE_SYNCUSER should be set to root, as our custom-launched sshd allows it and we need root-like permissions to rsync all the content from source"
[[ ! -v $DESTINATION_SYNCUSER || ${!DESTINATION_SYNCUSER} != root ]] || fail "$DESTINATION_SYNCUSER is set to root. We should always SSH as non-root, to avoid problems on locked-down instances, and then rely on sudo"

issource() { [[ -v $SOURCE ]]; }
isdestination() { [[ -v $DESTINATION ]]; }
is_source_or_destination() {
	if ! issource && ! isdestination; then
		warn "Neither $SOURCE nor $DESTINATION is set"
		return 1
	fi
}

if issource && isdestination; then
	error "Error: can't be both primary and standby (both $SOURCE (${!SOURCE}) and $DESTINATION (${!DESTINATION}) vars set)"
fi

hassource() { [[ -v $SOURCE_HOST ]]; }
hasdestination() { [[ -v $DESTINATION_HOST ]]; }
