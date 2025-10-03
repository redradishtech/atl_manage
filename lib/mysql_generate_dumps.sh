#!/bin/bash -eu
## Dumps a mysql database, or all of them into the current directory.
#
# Notes:
# A straightforwad mysqldump --all-databases gives error on restoring in a newer version of mysql:
#  ERROR 1728 (HY000) at line 2441: Cannot load from mysql.proc. The table is probably corrupted
# This error happens even when not using --routines.
# Hence we use logical per-database backups.  See
# See http://mysqlserverteam.com/upgrading-directly-from-mysql-5-0-to-5-6-with-mysqldump/

# pipefail so if mysqldump throws an error, this isn't obscured by '| zstd'
set -o pipefail

if [[ -d /var/lib/mysql/dump ]]; then
	echo >&2 "Warning: old location /var/lib/mysql/dump still exists. This should be deleted"
fi
#mysqldump --all-databases --routines --events -uroot -psecret --opt | zstd > mysqldump.sql.zstd
# Do not include --routines, as it results in a restore error:
# ERROR 1728 (HY000) at line 2441: Cannot load from mysql.proc. The table is probably corrupted
# Show grants. http://serverfault.com/questions/8860/how-can-i-export-the-privileges-from-mysql-and-then-import-to-a-new-server

CONN=(-u"$ATL_DATABASE_SUPERUSER" -p"$ATL_DATABASE_SUPERPASSWORD")
mysql "${CONN[@]}" --skip-column-names -A -e"SELECT CONCAT('SHOW GRANTS FOR ''',user,'''@''',host,''';') FROM mysql.user WHERE user<>''" | mysql "${CONN[@]}" --skip-column-names -A | sed 's/$/;/g' >mysql_grants.sql

if [[ ${1:-} ]]; then
	db="$*"
else
	db="$(mysql "${CONN[@]}" --skip-column-names -sBe 'show databases' | grep -E -v '^(information_schema|performance_schema)')"
	db="$(echo 'SELECT `schema_name` from INFORMATION_SCHEMA.SCHEMATA  WHERE `schema_name` NOT IN('"'information_schema', 'sys', 'performance_schema'"');' | mysql "${CONN[@]}" --skip-column-names -sB)"
fi

for db in $db; do
	# --single-transaction gives us a consistent backup across tables, and no table locks. Requires InnoDB
	# Note that we don't use '--databases $db' as that would result in hardcoding the database name in the dump, which makes restoring to a differently-named database like $db-staging) hard. See https://dba.stackexchange.com/questions/8869/restore-mysql-database-with-different-name
	mkdir "$db"
	dumpopts=(--single-transaction --add-drop-table --routines --events --skip-dump-date --opt)
	mysqldump "${CONN[@]}" "${dumpopts[@]}" "$db" | zstd >"$db/$db.sql.zstd" || exit $?
	{
		echo "MySQL dump: $db.sql.zstd"
		echo "Generated: $(date)"
		echo "sha1sum: $(sha1sum "$db/$db.sql.zstd")"
		echo
		echo "To restore data: zstdcat $db.sql.zstd | sed -e 's/\`$db\`/\`'\$ATL_DATABASE'\`/g' | atl_mysql --super"
	} >>"$db"/README.txt
done
