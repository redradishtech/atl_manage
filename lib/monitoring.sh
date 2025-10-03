#shellcheck shell=bash

infer_atl_monitoring_from_installed_packages() {
	if command -v icinga >/dev/null; then
		ATL_MONITORING=icinga
	elif command -v nagios3 >/dev/null; then
		ATL_MONITORING=nagios3
	elif command -v nagios4 >/dev/null; then
		ATL_MONITORING=nagios4
	else
		ATL_MONITORING=nagios4
		warn "Neither Nagios nor Icinga are installed. Defaulting to $ATL_MONITORING"
	fi
}

# Return true if $ATL_MONITORING's package is installed
isinstalled() {
	case "$ATL_MONITORING" in
	icinga2) dpkg -s "icinga2" &>/dev/null ;;
	icinga) dpkg -s "icinga-core" &>/dev/null ;;
	nagios3) dpkg -s nagios3 &>/dev/null ;;
	nagios4) dpkg -s nagios4 &>/dev/null ;;
	esac
	return $?
}

set_monitoring_vars() {
	monitoring_exe="$ATL_MONITORING"               # The binary is 'nagios4', 'icinga' etc.
	monitoring_apachesnippetname="$ATL_MONITORING" # The snippet under /etc/apache2/conf-available, passed to a2enconf
	monitoring_logdir=/var/log/"$ATL_MONITORING"   # Correct at least for nagios4 and icinga

	monitoring_etc="/etc/$ATL_MONITORING"
	case "$ATL_MONITORING" in
	icinga2)
		monitoring_confdir=$monitoring_etc/conf.d
		monitoring_staticconfs=("$monitoring_confdir"/*.cfg)
		monitoring_mainconf=$monitoring_etc/icinga.cfg
		monitoring_apachesnippetname="icingaweb2"
		# This only becomes available after we have '$monitoring_etc/features-enabled; ln -s ../features-available/notification.conf .'
		monitoring_commanddir="/run/icinga2/cmd"
		monitoring_commandfile="$monitoring_commanddir"/icinga2.cmd
		monitoring_logodir=/usr/share/nagios/htdocs/images/logos # Provided by nagios-images package
		monitoring_statusfile=/var/cache/icinga2/status.dat
		;;
	icinga)
		monitoring_confdir="$monitoring_etc/objects"
		monitoring_staticconfs=("$monitoring_confdir"/{hostgroups_*.cfg,localhost_*.cfg})
		monitoring_mainconf="$monitoring_etc/icinga.cfg"
		monitoring_cgiconf="$monitoring_etc/cgi.cfg"
		monitoring_commanddir="/var/lib/icinga/rw"
		monitoring_commandfile="$monitoring_commanddir"/icinga.cmd
		monitoring_logodir=/usr/share/nagios/htdocs/images/logos # Provided by nagios-images package
		monitoring_statusfile=/var/cache/icinga/retention.dat
		;;
	nagios3)
		monitoring_confdir=$monitoring_etc/conf.d
		monitoring_staticconfs=("$monitoring_confdir"/{hostgroups_*.cfg,localhost_*.cfg})
		monitoring_mainconf="$monitoring_etc/nagios.cfg"
		monitoring_cgiconf="$monitoring_etc/cgi.cfg"
		monitoring_commanddir="/var/lib/nagios3/rw"
		monitoring_commandfile="$monitoring_commanddir"/nagios.cmd
		monitoring_logodir=/usr/share/nagios/htdocs/images/logos # Provided by nagios-images package
		monitoring_statusfile=/var/cache/nagios3/status.dat
		;;
	nagios4)
		monitoring_confdir=$monitoring_etc/conf.d
		monitoring_staticconfs=($monitoring_etc/objects/{templates.cfg,localhost.cfg})
		monitoring_mainconf="$monitoring_etc/nagios.cfg"
		monitoring_cgiconf="$monitoring_etc/cgi.cfg"
		monitoring_apachesnippetname="nagios4-cgi"
		monitoring_commanddir="/var/lib/nagios4/rw"
		monitoring_commandfile="$monitoring_commanddir"/nagios.cmd
		monitoring_logodir=/usr/share/nagios4/htdocs/images/logos
		monitoring_statusfile=/var/lib/nagios4/status.dat
		;;
	none)
		:
		;;
	*)
		echo >&2 "Cannot get configuration file directory for unknown monitoring system: '$ATL_MONITORING'"
		;;
	esac
	export monitoring_exe
	export monitoring_staticconfs
	export monitoring_mainconf
	export monitoring_cgiconf
	export monitoring_apachesnippetname
	export moniotoring_commanddir
	export monitoring_commandfile
	export monitoring_logodir
	export monitoring_statusfile
	export monitoring_logdir
}

_fail() {
	echo >&2 "$@"
	exit 1
}

get_monitoring_commandfile() {
	[[ -e "$monitoring_commandfile" ]] || error "Monitoring command fifo '$monitoring_commandfile' does not exist or is not readable"
	[[ -w "$monitoring_commandfile" ]] || error "Monitoring command fifo '$monitoring_commandfile' exists but is not writeable by user ${USER:-$UID}"
	echo "$monitoring_commandfile"
}

disable_notifications() {
	# get the current date/time in seconds since UNIX epoch
	local datetime
	datetime="$(date +%s)"
	# pipe the command to the command file
	printf "[%i] DISABLE_NOTIFICATIONS;%i\n" "$datetime" "$datetime" >>"$(get_monitoring_commandfile)"
}
enable_notifications() {
	monitoring_active || fail "Monitoring is not active" # If the process isn't running, nothing will read from the command fileand we'll hang
	# get the current date/time in seconds since UNIX epoch
	local datetime
	datetime="$(date +%s)"
	# pipe the command to the command file
	printf "[%i] ENABLE_NOTIFICATIONS;%i\n" "$datetime" "$datetime" >>"$(get_monitoring_commandfile)"
}

submit_check_result() {
	# get the current date/time in seconds since UNIX epoch
	local datetime
	datetime=$(date +%s)

	# create the command line to add to the command file
	cmdline="[$datetime] PROCESS_SERVICE_CHECK_RESULT;$1;$2;$3;$4"

	# append the command to the end of the command file
	echo "$cmdline" >>"$(get_monitoring_commandfile)"
}

monitoring_active() {
	for prop in $(systemctl show "$ATL_MONITORING.service" --property=LoadState --property=ActiveState --property=SubState); do
		case "$prop" in
		LoadState=loaded) ;;
		ActiveState=active) ;;
		ActiveState=failed) return 1 ;;
		LoadState=* | ActiveState=*) return 1 ;;
		SubState=exited) return 1 ;;
		MainPID=*)
			#shellcheck disable=SC2001
			pid=$(echo "$prop" | sed -e 's/^MainPID=//')
			# kill -0 returns true if the process exists (without harming it)
			if kill -0 "$pid" >&1 >/dev/null; then
				:
			else
				return 1
			fi
			;;

		esac
	done
	return 0
}
