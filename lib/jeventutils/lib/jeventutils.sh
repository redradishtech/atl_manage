#!/bin/bash
# ^^ This is just to keep shellcheck happy. This is a library, not a script
# for t0, t1 etc
# shellcheck disable=SC2155   

JLOGDIR_GLOBAL=${JLOGDIR_GLOBAL:-/var/log}
JLOCKDIR_GLOBAL=${JLOCKDIR_GLOBAL:-/var/lock}

# Default JLOGDIR to ~/.cache for regular users, /var/log for system users (root, 'nobody' etc)
if [[ ! -v JLOGDIR ]]; then
	if [[ -v XDG_CACHE_HOME ]]; then
		JLOGDIR="$XDG_CACHE_HOME"
	elif (( EUID > 100 )) && [[ -v HOME ]]; then
		JLOGDIR="$HOME"/.cache
	else
		JLOGDIR=/var/log
	fi
fi
if [[ ! -v JLOCKDIR ]]; then
	JLOCKDIR=${XDG_RUNTIME_DIR:-/var/lock}
fi

[[ -v JLOGDIR ]] || { JLOGDIR="$JLOGDIR_GLOBAL"; }
[[ -v JLOCKDIR ]] || { JLOCKDIR="$JLOCKDIR_GLOBAL"; }

_JLIBDIR="$(realpath "$(dirname "${BASH_SOURCE}")")"
PATH="$_JLIBDIR/jo/:$PATH"   # The 'jo' executable is in our directory.

# Export vars so when we chain commands ('jlog foo jrun foo ..') the vars get default values set once and are inherited
export PATH JLOCKDIR_GLOBAL JLOGDIR_GLOBAL JLOCKDIR JLOGDIR

# Note, top-level functions invoke subshells (..) so that variables don't leak into the caller's shell (we are sourced, not called)
jrun()
(
	usage()
	{
		cat <<-'EOF'
		Usage: jrun [-h] RUNNAME COMMAND [ARGS...] 3>..
		Invokes COMMAND with ARGS, logging run start/finish time and exit code to JSON on fd 3.

		RUNNAME is a short logical tag (e.g. 'rsnapshot' for the invoked command, used in JSON metadata

		Example 1:

		$ jrun foo uname 3>&1
		Linux
		{"run:foo":{"state":"running","cmd":"'uname' ","pid":28379}}
		{"run:foo":{"state":"finished","cmd":"'uname' ","runtime":3,"exitcode":0}}

		Example 2:

		$ for i in {1..100}; do jrun foo bash -c 'sleep "$(($RANDOM % 11))"' & done 3> >(jeventlog | jevents -s)
		foo finished successfully 10s ago, taking 10s
		Stats:
		         run:foo ('bash -c sleep "$(($RANDOM % 11))"') succeeded for 100/100 of most recent runs, taking 5s on average (max 10s, min 0s)

		 -h	display this help and exit
		EOF
		exit
	}
		# FIXME: for reasons I don't understand, this doesn't work:
		# while read r; do break; done < <(jrun foo bash -c 'echo foo; sleep 0.1; echo bar')
		# The exit code from bash is 141 instead of 0. This only happens if we do a process substitution, and have a delay between lines.
		# Found this problem in check_tarsnap_backup_fresh

	unset OPTIND    # if jlog is nested (called from) another getopts-using function, reset the option parser
	while getopts ":h" opt; do 
		case ${opt} in
			h|*) usage;;
		esac
	done
	shift $((OPTIND -1))
	(( $# >= 2 )) || usage
	local runname="$1"; shift
	_validate_symbolicname "$runname"
	# Should we bother to record the pid of this process (the one that calls the jrun'd command)? 
	# Until there is a use-case, let's assume no, and let 'pid' be the pid of the jrun'd command
	declare -A logfields=()
	#declare -A logfields=([callerpid]=$$)
	local log="_echojson run:$runname"
	local t0=$(date +%s%N)
	# $@ will inherit our stdout/stderr, which has probably been redirected (via jlog) to a log file. It is $@'s responsibility to close stdout/stderr. E.g. I had a situation where $@ spawned 'sshd & disown'. sshd held onto stdout/stderr forever, causing the wrapping jlog to never complete, and the wrapping jlock to never release its lock.
	# $@ inherits stdin too, to allow for e.g. './stdout_emitting_script.sh | jwritelock processor jrun processor process.sh'
	"$@" &
	pid=$!
	# https://stackoverflow.com/questions/12985178/bash-quoted-array-expansion
	$log state=running pid=$! cmd="$(printf "'%s' " "${@}")"
	wait $pid
	local exitcode=$?
	local t1=$(date +%s%N)
	local runtime=$(((t1 - t0)/1000000))
	$log state=finished runtime=$runtime exitcode=$exitcode pid=
)

jreadlock() {
	local locktype=shared
	_jlock "$@"; }

jwritelock() {
	local locktype=exclusive
	_jlock "$@"; }

_jlock()
{
	usage()
	{
		local lockcmd=$(basename "${BASH_SOURCE[-1]}")
		cat <<-EOF
		Usage: $lockcmd [-h] [-g] [-u LOCKUSER] LOCKNAME COMMAND [ARGS..] 3>..
		Run a command after obtaining a lock, emitting JSON logs showing lock wait time.
		
		LOCKNAME identifies the lock (e.g. 'backup'); the actual path, calculated internally, will be \$JLOCKDIR/\$LOCKNAME.lock or (given -g) \$JLOCKDIR_GLOBAL/\$LOCKNAME.lock. Currently:
			JLOCKDIR=$JLOCKDIR
			JLOCKDIR_GLOBAL=$JLOCKDIR_GLOBAL
		
		Options:
		 -g	global lock (use \$JLOCKDIR_GLOBAL instead of \$JLOCKDIR)
		 -u	user to create lockfile as, if it doesn't exist. Useful in situations where your command may be run as either \$USER or root, and
		          a restrictive umask (e.g. 027) implies that if run as root, the lockfile would not later be readable by \$USER.
		 -h	display this help and exit
		
		Minimal example:
		
			export JLOGDIR=/tmp JLOCKDIR=/tmp		# Tell scripts their lock/log directories
			# jreadlock foo uname 3>&1
			{"lock:foo":{"state":"waiting","pid":745241,"lockfile":"/opt/atlassian/redradish_jira/current/temp/foo.lock","locktype":"shared"}}
			{"lock:foo":{"state":"acquired","pid":745241,"lockfile":"/opt/atlassian/redradish_jira/current/temp/foo.lock","waittime":2,"locktype":"shared"}}
			Linux
			{"lock:foo":{"state":"released","holdtime":60,"lockfile":"/opt/atlassian/redradish_jira/current/temp/foo.lock","waittime":2,"locktype":"shared"}}
		EOF
		_usage_example

		echo "Description:"
		echo
		echo -n "'$lockcmd LOCKNAME COMMAND' is the equivalent of 'flock "
		if [[ $lockcmd = jwritelock ]]; then
			echo -n "-x"
		else 
			echo -n "-s"
		fi
		cat <<-EOF
		 LOCKNAME -c COMMAND', except generating JSON logs on fd 3.
		
		Options:
		 -h	display this help and exit
		
		Variables:
			JLOCKDIR		Directory to create LOCKNAME.lock and LOCKNAME.lock.json in. Currently set to '$JLOCKDIR'
			JLOCKDIR_GLOBAL	Directory to create LOCKNAME.lock and LOCKNAME.lock.json in, given -g. Currently set to '$JLOCKDIR_GLOBAL'
		EOF
		exit
	}

	local lockuser=
	local global=false
	local nonblock=false
	local wait_secs=$((60*60))
	unset OPTIND    # if jlog is nested (called from) another getopts-using function, reset the option parser
	while getopts u:ghnE:w: opt; do 
		case ${opt} in
			g)
				global=true;;
			n)
				nonblock=true;;
			E)
				conflict_exit_code="$OPTARG";;
			w)
				wait_secs="$OPTARG";;
			u)
				lockuser=$OPTARG;;
			[?]) echo "Unknown option";;
			h|*) usage "$@";;
		esac
	done
	shift "$((OPTIND -1))"

	(( $# >= 2 )) || usage "$@"
	local lockname="$1"; shift
	_validate_symbolicname "$lockname"

	declare -A logfields=([pid]=$$)

	# locktype is assumed set by the caller (we're an internal function, and want to keep opts as user-provided)
	case "$locktype" in
		exclusive) local lockflags=(--exclusive); logfields[locktype]="exclusive";;
		shared) local lockflags=(--shared); logfields[locktype]="shared";;
		*) echo >&2 "Invalid locktype '$locktype' given to jeventutils.sh::lock"; exit 1; ;;
	esac
	if $nonblock; then
		lockflags+=("--nonblock")
	fi
	if [[ -v conflict_exit_code ]]; then
		lockflags+=(--conflict-exit-code="$conflict_exit_code")
	fi
	lockflags+=("--timeout" "$wait_secs")

	local lockdir
	if $global; then lockdir=${JLOCKDIR_GLOBAL}; else lockdir="$JLOCKDIR"; fi

	local lockfile="$lockdir/$lockname.lock"
	local lockinfo="$lockdir/$lockname.lock.json"
	local log
	log="_echojson lock:$(basename "${lockfile%.lock}")"

	id=$lockfile

	# Past runs, on acquiring a lock, will have recorded their metadata into $lockinfo.
	# It would be tempting, at this point, to emit an event saying "hey, we're waiting on pid X":
	#
	# if [[ -s "$lockinfo" ]]; then
	#	local lockingpid=$(<"$lockinfo" jq 'map(.pid)[0]')
	#	$log state=waiting lockfile="$lockfile" lockingpid="$lockingpid"
	# fi
	#
	# Sadly it doesn't work. If thread 1 has the lock, and 2 and 3 are waiting, both 2 and 3 will initially have lockingpid=1. But then 1 releases, 2 gains the lock, but 3 still says lockingpid=1
	# The locking pid read from $lockinfo is only valid at the instant it is read, not later, so is not appropriate for recording in JSON. 
	# Instead, at query time jevents reads $lockinfo, to let the user know which pid was being waited on.
	if [[ -e "$lockfile" ]]; then
		[[  -r "$lockfile" ]] || _jerror "User ${USER:-$UID} unable to write to $lockfile"
	else
		local lockdir="$(dirname "$lockfile")"
		if [[ -n $lockuser ]]; then
			sudo -u "$lockuser" mkdir -p "$lockdir"
			sudo -u "$lockuser" touch "$lockfile"
		else
			mkdir -p "$lockdir"
			touch "$lockfile"
		fi
	fi
	$log state=waiting lockfile="$lockfile"
	(
		local t0=$(date +%s%N)
		flock "${lockflags[@]}" ${lockfd} || return $?
		# echo "$$" >&${lockfd}     # FIXME: why do we not just use the lockfile to store our lockinfo?
		local t1=$(date +%s%N)
		#echo "$t1" >&${timefd}
		local waittime=$(((t1 - t0)/1000000))
		$log state=acquired waittime=$waittime


		# https://stackoverflow.com/questions/55716822/bash-flock-an-output-file
		exec 200>>"$lockinfo"
		flock -x 200
		#echo >&2 "Obtaining $locktype lock on $lockfile"
		if [[ $locktype = exclusive ]]; then
			# Record the locking pid in $lockinfo. Note that we can't use $lockfile for metadata because entering the (..) block overwrites it, leaving later blockees without metadata
			$log state=acquired waittime=$waittime 3>"$lockinfo"
		else
			# If the lock is shared, we could be one of N processes owning it, so append ('>>') our metadata
			$log state=acquired waittime=$waittime 3> >(jeventlog >> "$lockinfo")
		fi
		flock -u 200
		#echo >&2 "YAY, wrote to $lockfd which rediects to $lockfile"
		# FIXME: is there any use-case where we want to lock an eval'ed function?
		#echo >&2 "Here we are, is $1 a function? $(type -t "$1")"
		#if [[ $(type -t "$1") = function ]]; then
		#	echo >&2 "$1 is a function; evaluating"
		#	eval "$@"
		#else
		#	echo >&2 "$1 is a command; execing"
		# So we're going to run $@. Idiomatically $@ is a 'jrun' command, so that the runtime and exit code are captured. 'jrun' always returns a zero exitcode.
		# In fact, anything besides jrun is probably an error, so we log a warning there.
		# But there's nothing stopping a user jlock'ing something else besides jrun, in which case $? might be nonzero. If $? was nonzero and 'set -eu' was set
		# this function would exit before outputting the 'released lock' json line - not good. So we have an '|| ..' clause to prevent immediate exit, and capture
		# the exit code, and return it as 'lockee_exitcode' (the unusual name is to avoid conflicting with jrun's 'exitcode', which should be preferred)
		local lockee_exitcode=0
		[[ "$1" =~ ^(jrun|jreadlock|jwritelock|jlog)$ ]] || _jwarn "Warning: Running a raw command under lockfile: $1. Normally you would want the runtime and exit code by wrapping in 'jrun $lockname ...'"
		"$@" || lockee_exitcode=$?
		#fi
		local t2=$(date +%s%N)
		local holdtime=$(((t2 - t1)/1000000))   # Get from nanoseconds to milliseconds
		$log state=released holdtime=$holdtime pid= lockee_exitcode=$lockee_exitcode
		flock -x 200
		if [[ $locktype = exclusive ]]; then
			rm -f "$lockinfo"   # The -f is in case we're sourced from a user shell with alias rm='rm -i'
		else
			$log state=released holdtime=$holdtime pid= 3> >(jeventlog >> "$lockinfo")
			# FIXME: What happens if the caller only ever requests shared/read locks? We would keep appending to $lockinfo forever.
			# We can't just not record shared locks (only exclusive), because a writelock will block on a held readlock, and we
			# want to know why.
			# Perhaps 
		fi
		flock -u 200
	) {lockfd}>"$lockfile"
	# Dilemma: do we < or > the lockfile?
	# If we >, then if a script ever runs as root, its lockfile will be unwriteable by other users. This is the case for manually running $ATL_MANAGE/replication/sync_filesystem_auto and then letting it run via cron (as 'jira')
}

jlog()
(
	# Override ts format to get iso8601 format with subsecond precision (%.S)
	#/usr/bin/ts "ts=%Y-%m-%dT%H:%M:%.S%z logid=$$"
	# Edit: nanosecond precision is ugly and unnecessary for logs
	[[ -v JLOGUTILS_LOG_TIMESTAMP_FORMAT ]] || JLOGUTILS_LOG_TIMESTAMP_FORMAT="%Y-%m-%dT%H:%M:%S%z"

	usage()
	{
		cat <<-EOF
		Usage: jlog [options] LOGNAME COMMAND [ARGS...] 3>..
		Invokes COMMAND with ARGS and writes its stdout/stderr to a log file, \$JLOGDIR/LOGNAME.log, timestamping each line.

		Options:
		 -g	global log directory (use /var/log/ instead of \$JLOGDIR)
		 -h	display this help and exit

		Variables:
			JLOGDIR				directory to write LOGNAME.log file to	(current: '${JLOGDIR:-}')
			JLOGDIR_GLOBAL		directory to write LOGNAME.log file to, given -g	(current: '${JLOGDIR:-}')
			JLOGUTILS_LOG_TIMESTAMP_FORMAT	sets the log timestamp format	(current: '$JLOGUTILS_LOG_TIMESTAMP_FORMAT')
		EOF
		exit
	}
	local global=false
	unset OPTIND    # if jlog is nested (called from) another getopts-using function, reset the option parser
	while getopts gh opt; do 
		case ${opt} in
			g) global=true;;
			[?]) usage;;
			h|*) usage;;
		esac
	done
	shift $((OPTIND -1))
	(( $# > 1 )) || usage

	local logname logdir logfile logfile_tmp log logfields

	logname="$1"; shift
	_validate_symbolicname "$logname" || usage
	if $global; then logdir=${JLOGDIR_GLOBAL:-/var/log}; else logdir="$JLOGDIR"; fi
	logfile="$logdir/$logname.log"
	logfile_tmp="$(mktemp --dry-run --tmpdir="$logdir" "${logname}.log"-tmpXXXXXXX)"
	#shellcheck disable=SC2064
	trap "rm -f \"$logfile_tmp\"" EXIT   # Evaluate locally, since our vars are locally scoped
	declare -A logfields=([pid]=$$)
	log="_echojson log:$(basename "${logfile%.log}")"
	$log file="$logfile"
	#set -o  pipefail   # Necessary so we get $@'s exit code, not that of later commands in the pipe. 

	timestamp()
	{
		/usr/bin/ts "ts=${JLOGUTILS_LOG_TIMESTAMP_FORMAT} pid=$$"
	}
	if "$@" |& timestamp |& tee "$logfile_tmp" &>> "$logfile"
	then
		# Script succeeded.
		# Nuke any content from past runs, and also update the timestamp (even if $logfile_tmp is empty) to indicate we ran
		#true > "$logfile" || echo >&2 "Warning: $USER lacks permission to update $logfile"
		# Save logs, if any (this wouldn't update the timestamp if $logfile_tmp is empty)
		#cat "$logfile_tmp" > "$logfile"
		:
	else
		printf "FAILED: '%s' exit code %d. See %s for details" "$@" $? "$logfile"
		:
		#  Script failed and generated output, which has already been appended to $logfile.
		# FIXME: should we be passing through exit codes?
	fi
	# Note we don't blank the 'pid', as it acts as an identifier within $logfile for lines our process emitted. This is relied on by active_summary() jq function.
	$log newlines="$(wc -l <"$logfile_tmp")"
	rm -f "$logfile_tmp"
)

_printstacktrace()
{
	local LO='\u001B[2m'
	local RESET='\e[0m'
	set +x   # First turn off +x in case the caller left it on. The caller doesnt want to see the gory details of this function
	for (( i=0; i<${#BASH_SOURCE[@]}; i++ ))
	do
		# Skip the stacktrace lines from this 'printstacktrace' function, or the 'fail' function, or the 'errhandler' ERR trap 
		if [[ ${FUNCNAME[$i]} =~ ^(printstacktrace|fail|error|errhandler)$ ]]; then continue; fi
		echo -e >&2 "\t${LO}${BASH_SOURCE[$i]}:${BASH_LINENO[$((i-1))]} ${FUNCNAME[$i]}${RESET}";
	done
}

_jfail()
{
 	local fail="\u001b[31m"  # Red
 	local reset="\u001b[0m"   # reset
	[[ ${JLOGUTILS_COLOR:-} = false ]] && echo -e >&2 "$@" || echo -e >&2 "${fail}$@${reset}"
	echo
	_printstacktrace
	exit 1
}

_jwarn()
{
 	local fail="\u001b[31m"  # Red
 	local reset="\u001b[0m"   # reset
	[[ ${JLOGUTILS_COLOR:-} = false ]] && echo -e >&2 "$@" || echo -e >&2 "${fail}$@${reset}"
}
_jq()
{
	command -v jq >/dev/null || _jerror "jq command NOT in path ($PATH)"
	# Force UTC so that jq's 'fromdate' function interprets timestamps as UTC. This may be a jq bug - see discussion in jeventutils.jq parsetime function
	TZ=UTC jq "$@"
}

# Merge lines of JSON on stdin. Each line is an event log. Merging means fields like 'state' in the later logs overwrite 'state' in earlier logs, which is what we want.
jeventquery()
(
	usage()
	{
			echo "Usage: jeventquery [-h] [LOGNAME] EXPRESSION"
			echo "Given JSON event logs on stdin, aggregates them by runid and runs a given jq query on each."
			echo
			echo "LOGNAME identifies the set of records; the actual path ($JLOGDIR/$LOGNAME.log.json derived from \$JLOGDIR/\$LOGNAME.log.json) will be calculated by this script. If not given, stdin is assumed"
			echo
			echo "Examples:"
			echo "$ cat \$JLOGDIR/rsnapshot.log.json | jeventquery '.[0]'             # Prints most recent run object"
			{
			echo '{'
			echo '  "runid": "15422",'
			echo '  "starttime": "2020-06-12T02:46:47Z",'
			echo '  "lock:app": {'
			echo '    "state": "released",'
			echo '    "pid": 15420,'
			echo '    "lockfile": "/opt/atlassian/redradish_jira/current/temp/app.lock",'
			echo '    "locktype": "shared",'
			echo '    "waittime": 2,'
			echo '    "holdtime": 5046,'
			echo '    "type": "lock",'
			echo '    "id": "app"'
			echo '  },'
			echo '  "run:rsnapshot": {'
			echo '    "runpid": 15456,'
			echo '    "state": "finished",'
			echo '    "pid": 15420,'
			echo '    "cmd": "'ionice -c3 rsnapshot -c /opt/atlassian/redradish_jira/current/backups/rsnapshot.conf hourly'",'
			echo '    "runtime": 5006,'
			echo '    "exitcode": 0,'
			echo '    "type": "run",'
			echo '    "id": "rsnapshot"'
			echo '  }'
			echo '}'
			} | _jq .
			echo "$ cat \$JLOGDIR/rsnapshot.log.json | jeventquery '.[] | starttime'         # Prints run start times"
			echo '2020-06-12T02:46:47Z'
			echo '2020-06-11T23:22:43Z'
			echo
			echo "$ cat \$JLOGDIR/rsnapshot.log.json | jeventquery '(..|select(.type?==\"run\")) | [.pid, .state] | @csv'  # for each 'run' node, print the pid and state in CSV form, e.g."
			echo '15420,"finished"'
			echo '3499538,"running"'
			echo
			echo "$ jeventquery rsnapshot 'map(..|select(.type?==\"run\" and .state?==\"finished\") | .runtime) | {avg: (add / length), min: min, max: max, count: length}'	# Show average, min and max runtimes"
			echo 
			{
			echo "{"
			echo '  "avg": 11345.6,'
			echo '  "min": 5006,'
			echo '  "max": 50302,'
			echo '  "count": 10'
			echo '}'
			} | _jq .
			echo
			echo " -h	display this help and exit"
			exit
	}
	unset OPTIND    # if jlog is nested (called from) another getopts-using function, reset the option parser
	while getopts ":h" opt; do 
		case ${opt} in
			h|*) usage;;
		esac
	done
	shift $((OPTIND -1))
	(( $# == 1 || $# == 2 )) || usage
	if [[ $# = 1 ]]; then
		local logfile="/dev/stdin"
	else
		local logname="$1"; shift
		_validate_symbolicname "$logname" || usage
		local logfile="$JLOGDIR/$logname.log.json"
	fi

	# FIXME: figure out how to reverse order of the items in our hash, so that the command is printed first
	# FIXME: if would be nice if we could eliminate pid attributes when they are finally unset. Perhaps a strict additive overlay of JSON isn't really what we want..
	# https://stackoverflow.com/a/58621547/7538322
	# shellcheck disable=SC2016
	< "$logfile" _jq -sr 'include "jeventutils" {search: "'"$_JLIBDIR"'"};
	group_by(.runid)
	| map(singlerun_merge)
	| map(singlerun_addtypes)
	| sort_by(.starttime)
	| reverse
	| '"$*"
)


_usage_example()
{
	echo
	echo "Realistic Example:"
	echo 
	echo "	export JLOGDIR=/tmp JLOCKDIR=/tmp		# Tell scripts their lock/log directories"
	echo
	echo "	jwritelock backup \\		# Get an exclusive (write) lock on \$JLOCKDIR/backup.lock, so only one backup runs at once"
	echo "		jlog backup \\			# Stdout/stderr from nested commands goes to \$JLOGDIR/backup.log"
	echo "		jrun backup \\			# Run the nested command, emitting JSON events for its start/stop"
	echo "		  rsnapshot hourly \\		# The actual backup command (can be anything you like)"
	echo "		    3> >(jeventlog backup) 	# Get JSON from all the above (jwritelock to jrun) and write to \$JLOGDIR/backup.log.json"
	echo
	echo "	Then to see results:"
	echo 
	echo "	jevents -s backup	# Reads \$JLOGDIR/backup.log.json, printing active runs or last run state, and optionally some stats"
	echo
}

jeventlog()
(
	usage()
	{
		echo "Usage: jeventlog [-ht] [LOGNAME]"
		echo "Write JSON lines from stdin to a log file, adding a common runid and timestamp."
		echo 
		echo "LOGNAME is an identifier for this set of logs (e.g. 'backup'); the actual path (${JLOGDIR:-JLOGDIR}/${JLOGNAME:-JLOGNAME}.log.json derived from \$JLOGDIR/\$LOGNAME.log.json) will be calculated internally. If omitted, stdout is used (e.g. to pipe to jevents)"
		echo
		echo "Options:"
		echo " -t	if LOGNAME is given, also send output to stdout (acts like 'tee'). E.g. '>(jeventlog -t foo | jevents)' records a log file and prints a summary "
		echo " -h	display this help and exit"
		echo " -g	global log directory (use /var/log/ instead of \$JLOGDIR)"
		echo
		echo "Minimal example:"
		echo
		echo "	export JLOGDIR=/tmp JLOCKDIR=/tmp		# Tell scripts their lock/log directories"
		echo "	$ { jq -cn '{foo:1}'; jq -cn '{bar:2}'; }  | jeventlog foo"
		echo "	$ cat \$JLOGDIR/foo.log.json"
		echo '	{"runid":"634365","starttime":"2020-05-30T10:38:47Z","foo":1}'
		echo '	{"runid":"634365","starttime":"2020-05-30T10:38:47Z","bar":2}'

		_usage_example

		echo "Description:" 
		echo 
		echo "jeventlog ties logs from these disparate commands together by augmenting each line with a 'runid' attribute (actually"
		echo "the jeventlog process pid). This lets all logs related to one command by identified."
		echo "Additionally a 'starttime' value is appended to each, being the time when this series of related operations started."
		echo "The idea is that individual log emitters (e.g. jreadlock) only record time intervals (in ms) rather than absolute"
		echo "timestamps. These intervals will be resolved relative to starttime (although for this to work writelock must be put"
		echo " outermost in the function nesting)."
		exit

	}

	function _tstamp()
	{
		local starttime="$1"
		local pid="$2"
		# Argggh.. this jq command should augment JSON with the provided starttime and pid. It works.. for all lines except the last (stdin) where it silently fails to write (to stdout or a file). 'stdbuf -oL' doesn't help.
		# I have replaced jq with a hacky echo + sed that does the equivalent job.
		#_jq --arg starttime "$starttime" --arg pid "$pid" -c '{runid:$pid, starttime: $starttime} + .'
		echo -n '{"runid":"'$pid'", "starttime": "'$starttime'", '
		sed -e 's/^{//'
	}

	local tostdout=false
	local global=false
	unset OPTIND    # if jlog is nested (called from) another getopts-using function, reset the option parser
	while getopts ":shtg" opt; do 
		case ${opt} in
			g) global=true;;
			t) tostdout=true;;
			h|*) usage;;
		esac
	done
	shift $((OPTIND -1))
	(( $# <= 1 )) || usage

	if [[ $# = 0 ]]; then
		local logfile="/dev/stdout"
	else
		local logname="$1"; shift
		_validate_symbolicname "$logname"
		if $global; then logdir=${JLOGDIR_GLOBAL:-/var/log}; else logdir="$JLOGDIR"; fi
		local logfile="$logdir/$logname.log.json"
	fi

	#local starttime="$(_jq -nr 'now | gmtime | todate')"   # second precision is too coarse-grained
	# Log an iso8601 date with millisecond precision in GMT. https://stackoverflow.com/questions/16548528/command-to-get-time-in-milliseconds
	# Lack of timezone is to accommodate jq's limitations (https://github.com/stedolan/jq/issues/1117). Nanosecond precision would be pointless given our overhead
	local starttime="$(TZ=0 date +"%Y-%m-%dT%T.%3NZ")"

	# https://stackoverflow.com/questions/55716822/bash-flock-an-output-file
	# A writelock on the logfile is held whenever actual writing is occurring. Readers (jevents) should get a readlock to ensure consistent reads.
	# This 'exec' and flock used to be inside the 'while'. I hope that was not necessary
	exec 200>>"$logfile"
	while read -r line; do 
		flock -x 200
		if [[ -v JDEBUG && $JDEBUG = true ]]; then echo >&2 "Writing to $logfile"; fi
		echo "$line" | _tstamp "$starttime" "$$" | if $tostdout; then
			tee -a "$logfile"
		else
			echo "$(</dev/stdin)" >> "$logfile"
		fi
	done
	flock -u 200
)

jevents()
(
	usage()
	{
		echo "Usage: jevents [OPTION]... [LOGNAME] 3>.."
		echo "Print a text summary of a .log.json file of JSON run records"
		echo
		echo "LOGNAME identifies the set of records; the actual path ($JLOGDIR/$LOGNAME.log.json derived from \$JLOGDIR/\$LOGNAME.log.json) will be calculated by this script. If not given, stdin is assumed"
		echo " -s	print statistics on last runs"
		echo " -n NUM	consider only last NUM runs. Alternatively, set JLOGUTILS_RELATIVE_RUNS_TO_SHOW=NUM"
		echo " -h	display this help and exit"
		exit
	}

	# Returns actual status ('active', 'dead') of allegedly running pids in $logfile, in JSON format ($pidstatusjson) and as an array ($pidstatus).
	function _setpidstatus()
	{
		declare -g -A pidstatus
		declare -g pidstatusjson
		while read -r pid; do
			# https://stackoverflow.com/questions/3043978/how-to-check-if-a-process-id-pid-exists
			kill -0 "$pid" 2>/dev/null && pidstatus[$pid]='active' || pidstatus[$pid]='dead'
		done < <(
		cat "$logfile" | _jq -sr '
		include "jeventutils" {search: "'"$_JLIBDIR"'"};
		active_pids')
		pidstatusjson=$({ 
			for k in "${!pidstatus[@]}"; do
				printf "%s=%s\n" "$k" "${pidstatus[$k]}"
			done | jo -d.
		})
	}

	function _unsetpidstatus()
	{
		unset pidstatus pidstatusjson
	}


	# Given a log file $logfile, finds 
	# Returns actual status ('active', 'dead') of allegedly running pids in $logfile, in JSON format ($lockstatusjson). Assumes $pidstatus has been set
	function _setlockstatus()
	{
		declare -A lockingpid
		declare -A lockingpidstatus
		declare -g lockstatusjson
		local lock lockfile waitingpid
		while read -r lock lockfile waitingpid; do
			#echo >&2 "lock: $lock lockfile: $lockfile waitingpid: $waitingpid ps: $ps"
			#local waitingpidstatus="${pidstatus[$waitingpid]}"  # 'active' or 'dead'
			#echo >&2 "PiD $waitingpid (status $waitingpidstatus) is waiting on lock $lock, in file $lockfile"
			local infofile="${lockfile}.json"
			if [[ -f "$infofile" ]]; then
				#cat "$infofile"
				while read -r lock lockfile pid; do
					lockingpid[$lock]=$pid
					if [[ -v lockingpidstatus[$pid] ]]; then
						: #echo >&2 "We already know $pid is ${lockingpidstatus[$pid]}"
					else
						kill -0 "$pid" 2>/dev/null && lockingpidstatus[$pid]='active' || lockingpidstatus[$pid]='dead'
						#echo >&2 "$lock: locked by $pid which is ${lockingpidstatus[$pid]} "
					fi
				done < <(
					cat "$infofile" | _jq -sr '
					include "jeventutils" {search: "'"$_JLIBDIR"'"};
					active_locks'
					)
			fi
		done < <(
			cat "$logfile" | _jq -sr '
			include "jeventutils" {search: "'"$_JLIBDIR"'"};
			active_locks'
			)

		lockstatusjson=$({ 
			for k in "${!lockingpid[@]}"; do
				local pid=${lockingpid[$k]}
				printf "%s.lockingpid=%s\n" "$k" "$pid"
				printf "%s.lockingpidstatus=%s\n" "$k" "${lockingpidstatus[$pid]}"
			done | jo -d.
		})
	}

	function _unsetlockstatus()
	{
		unset logkstatusjson
	}


	local stats=false
	unset OPTIND    # if jlog is nested (called from) another getopts-using function, reset the option parser
	while getopts ":shn:" opt; do 
		case ${opt} in
			n) export JLOGUTILS_RELATIVE_RUNS_TO_SHOW=$OPTARG;;
			s) stats=true;;
			h|*) usage;;
		esac
	done
	shift $((OPTIND -1))
	(( $# <= 1 )) || usage
	if [[ $# = 0 ]]; then
		local logfile=$(mktemp --tmpdir=/dev/shm)
		#shellcheck disable=SC2064
		trap "rm -f \"$logfile\"" EXIT    # Note: evaluate $logfile here, not later, since $logfile is locally scoped
		cat /dev/stdin > "$logfile"
		# Store stdin in a file, because we need to read it more than once

	else
		local logname="$1"; shift
		_validate_symbolicname "$logname" || usage
		# Fall back to $JLOGDIR_GLOBAL if the log file can't be found in $JLOGDIR. N:q

		local logfile
		if [[ -v JLOGDIR && -r "$JLOGDIR/$logname.log.json" ]]; then
			logfile="$JLOGDIR/$logname.log.json"
		elif [[ -r "$JLOGDIR_GLOBAL/$logname.log.json" ]]; then
			logfile="$JLOGDIR_GLOBAL/$logname.log.json"
		else
			echo >&2 "$JLOGDIR/$logname.log.json (and $JLOGDIR_GLOBAL/$logname.log.json) do not exist"
			return 1
		fi
	fi
	#shellcheck disable=SC2094
	local cmd="active_summary"
	if $stats; then cmd+=', "Stats:", (finishedruns | finishedruns_summary)'; fi
	#flock -s "$logfile"
	local t0=$(date +%s%N)
	_setpidstatus </dev/null    # Set $pidstatus and $pidstatusjson. Null stdin so _pidstatus doesn't consume it
	local t1=$(date +%s%N)
	_setlockstatus </dev/null    # Set $lockstatusjson. Null stdin so _lockstatus doesn't consume it
	local t2=$(date +%s%N)
	local runtime=$(((t1 - t0)/1000000))
	#echo "Runtime: $runtime"
	#echo "Lockstatus: $lockstatusjson"

	_jq -sr --argjson pidstatus "$pidstatusjson" --argjson lockstatus "$lockstatusjson" ' include "jeventutils" {search: "'"$_JLIBDIR"'"}; '"$cmd" < "$logfile"
	_unsetpidstatus
	_unsetlockstatus
)

jeventsummaryscript()
{
	usage()
	{
		echo "Usage: jeventsummaryscript [-h] EXECSCRIPT [ARGS]"
		echo "Given event JSON on stdin expected to contain 'jrun' events, invokes EXECSCRIPT, with EXITCODE and SUMMARY environment variables set. The ARGS also have any occurrence of @SUMMARY@ and @EXITCODE@ replaced with values derived from the events JSON."
		echo
		echo " -h	display this help and exit"

		echo "Sample use:"
	}

	unset OPTIND    # if jlog is nested (called from) another getopts-using function, reset the option parser
	local tostdout=false
	while getopts ":ht" opt; do 
		case ${opt} in
			t) tostdout=true;;
			h|*) usage; return;;
		esac
	done
	shift $((OPTIND -1))
	(( $# > 0 )) || { usage; return; }

	local json exitcode nagiosexitcode summary
	json="$(cat -)"
	exitcode=$(jeventquery '.[] | [(..|select(.type?=="run"))] | map(.exitcode) | add' <<< "$json")
	# We get back 'null' if there were no 'run' entries in the JSON stream. This happens when e.g. we gave up waiting on a lock.
	if [[ $exitcode == null ]]; then exitcode=1; fi
	summary="$(echo "$json" | JLOGUTILS_COLOR=false JLOGUTILS_HOURS_TO_RELATIVIZE_DATES_FOR=0 jevents --)"
	if (( exitcode <= 3 )); then nagiosexitcode=$exitcode; else nagiosexitcode=3; fi   # Let invoked scripts distinguish warnings (1) from critical errors (2)

	local oldarg newarg
	cmd=("$1"); shift
	for oldarg in "$@"; do
		newarg="$(echo "$oldarg" | summary="$summary" nagiosexitcode="$nagiosexitcode" perl -pe 's/\@SUMMARY\@/$ENV{summary}/eg; s/\@EXITCODE\@/$ENV{nagiosexitcode}/eg;')" 
		cmd+=("$newarg")
	done

	export EXITCODE="$exitcode"
	export SUMMARY="$summary"
	local output
	if [[ -v JDEBUG && $JDEBUG = true ]]; then echo >&2 "Running: ${cmd[*]}"; fi
	if output="$("${cmd[@]}" 2>&1)"; then
		if [[ -v JDEBUG && $JDEBUG = true ]]; then echo >&2 "Command ran successfully"; fi
		echo "$output"
	else
		echo >&2 "jeventsummaryscript failed"
		echo -e >&2 "\n\n\tFailed command: ${cmd[*]@Q}"
		echo -e >&2 "\n\n\tOutput: $output\n\n"
	fi
	if $tostdout; then
		echo "$json"
	fi
}


# Emits a line of JSON to fd 3 with all our current logging fields ($logfields), after updating them with k=v pairs given as function args. The first arg is an 'id' identifying a common event stream
# Usage: _echojson <id> k=v [...]
_echojson()
{
	#shellcheck disable=SC2188
	if { >&3; } 2<> /dev/null; then
		# fd3 has been redirected; all good
		:
	else
		 if [ -t 0 ] ; then
			 # fd3 not redirected, and we're interactive; print a warning and redirect 3 to stderr so the user sees JSON intermixed with actual output.
			 # Note: redirecting fd3 to either fd1 or fd2 is dangerous, as the script we're wrapping could well do its fd manipulation, e.g. 'out=$(mktemp); foo > "$out"' patten in check_tarsnap_backup_fresh. Redirecting stderr is less likely to cause problems than stdout, hence we pick &2 here.
			exec 3>&2
			_jwarn "Please redirect JSON logs.\nEither to a log file:  ${BASH_SOURCE[-1]} 3> >(jeventlog foo)\nOr just to stdout for debugging:  ${BASH_SOURCE[-1]} 3>&1"
		else
			# This happens in two situation:
			# 1) if jrun calls itself ('jrun foo jrun bar true'). In that situation fd3 is borked for reasons I don't understand and needs closing and redirecting
			# 2) if a noninteractive script fails to redirect fd3, e.g. by ending with '3> >(jeventlog foo)'"
			exec 3<&-
			exec 3>&2
		fi
	fi

	local id="$1"; shift
	#TZ=UTC printf -v logfields[time] '%(%Y-%m-%dT%H:%M:%S)TZ' -1
	for kv in "$@"; do
		local k="${kv%=*}"
		local v="${kv#*=}"
		if [[ -n $v ]]; then
			logfields["$k"]="$v"
		else
			unset logfields["$k"]
		fi
	done
	{ 
		local sep=#   # A character unlikely to be naturally in $id (so not '.').
		for k in "${!logfields[@]}"; do
			printf "$id${sep}%s=%s\n" "$k" "${logfields[$k]}"
		done | jo -d${sep}
	} >&3
}

_validate_symbolicname()
{
	if [[ $1 =~ ^[\.a-zA-Z0-9_-]+$ ]]; then
		return
	else
		echo >&2 "'$1' should be just a logical identifier (a-z, A-Z, 0-9, .,-,_) without path or extension"
		exit
		return 1
	fi
}

## Design choice notes:

# These functions assume logs in $JLOGDIR and locks in $JLOCKDIR. Wouldn't it be better to use absolute file paths?  E.g. instead of:
# 
# export JLOGDIR=/tmp JLOCKDIR=/tmp
# jwritelock backup \\
# 	jlog backup \\
# 	jrun backup \\
# 	  rsnapshot hourly \\
# 	    3> >(jeventlog backup)
# 
# We'd have:
# 
# jwritelock $lockdir/backup.lock \\
# 	jlog $logdir/backup.log \\
#       jrun backup \\
#       rsnapshot hourly \\
# 	3> >(jeventlog > $logdir/backup.log.json)
#
# Explicit is good. This would also allow funky things like 'jlog >(postprocessor)'
# I went the symbolic route for two reasons:
# 1) Most of the time the actual log/lock file location is an uninteresting detail, something that it is *good* to hide within a library
# 2) We need symbolic names for the JSON stream anyway. Should we have both ('jlog backup $logdir/backup.log')? Too noisy. Should we infer 'backup' from 'backup.lock' and 'backup.log'? We want to avoid inference, and anyway that assumes a *.log/*.lock pattern - ugly. Plus jrun needs a symbolic name as an arg. Now we're mixing symbolic names with paths. Also ugly.
# Perhaps if a use-case arises, we could support an optional second absolute path, to allow 'jlog backup >(postprocessor)'.
# For now, note that 'jeventlog' with no symbol emits to stdout, and 'jevents' with no symbol reads from stdin, so we can do:
# $ jrun passivecheck jlog du du 3> >(jeventlog | jevents)
# [15/Jun 10:31] (0s ago)  passivecheck finished successfully 0s ago, taking 0s. 558 logs generated (grep 2877149 /opt/atlassian/redradish_jira/current/logs/du.log)

# vim: set ft=sh:e
