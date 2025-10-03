# shellcheck shell=bash
# Functions relating to maintenance mode (atl_maintenance). Used in lib/profile.sh (for setting the prompt)

# Sadly we can't avoid repeated sourcing because although functions stick around, ATL_MAINTENANCE_MARKERFILE doesn't
# if [[ $(type -t _atl_maintenance_remaining) = function ]]; then return 0; fi   # Avoid sourcing this file more than once.

#shellcheck source=/opt/atl_manage/lib/common.sh
#. "$ATL_MANAGE/lib/common.sh"
statedir="${ATL_ROOT:-}"/var/lib/atl_manage
ATL_MAINTENANCE_MARKERFILE="$statedir"/in_maintenance.html # For simplicity let's assume being 'in maintenance' is a server-wide state, not per-app, hence --global
export ATL_MAINTENANCE_MARKERFILE

if [[ -f "$ATL_MANAGE/.in_maintenance" ]]; then rm "$ATL_MANAGE/.in_maintenance"; fi # Remove some time after Dec 2021

# Returns amount of time left in maintenance window (as $retval), and removes the maintenance marker file if it doesn't seem at all relevant
_atl_maintenance_remaining() {
	if [[ ! -f $ATL_MAINTENANCE_MARKERFILE ]]; then
		retval=
		return
	fi
	local maintenance_ends current_time time_remaining SECONDS_IN_HOUR time_remaining_hours time_remaining_minutes

	maintenance_ends="$(stat --printf='%Y' "$ATL_MAINTENANCE_MARKERFILE")"
	((current_time = $(date +%s)))
	((time_remaining = maintenance_ends - current_time)) || true # let returns 1 if the result is 0
	# Note the quoting so globbing doesn't break us. Bash is a horrible language
	((SECONDS_IN_HOUR = 60 * 60))
	# if time_remaining is less than SECONDS_IN_HOUR, 'let' returns exit code 1. We're fine with the result being 0
	((time_remaining_hours = time_remaining / SECONDS_IN_HOUR)) || true
	((time_remaining_minutes = time_remaining % SECONDS_IN_HOUR / 60))
	if ((time_remaining > -(12 * SECONDS_IN_HOUR))); then
		#shellcheck disable=SC2034
		retval="${time_remaining_hours}h${time_remaining_minutes}m"
	else
		if [[ -w $ATL_MAINTENANCE_MARKERFILE ]]; then
			log "Removing expired maintenance marker file (${time_remaining_hours}h${time_remaining_minutes}m expired): $ATL_MAINTENANCE_MARKERFILE"
			rm -f "$ATL_MAINTENANCE_MARKERFILE"
		fi
	fi
}
export -f _atl_maintenance_remaining
