#!/bin/bash -eu

set -o pipefail

main() {
	[[ $ATL_DATABASE_TYPE = mysql ]] || { fail "Database type is '$ATL_DATABASE_TYPE'; Not running atl_mysql $*" && exit; }
	local superuser quiet var mysqlcmd mysqlargs

	superuser=false
	quiet=true

	for var in "$@"; do
		case "$var" in
		--super*)
			superuser=true
			shift
			;;
		-q | --quiet) quiet=true ;; # Deprecated option, now quietness is the default
		--verbose)
			quiet=false
			shift
			;;
		-h | --help) usage ;;
		--)
			shift
			break
			;;
		*) break ;;
		esac
	done
	case "$(basename "$0")" in
		atl_mysql_createuser) warn "In future please use 'atl_mysql_user_create'";;
		atl_mysql_createdb) warn "In future please use 'atl_mysql_create'";;
		atl_mysqldumpall) warn "In future please use 'atl_mysql_dumpall'";;
		atl_mysql_dropdb) warn "In future please use 'atl_mysql_drop'";;
		atl_mysql_dropuser) warn "In future please use 'atl_mysql_user_drop'";;
		atl_mysql_rename) warn "In future please use 'atl_mysql_sql_rename'";;
	esac

	mysqlcmd=mariadb
	case "$(basename "$0")" in
	atl_mysql)
		mysqlargs+=(${ATL_DATABASE:+"--database=$ATL_DATABASE"})
		;;
	atl_mysql_super)
		# Same as atl_mysql --super, but does not load the current database. I thought this might be useful for multi-db restores, but probably 'atl_mysql --one-database' does the job
		superuser=true
		mysqlargs+=()
		;;
	atl_mysql_dumpall | atl_mysqldumpall)
		superuser=true
		mysqlcmd=mysqldump
		mysqlargs=(--add-drop-table --routines --events --opt --all-databases)
		;;
	atl_mysql_dump | atl_mysqldump)
		superuser=true
		# We used to pass the database with --databases, like this, but that prevents atl_mysqldump <tablename> from working.
		mysqlcmd=mysqldump
		mysqlargs=(--add-drop-table --routines --events --opt "$ATL_DATABASE")
		;;
	atl_mysql_create | atl_mysql_createdb)
		superuser=true
		# From https://confluence.atlassian.com/adminjiraserver/connecting-jira-applications-to-mysql-5-7-966063305.html
		mysqlargs=(-e "CREATE DATABASE IF NOT EXISTS \`${ATL_DATABASE:?}\` character set utf8mb4 COLLATE utf8mb4_general_ci \p;")
		;;
	atl_mysql_user_create | atl_mysql_createuser)
		superuser=true
		local sql="CREATE USER IF NOT EXISTS '$ATL_DATABASE_USER'@'$ATL_DATABASE_HOST' "
		if [[ -v ATL_DATABASE_PROTOCOL && $ATL_DATABASE_PROTOCOL = socket ]]; then
			sql+="identified with unix_socket; "
		else
			sql+="identified by '$ATL_DATABASE_PASSWORD'; "
		fi
		sql+="GRANT ALL PRIVILEGES on \`${ATL_DATABASE:?}\`.* to '$ATL_DATABASE_USER'@'$ATL_DATABASE_HOST'  \p;"
		mysqlargs=(-e "$sql")
		;;
	atl_mysql_drop | atl_mysql_dropdb)
		superuser=true
		mysqlargs=(-e "DROP DATABASE \`${ATL_DATABASE:?}\` \p;")
		;;
	atl_mysql_user_drop | atl_mysql_dropuser)
		superuser=true
		mysqlargs=(-e "DROP USER '$ATL_DATABASE_USER'@'$ATL_DATABASE_HOST' \p;")
		;;
	atl_mysql_sql_rename | atl_mysql_rename)
		# E.g.:
		# /*!50013 DEFINER=`coastec_jethro-test`@`%` SQL SECURITY DEFINER */
		# CREATE DATABASE /*!32312 IF NOT EXISTS*/ `je_superlongchu` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin */;

		perl -pe 's/(DEFINER=`)[^`]+(`)@`([^`]+)`/\1'"$ATL_DATABASE_USER"'`@`'"$ATL_DATABASE_HOST"'`/gm;
			s/^(-- Host: .*    Database: )[^ \n]*$/\1'"$ATL_DATABASE"'/g;
			s/^(-- Current Database: )[^ \n]*$/\1\`'"$ATL_DATABASE"'\`/g;
			s/^(USE )[^ \n]*;$/\1'\`"$ATL_DATABASE"\`';/g;
			s/^((?:CREATE|ALTER) DATABASE [^\`]*\`)[^\`]+(\`)/\1'"$ATL_DATABASE"'\2/g;
			s/^(-- Dumping (events|routines) for database '"'"')[^ \n]*'"'"'$/\1'"$ATL_DATABASE'"'/g;'
		exit 0
		;;
	atl_mysql_sql_rename_owner)
		# Rename just the owner, not the database name. This is good for restoring multi-database backups, where the .sql file contains multiple 'USE <dbname>;' statements that shouldn't be messed with.
		perl -pe 's/(DEFINER=`)[^`]+(`)@`([^`]+)`/\1'"$ATL_DATABASE_USER"'`@`'"$ATL_DATABASE_HOST"'`/gm;'
		exit 0
		;;
	atl_mysqlimport)
		mysqlcmd=mysqlimport
		mysqlargs=( "$ATL_DATABASE")
		;;
	atl_mysqladmin)
		mysqlcmd=(mysqladmin)
		superuser=true
		;;
	atl_mysql_user_passwordset)
		superuser=true
		mysqlargs=(-e "alter user '$ATL_DATABASE_USER'@'$ATL_DATABASE_HOST' identified by '$ATL_DATABASE_PASSWORD' \p; flush privileges; \p;")
		;;
	atl_mysql_user_unixauthset)
		superuser=true
		mysqlargs=(-e "alter user '$ATL_DATABASE_USER'@'$ATL_DATABASE_HOST' identified with unix_socket \p; flush privileges; \p;")
		;;
	*)
		fail "Unhandled command: $(basename "$0")"
		;;
	esac

	if ! $superuser && [[ -v ATL_DATABASE_PROTOCOL && $ATL_DATABASE_PROTOCOL = socket ]]; then
		# Socket auth: run $mysqlcmd as $ATL_USER, relying on there being a working ~/.my.cnf for $ATL_USER.
		# Note, --super only works via TCP currently.
	
		mysqlcmd=("$mysqlcmd" "${mysqlargs[@]}")
		# We want the history file owned by the caller, not ATL_USER which may not have write access to its home dir.
		export MYSQL_HISTFILE=$(mktemp)
		permanent_histfile=~/.mysql_history-"${ATL_DATABASE:-}"
		if [[ -f $permanent_histfile ]]; then
			cp "$permanent_histfile" "$MYSQL_HISTFILE"
		fi
		chown "$ATL_USER" "$MYSQL_HISTFILE"
		# Connect as ATL_USER so that it is the DEFINER for created db objects.
		runuser -u "$ATL_USER" -- "${mysqlcmd[@]}" "$@"
		cp "$MYSQL_HISTFILE" ~/.mysql_history-"${ATL_DATABASE:-}"
		
	else
		# TCP auth. Run as the current user, but with a hand-rolled .my.cnf containing all the settings

		TMP_CNF="$(mktemp)"
		trap 'rm -f "$TMP_CNF"' EXIT TERM
		cat > "$TMP_CNF" <<-EOF
		# Generated for a temporary $mysqlcmd invocation, $(date)
		[client]
		# Note that if host is 'localhost' then MySQL uses a socket where possible even if protocol=tcp is specified
		host=$ATL_DATABASE_HOST
		port=$ATL_DATABASE_PORT
		ssl-verify-server-cert=off
		EOF
		# Set password as env var rather than --password to stop MySQL complaining. https://www.codingwithjesse.com/blog/mysql-using-a-password-on-the-command-line-interface-can-be-insecure/
		if $superuser; then
			#export MYSQL_PWD="$ATL_DATABASE_SUPERPASSWORD"
			cat >> "$TMP_CNF" <<-EOF
			user=$ATL_DATABASE_SUPERUSER
			password='$ATL_DATABASE_SUPERPASSWORD'
			EOF
		else
			echo >&2 "We are NOT superuser"
			#export MYSQL_PWD="$ATL_DATABASE_PASSWORD"
			{
				if [[ -v ATL_DATABASE_USER ]]; then
					echo "user=$ATL_DATABASE_USER"
				else
					echo "# ATL_DATABASE_USER was unset"
				fi
				if [[ -v ATL_DATABASE_PASSWORD ]]; then
					echo "password='$ATL_DATABASE_PASSWORD'"
				else
					echo "# ATL_DATABASE_PASSWORD was unset"
				fi
			} | cat >> "$TMP_CNF"
		fi

		# With mysql, later args take precedence over earlier ones. This is handy, as it means args like --database=abc or --protocol=socket can be specified, and will override the defaults set above.
		# In the case of atl_mysql --super, ATL_DATABASE may be unset (as straight after ej_create).
		# The --defaults-file overrides ~/.my.cnf which contains who-knows-what
		mysqlcmd=("$mysqlcmd" "--defaults-file=$TMP_CNF" "${mysqlargs[@]}")
		MYSQL_HISTFILE=~/.mysql_history-"${ATL_DATABASE:-}" "${mysqlcmd[@]}" "$@"
	fi
}

usage() {
	echo >&2 "Purpose: Connects to the $ATL_DATABASE database with RW access, as the $ATL_DATABASE_USER user."
	cat >&2 <<-EOF

		Usage:
		$0 <[options]> <psql_options and commands>

		Options:
		-h              Show this message
		--verbose       Print information about the database we're connecting to
		--super[user]   Run superuser, rather than \$ATL_DATABASE_USER ($ATL_DATABASE_USER)
	EOF
	exit
}

main "$@"
