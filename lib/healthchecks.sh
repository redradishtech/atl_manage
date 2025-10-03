#shellcheck shell=bash
# Functions that may be called from $ATL_APPDIR/*/*.healthcheck scripts.

# Purpose: Determines if any data in a database (or specific tables) has changed in the last INTERVAL
# Usage: mysql_database_changed_in_last MYSQL_INTERVAL DATABASE [TABLE1 [TABLE2...]]
# Where:
#    MYSQL_INTERVAL		E.g. '1 hour'
#    DATABASE			E.g. 'je_asne'
#	 TABLE1				E.g. '_person'
#	 TABLE2				E.g. 'settings'
# 
# The function returns zero if data has changed within MYSQL_INTERVAL, 1 otherwise
function mysql_database_changed_in_last() {
	local interval db where whereclause sql

	err() { echo "$*"; echo >&2 "Usage: ${FUNCNAME[1]} MYSQL_INTERVAL DATABASE TABLE1 TABLE2..."; return 1; }
	(( $# >= 2 )) || err
	interval="$1"; shift
	db="$1"; shift
	[[ $interval =~ ^[[:digit:]]\ (minute|hour|day)s?$ ]] || err "Invalid INTERVAL"
	[[ $db =~ je_[a-z]+ ]] || err "Invalid database name"
	declare -a where
	for tbl in "$@"; do
		[[ $tbl =~ [a-z_]+ ]] || err "Invalid format for table name '$tbl'"
		where+=("${tbl@Q}")
	done
	whereclause="TABLE_SCHEMA=${db@Q} and UPDATE_TIME > now() - interval $interval"
	if (( $# )); then
		whereclause+="$(IFS=','; echo " and TABLE_NAME in (${where[*]})"; )"
	fi
	sql="SELECT TABLE_SCHEMA, table_name, UPDATE_TIME FROM information_schema.tables WHERE $whereclause order by update_time desc;"
	out="$(atl_mysql --super -sNBe "$sql")"
	if [[ -n $out ]]; then
#		echo >&2 "The following tables have changed within $1:"
#		echo >&2 "$out"
		return
	else
		return 1
	fi
}

# Return true if any files in /var/lib/mysql/$1 have changed within $2 time period
# E.g. database_changed_in_last je_admin 1h
function database_changed_in_last() {
	local db="$1"; shift
	local period="$1"; shift
	if ! command -v fdfind > /dev/null; then
		echo >&2 "Warning: fdfind not installed"
		return 0   # Fail positive
	fi
	local dbdir="/var/lib/mysql/${db?}"
	if [[ ! -d $dbdir ]]; then
		echo >&2 "Missing database directory $dbdir"
		return 0
	fi
	fdfind -q -t file --changed-within ${period} . "$dbdir"
	return $?
}

