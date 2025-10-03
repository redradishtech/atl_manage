#shellcheck shell=bash
# Invoked at the end of an event command, this snippet infers the event name
# from the subdirectory name (e.g. 'install-pre'), then calls the shell
# function ('install-pre' $@).
#
# This allows a single script file to be symlinked into various 'event'
# directories, and have different functions invoked depending on which symlink
# is called. For instance, we currently have 1 file with 3 events:
#
# install-post/backups-rsnapshot
# cleanup/backups-rsnapshot -> ../install-post/backups-rsnapshot
# uninstall-pre/backups-rsnapshot -> ../install-post/backups-rsnapshot

# Add bin/ to our path, e.g. so atl_psql works from events/start-pre/check_versioncompat
export PATH="$ATL_MANAGE/bin:$PATH"
# Aug/20: currently events scripts need functions 'cachedir', 'pkginstall', 'sudosnippet', 'version_lessthan', 'log' etc
# shellcheck source=/opt/atl_manage/lib/common.sh
. "$ATL_MANAGE"/lib/common.sh --nolog

# If not set explicitly (in $ATL_MANAGE/bin/atl_event), the event is the name of the directory containing the invoked command. The default lets us invoke scripts directly from the shell.
# Note that this must work if the script is symlinked to elsewhere (so we mustn't follow symlinks), and regardless of whether an absolute or relative (even ./) directory is used.
event="${ATL_EVENT:-$(basename "$(
	cd "$(dirname "$0")"
	pwd
)")}"

logdir="$ATL_APPDIR/$ATL_TOMCAT_SUBDIR"logs
eventdir="$logdir"/events/$(date +%Y%m%d-%H%M)_${event}

shopt -s nullglob
validateperms_healthcheck() {
	local dir="${1:?}" # Generally a subdir of $ATL_APPDIR like $ATL_APPDIR/monitoring
	[[ -d $dir ]] || {
		warn "$dir does not exist. Perhaps the hg patchqueue isn't applied?"
		return
	}
	for cfg in "$dir"/*.cfg; do
		sudo -u nagios test -r "$cfg" || error "Nagios cannot read file '$cfg'. To fix, 'hg qgoto <relevantpatch>; setfacl -m u:nagios:r[x] $cfg; hg acl save; hg commit --mq -m FixPerms"
	done
	# https://stackoverflow.com/questions/30009320/recursively-find-files-that-are-not-publicly-readable
	# Ignore vim swapfiles
	unreadable="$(find "$ATL_MANAGE" ! -perm -o=r -not -name "*\.*")" # This covers vim swap files and .in_maintenance markers
	if [[ -n $unreadable ]]; then
		# Permissions can get messed up after manually adding/removing things in $ATL_MANAGE. Let's try to fix ourselves before complaining
		(
			cd $ATL_MANAGE
			.hgpatchscript/worldreadable
		)
		unreadable="$(find "$ATL_MANAGE" ! -perm -o=r -not -name "*\.*")" # This covers vim swap files and .in_maintenance markers
		if [[ -n $unreadable ]]; then
			error "Some files are not world-readable in $ATL_MANAGE. This will prevent '$ATL_USER' from reading/executing scripts invoked via nagios checks. Files are: $unreadable"
		fi
	fi
}

only_in_nonproduction() {
	[[ $ATL_ROLE != prod ]] || exit 0
}

require_app() {
	for app in "$@"; do
		if [[ $ATL_PRODUCT = "$app" ]]; then
			return 0
		fi
	done
	exit 0
}

# Allows scripts to exit quietly if a required database table doesn't exist at all, as is the case initially in a blank database
require_table() {
	# https://stackoverflow.com/questions/20582500/how-to-check-if-a-table-exists-in-a-given-schema
	if [[ $(atl_psql -tAXqc "SELECT EXISTS ( SELECT 1 FROM pg_tables WHERE  schemaname = 'public' AND tablename = '$1');") != t ]]; then
		warn "Database not set up (no $1 table)"
		# Our database isn't set up. No point doing any consistency checks
		exit 0
	fi
}

fail() {
	if [[ -f $ATL_APPDIR/STARTUP_CHECK_OVERRIDE ]]; then
		warn "$@"
	else
		echo >&2 "$@"
		exit 2
	fi
}
