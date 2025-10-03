# shellcheck shell=bash

# The --no_profile_needed is required - the caller (e.g. 'nagios') may not ATL_PROFILEDIR set or permission to access it.
#shellcheck source=/opt/atl_manage/lib/common.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"/../../lib/common.sh --no_profile_needed --nolog

# Sets $newest_file_age_days and $newest_file_age_secs, being the time since the most recent file in $1 has been modified. If no files exist in $1 both variables will be blank.
# Rsync excludes can be passed as further args.
find_youngest_file()
{
	if [[ $1 =~ ^--no-younger-than=.+ ]]; then
		youngestfile="${1#--no-younger-than=}"; shift
		[[ -f "$youngestfile" ]] || warn "Given arg $1 but file $youngestfile does not exist or is not readable"
	fi

	#shellcheck disable=SC2034
	while read -r tstamp newest
	do
		newest_filename="$newest"    # Variables defined *by* the while loop aren't defined out of it.
		(( now_secs=$(date +%s) ))
		newest_file_secs=$tstamp
		# let newest_file_secs=$(find -L $ATL_DATADIR/attachments -type f -printf '%T@.%p\n' | sort -n | tail -1 | cut -f1 -d.)
		newest_file_age_secs=$(( now_secs - newest_file_secs ))
		newest_file_age_days=$(( newest_file_age_secs / 60 / 60 / 24 ))
		# Say our newest source file is 3 days old, and $warndelay is 1 day. We would then allow backup files to be up to 3+1=4 days old.
		# Say our newest source file is 1 hour old, and $warndelay is 1 day. We should then allow backup files to be up to 1d 1h old, but since we can't work in part-days, always round up.
		(( newest_file_age_days++ )) || true
	done < <(rsync -rL --list-only "$@" | grep -v '^d' | rsync_to_time_and_filename | sort -k1r | filter_tooyoung_files "${youngestfile:-}" | head -1)

	# FIXME: this won't handle paths containing colons. See findlatest
}

# Given a line like:
# -rw-r-----            328 2021/11/09 22:40:42 current/dbconfig.xml
# outputs:
# 1636458042      current/dbconfig.xml
# being the timestamp in epoch format, and the filename (whitespace allowed), tab-separated
rsync_to_time_and_filename() {
	# Note that this can create a large file in $TMPDIR. Set ATL_TMPDIR=$ATL_APPDIR/temp to get it onto a bigger partition
	awk '{
	split($3, dateArr, "/"); split($4, timeArr, ":"); time=mktime(dateArr[1] " " dateArr[2] " " dateArr[3] " " timeArr[1] " " timeArr[2] " " timeArr[3]);
	printf "%s\t", time;
	for(i=5; i<=NF; i++) printf "%s%s", $i, (i<NF ? " " : "\n");
	}'
}

filter_tooyoung_files() {
	local youngestfile="$1"
	if [[ -n "$youngestfile" ]]; then
		youngestepoch="$(stat -c "%W" "$youngestfile" || :)"
		#youngest="$(date -d "${ATL_BACKUP_HOURLY_FREQUENCY} hours ago" +%s)"
		awk -v youngest="$youngestepoch" '$1 < youngest { print }' || :
	else
		tee
	fi
} 

failcritical()
{
	echo "$1"
	exit 2
}

failwarn()
{
	echo "$1"
	exit 1
}

