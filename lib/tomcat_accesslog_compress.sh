#!/bin/bash -eu

# Compresses old Tomcat logs (notably access logs), and removes ones older than X months if they consume more than Y Gb in total.

# Don't compress files that are younger than this-many days. This allows evergreen files like replication.log to never be deleted.
let DONT_COMPRESS_YOUNGER_THAN_DAYS=7
# Only delete old compressed logs if their total size (compressed) exceeds MAXSIZE_GB gigabytes.
let MAXSIZE_GB=5
# Refuse and complain if asked to delete logs younger than MTIME_MONTHS months. This allows one to conform to log retention policies.
let MTIME_MONTHS=6

shopt -s extglob
shopt -u nullglob

main() {
	set -eu # Rely on quick failure from getopt if wrong arg is passed
	#https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash/38153758
	PARSED=$(getopt --options 'hv' --longoptions 'help,verbose' --name "$0" -- "$@")
	eval set -- "$PARSED"
	verbose=false
	while true; do
		case "$1" in
		-v | --verbose) verbose=true ;;
		--)
			shift
			break
			;;
		-h | --help | *) usage ;;
		esac
		shift
	done
	[[ $# = 1 ]] || usage
	CATALINA_BASE="$1"
	[[ -d $CATALINA_BASE/logs ]] || error "Directory '$CATALINA_BASE' does not appear to be Tomcat's (no logs/)"

	remove_past_backup_install_logs
	archive
}

usage() {
	echo >&2 "Purpose: compresses Tomcat log files, and deletes logs older than $MTIME_MONTHS months"
	echo >&2 "Usage  : $0 /path/to/tomcat/base [--verbose]"
	echo >&2 "E.g.   : $0 /opt/atlassian/jira/current [--verbose]"
	echo >&2 "E.g.   : $0 /opt/atlassian/crowd/current/apache-tomcat [--verbose]"
	exit 2
}

remove_past_backup_install_logs() {
	cd "$CATALINA_BASE"/..
	export GLOBIGNORE=current
	rm -f ./*-backup-*/logs/!(highload_events|events)
}

archive() {
	cd "${CATALINA_BASE}/logs"

	# today's date (not to be gzipped)
	DATE="$(date --rfc-3339=date)"

	# https://stackoverflow.com/questions/11366184/looping-through-find-output-in-bash-where-file-name-contains-white-spaces
	find . -maxdepth 1 -type f -not -name "*.gz" -mtime +${DONT_COMPRESS_YOUNGER_THAN_DAYS} -not -name "*$DATE*" -print0 | while read -d '' -r file; do
		# Check that the file is not being used. We can't rely on the filename to have a timestamp ('catalina.out') nor even the last modified date to tell if Tomcat is still using the file.
		debug "Considering: $file"
		lsof -n -w "$file" &>/dev/null || {
			debug "Compressing old log: ${file}"
			echo -ne "${file}\0"
		}
	done | xargs -0 --no-run-if-empty pigz -f # The -f is in case $file.gz exists, which shouldn't normally happen, but we don't want an interactive prompt

	if logstoobig; then
		debug "Our gzipped logs consume more than $MAXSIZE_GB Gb. Deleting any older than $MTIME_MONTHS months: $(find . -name "*.gz" -mtime +$((MTIME_MONTHS * 30)))"
		find . -name "*.gz" -mtime +$((MTIME_MONTHS * 30)) -exec rm {} \;
		if logstoobig; then
			echo "Warning: log directory $PWD is still over $MAXSIZE_GB Gb, despite deleting old logs. Remaining $(ls -1 ./*.gz | wc -l) gzipped log files are younger than $MTIME_MONTHS months, and so will not be removed"
		fi
	else
		debug "Our gzipped logs consume $((logsize / 1024 / 1024)) Mb, less than our maximum of $MAXSIZE_GB Gb. Not deleting"
	fi
}

logstoobig() {
	logsize=$(find . -name "*.gz" -printf "%s\n" | awk '{t+=$1}END{print t}')
	[[ -z $logsize ]] && logsize=0 # If there are no files, logsize will be blank
	((logsize > MAXSIZE_GB * 1024 * 1024 * 1024))
}

debug() {
	if $verbose; then echo >&2 "$*"; fi
}

fail() {
	echo >&2 "$*"
	exit 1
}

main "$@"
