#!/bin/bash -eu
# Intended to be symlinked from $ATL_APPDIR/.env/atl_* - this command invokes its namesake wrapped in atl_env found in the same directory. This allows e.g. $ATL_APPDIR/.env/atl_psql to be invoked from cron scripts and elsewhere, and run contextualized for the app.

ATL_MANAGE="$(dirname "$(realpath -m "${BASH_SOURCE[0]}"/..)")" # Figure out ATL_MANAGE (probably /opt/atl_manage) assuming ${BASH_SOURCE[0]} is a symlink to e.g. /opt/atl_manage/lib/atl_contextualized_command.sh
ourdir="$(realpath -m "$(dirname "${BASH_SOURCE[0]}")")"
atl_env="$ourdir/atl_env"
cmd="$(basename "$0")"
export PATH="$ATL_MANAGE/bin:/bin:$PATH" # We might have $ourdir in our path, in which case invoking $cmd would cause an infinite loop. Put the directories of our target $cmd in the path first.
#echo >&2 "$0 Running: $atl_env $(which "$cmd"): $cmd $*"
"$atl_env" "$cmd" "$@"
