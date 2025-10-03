#!/bin/bash -eu
# A wrapper around Postgres commands (psql, createuser, dropuser, createdb, dropdb, pg_dump, pg_dumpall, pg_restore) that:
# - Uses the ATL_DATABASE_* variables to tell the command how to connect to the database
# - Does the 'default thing' to the relevant database (using ATL_DATABASE_* vars), if invoked with no args. For instance:
# -- 'atl_createuser' creates the $ATL_DATABASE_USER role with $ATL_DATABASE_PASSWORD password
# -- 'atl_dropuser' drops the $ATL_DATABASE_USER role
# -- 'atl_createdb' creates the $ATL_DATABASE database, using C locale for JIRA
# -- 'atl_dropdb' drops the $ATL_DATABASE database (after prompting for confirmation)
# - Provides a --superuser option which runs the command as ATL_DATABASE_SUPERUSER (normally 'postgres') and ATL_DATABASE_SUPERPASSWORD. The --superuser is implicitly used to achieve some of the 'default' behaviours.

set -o pipefail

pgcmd="$(basename "$0")"
pgcmd="${pgcmd#atl_}" # There is definitely an atl_ prefix.. (e.g. 'atl_psql')
if [[ ! -x /usr/bin/$pgcmd ]]; then
	pgcmd="${pgcmd#pg_}"
fi

main() {
	[[ $ATL_DATABASE_TYPE =~ postgresql ]] || { warn "Database type is '$ATL_DATABASE_TYPE'; Not running atl_psql $*" && exit; }
	superuser=false
	verbose=false

	# Iterate through command line arguments
	args=() # Store non-option args outside $@ for dropdb's benefit
	for arg in "$@"; do
		case $arg in
		--super*) superuser=true ;;
		--atlverbose) verbose=true ;;
		--help)
			usage "$@"
			passedargs+=("$arg")
			;;
		-*) passedargs+=("$arg") ;;
		*)
			passedargs+=("$arg")
			args+=("$arg")
			;;
		esac
	done
	# Update the original arguments with the arguments without --force
	set -- "${passedargs[@]}"

	for var in "$@"; do
		case "$var" in
		--super*)
			superuser=true
			shift
			;;
		-q | --quiet) quiet=true ;; # Deprecated option, now quietness is the default
		-v | --verbose)
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

	# Set variables up-front, and then specific commands
	export PGCONNECT_TIMEOUT=15 # Up to 7s for slow/remote SSH connections
	export PGHOST="$ATL_DATABASE_HOST"
	export PGPORT="$ATL_DATABASE_PORT"
	export PGDATABASE="$ATL_DATABASE"


	case "$(basename "$0")" in
		atl_pg_createuser) warn "Please use 'atl_pg_user_create'";;
		atl_pg_createdb) warn "Please use 'atl_pg_create'";;
		atl_pg_dropdb) warn "Please use 'atl_pg_drop'";;
		atl_pg_dropuser) warn "Please use 'atl_pg_user_drop'";;
		atl_pg_renameowner) warn "Please use 'atl_pg_sql_owner_change'"
	esac

	# This script is symlinked to all Postgres command wrappers (atl_psql, atl_pg_dump, etc). Here we add extra implied args depending on the command type.
	# The 'set --' sets the args ($1, $2) etc. We generally push the old args ($@) first, then extras

	case "$(basename "$0")" in
	atl_pg_restore)
		superuser=true
		#set -- "-d" "$ATL_DATABASE_USER"
		;;
	atl_pg_user_create | atl_pg_createuser)
		pgcmd=createuser
		superuser=true
		if [[ $ATL_DATABASE_PASSWORD = "$ATL_DATABASE_USER" ]]; then
			fail "Sorry, '$ATL_DATABASE_PASSWORD' is a terrible password. Please: { echo ATL_DATABASE_PASSWORD=$(pwgen -1s) >> $ATL_PROFILEDIR/${ATL_PROFILEFILES_SOURCED/ */}; } and try again"
		fi
		# So 'createuser' is a bit useless - there is no way to specify the password automatically! We could run 'createuser --pwprompt' as in attempt 2 below, but that prompts for a password even if the user already exists - when it should just say so. https://stackoverflow.com/questions/42419559/postgres-createuser-with-password-from-terminal says the solution is to create the user with SQL, so that's what we'll do
		unset PGDATABASE
		pgcmd='psql'
		set -- -c "create role \"${1:-$ATL_DATABASE_USER}\" with login password '$ATL_DATABASE_PASSWORD';"

		# Let's try omitting --pwprompt, as it causes 'atl_createuser' when the user already exists to not fail as you'd expecte
		#set -- "${@:-$ATL_DATABASE_USER}"
		#set -- "${@:-$ATL_DATABASE_USER}" "--pwprompt"
		;;
	atl_pg_user_drop | atl_pg_dropuser)
		pgcmd=dropuser
		superuser=true
		set -- "${@:-$ATL_DATABASE_USER}"
		;;
	atl_pg_create | atl_pg_createdb)
		pgcmd=createdb
		superuser=true
		local args=("--owner=$ATL_DATABASE_USER")
		case "$ATL_PRODUCT" in
		jira)
			args+=(-l C -T template0)
			;;
		esac
		# We have set PGDATABASE which will be what 'createdb' uses if no args are given. However if $@ is an alternative database name, that will be created instead
		set -- "$@" "${args[@]}"
		;;
	atl_pg_drop | atl_pg_dropdb)
		pgcmd=dropdb
		superuser=true
		atl_maintenance check
		if ! ((${#args[@]})); then # If only options (-*, --*) were passed, append our database. A non-option arg is assumed to be an auxiliary database name
			set -- "$@" "$ATL_DATABASE"
		fi

		;;

	atl_pg_dump | atl_pg_dumpall)
		# Tip: To pg_dump tables from a particular plugin: atl_pg_dump -t '"AO_B8B557"*'
		# There may be objects not owned by $ATL_DATABASE_USER, so always dump as superuser by default
		superuser=true
		# We might be redirecting to a dumpfile, so don't print extra rubbish
		# Actually, everything extra should go to stderr so shouldn't matter
		#quiet=true
		;;
	atl_psql)
		# ON_ERROR_STOP makes psql return a non-zero exit code on SQL errors. The equivalent for the non '--super' codepath is in ~/.psqlrc.
		local args=("-v" "ON_ERROR_STOP=on")
		set -- "$@"
		;;
	atl_pg_isready)
		set -- "$@"
		;;
	atl_pg_conftool)
		local args=("$ATL_DATABASE_VERSION" "$ATL_DATABASE_CLUSTER")
		set -- "$@"
		;;


	atl_pg_sql_owner_change | atl_pg_renameowner | atl_pg_sql_rename)
		local newuser="${1:-$ATL_DATABASE_USER}"
		if [[ $newuser =~ - ]]; then
			# Usernames containing hyphens must be quoted
			newuser="\"$newuser\""
		fi

		perl -pe "s/(^-- (Data for )?Name: .*; Owner: )[^;\n]+$/\1$newuser/g;
			s/(^ALTER (?:TABLE|FUNCTION|SCHEMA|AGGREGATE|SEQUENCE|LARGE OBJECT) .* OWNER TO ).*?(?=[;\n])/\1$newuser\2/g;
			s/(^(?:REVOKE|GRANT) ALL ON (?:TABLE|SCHEMA) .* (?:FROM|TO) \"?).*?(\"?;)/\1$newuser\2/g"
		# The first clause handles lines like:
		#    -- Name: agile; Type: SCHEMA; Schema: -; Owner: jira-foo
		# Notice that Postgres doesn't quote the username when it is just a comment.
		#
		# The second clause handles lines like:
		#    ALTER SCHEMA agile OWNER TO "jira-edgecast";
		# The name may also come to us unquoted, as in:
		#    ALTER FUNCTION public.nextid(tablename character varying) OWNER TO postgres;
		#
		exit 0
		;;
	atl_pg_sql_encoding_change_ascii2utf8)
		# If a database was created with C locale, fix it with 'pg_dump -E UTF-8 | atl_pg_sql_encoding_change_utf8'. The latter command rewrites lines like this, which -E doesn't seem to change:
		# CREATE DATABASE mbc_confluence WITH TEMPLATE = template0 ENCODING = 'SQL_ASCII' LOCALE_PROVIDER = libc LOCALE = 'C';
		#
		perl -pe "s/^(CREATE DATABASE \w+ .*ENCODING = ')SQL_ASCII('.* LOCALE = ')C(';)$/\1UTF8\2en_AU.UTF-8\3/g;
		s/^SET client_encoding = 'SQL_ASCII';$/SET client_encoding = 'UTF8';/g "
		exit 0
		;;

	atl_pg_user_passwordset)
		pgcmd='psql'
		superuser=true
		unset PGDATABASE
		set -- -c "alter user \"${1:-$ATL_DATABASE_USER}\" with login password '$ATL_DATABASE_PASSWORD';"

		# Let's try omitting --pwprompt, as it causes 'atl_createuser' when the user already exists to not fail as you'd expecte
		#set -- "${@:-$ATL_DATABASE_USER}"
		#set -- "${@:-$ATL_DATABASE_USER}" "--pwprompt"
		;;

	*)
		warn "No defaults set yet for $0"
		;;
	esac

	# Note: we don't quote the $*, as it may legitimately be blank
	#if [[ $# -gt 1 ]]; then
	#	error "Don't know what to do here. Should we quote '$*' or not? If we quote, atl_psql on its own with no args fails. If we don't quote, will multi-arg fail???"
	#fi
	if $verbose; then
		echo >&2 "Using database $ATL_DATABASE_TYPE://$ATL_DATABASE_HOST/$ATL_DATABASE"
	fi

	if $superuser; then
		export PGUSER="$ATL_DATABASE_SUPERUSER"
		export PGPASSWORD="$ATL_DATABASE_SUPERPASSWORD"
	else
		export PGUSER="$ATL_DATABASE_USER"
		export PGPASSWORD="$ATL_DATABASE_PASSWORD"
	fi

	if $verbose; then set -x; fi
	# For some reason we can't just export PSQLRC=<(....) like other vars.
	# We use the caller's ~/.psqlrc (if present) so that users can store history with HISTFILE
	# Note that psql does not honor $HOME when looking up default '~/.psqlrc', so would use /root/.psqlrc under a 'sudo -sE' environment. We avoid this problem by setting PSQLRC explicitly, and using a little sed script to replace ~ in our ~/.psqlrc with our real $HOME
	# FYI, when invoked by systemd on startup, $HOME will be for the runtime user, $ATL_USER, whose ~/.psqlrc is set via $ATL_MANAGE/templates/skel/.psqlrc
	PSQLRC=<(
		test -f ~/.psqlrc && sed -e "s#~#$HOME#g" <~/.psqlrc
		if [[ -v ATL_DATABASE_SCHEMA_SEARCH_PATH ]]; then
			# Used by /home/jturner/finances/financeloader/bin/fin_sql
			echo "set search_path=$ATL_DATABASE_SCHEMA_SEARCH_PATH;"
		fi
	) "$pgcmd" "$@"
	#grep -v search_path; echo "set search_path=finance;
	if $verbose; then set -x; fi
}

usage() {
	echo >&2 "Purpose: Runs $pgcmd on the $ATL_DATABASE database with RW access, as the $ATL_DATABASE_USER user."
	cat >&2 <<-EOF

		Usage:
		$(basename "$0") [ATLOPTIONS] <$pgcmd options and args>

		ATLOPTIONS:
		-h|--help       Show this message
		--atlverbose    Print information about the database we're connecting to
		--super[user]   Run superuser, rather than \$ATL_DATABASE_USER ($ATL_DATABASE_USER)

		Note that atl_dropdb can have the database overridden via the first arg.
	EOF
}

log() {
	echo >&2 "$@"
}

warn() {
	log >&2 "!! $*"
}

fail() {
	echo >&2 "$@"
	exit 1
}

main "$@"
# vim: set foldmethod=marker formatoptions+=cro :
