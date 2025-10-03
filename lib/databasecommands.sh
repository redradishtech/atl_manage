#!/bin/bash

# Maps database-agnostic scripts (atl_sql, atl_dropdb etc) to their database-specific implementations.
# To just run a SQL statement, feed it to this command on stdin (atl_sql <<< 'select 1'). This is the only cross-database way that works: mysql uses -e and psql uses -c.

. /opt/atl_manage/lib/common.sh --nolog

cmd="$(basename "$0")"
args=

case "$ATL_DATABASE_TYPE" in
	*postgresql*) dbprefix="pg";;
	mysql) dbprefix="mysql";;
	*) fail "Unknown ATL_DATABASE_TYPE '$ATL_DATABASE_TYPE" ;;
esac

case "$cmd" in
	# atl_sql takes SQL on stdin
	atl_sql)
		case "$dbprefix" in
			pg)
				cmd="atl_psql"
				# -X is in case \timing is on in ~/.psqlrc
				args="-tAXq"
				;;
			mysql)
				cmd="atl_mysql"
				args="-sNB"
				;;
		esac
		;;
	atl_db_*) cmd="${cmd/atl_db_/atl_${dbprefix}_}";;
	atl_*) cmd="${cmd/atl_/atl_${dbprefix}_}";;
	*)
		fail "$cmd does not look like an atl_db command and should not be symlinked"
		;;
esac

if command -v $cmd >/dev/null; then
	exec "$cmd" $args "$@"
else
	error "Couldn't find «$cmd»"
fi
