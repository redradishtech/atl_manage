#!/bin/bash -eu

# shellcheck source=/opt/atl_manage/lib/common.sh
source "$ATL_MANAGE/lib/common.sh" --

set -o pipefail

main() {
	[[ -v ATL_SYSTEMD_SERVICENAME ]] || fail "$ATL_SHORTNAME does not have a systemd service (ATL_SYSTEMD_SERVICENAME undefined)"
	# If we've just atl_install'ed and want to atl_backupmirror_restore, the service won't exist.
	systemctl -q is-enabled "$ATL_SYSTEMD_SERVICENAME" || {
		warn "Systemd service $ATL_SYSTEMD_SERVICENAME is not enabled"
		exit 0
	}

	systemdcmd="$(basename "$0")"   # atl_stop, atl_start, atl_restart
	systemdcmd="${systemdcmd#atl_}" # Strip atl_ prefix to get the (hopefully) systemd command

	case "$systemdcmd" in
	stop)
		if confirm_stop_if_service_is_shared; then
			#atl_event stop-pre  # Rely on systemd triggering stop-pre
			$SUDO systemctl stop "$ATL_SYSTEMD_SERVICENAME"
		fi
		;;
	start)
		#atl_event stop-pre  # Rely on systemd triggering start-pre
		#atl_event start-pre
		$SUDO systemctl start "$ATL_SYSTEMD_SERVICENAME"
		;;
	restart)
		#atl_event stop-pre
		#atl_event start-pre
		atl_event reload-pre    # EJ overrides this to regenerate tenant PHP config snippets
		$SUDO systemctl restart "$ATL_SYSTEMD_SERVICENAME"
		;;
	reload)
		atl_event reload-pre    # EJ overrides this to regenerate tenant PHP config snippets
		$SUDO systemctl reload "$ATL_SYSTEMD_SERVICENAME"
		;;
	*)
		$SUDO systemctl "$systemdcmd" "$ATL_SYSTEMD_SERVICENAME"
		;;
	esac
}

confirm_stop_if_service_is_shared() {
	if [[ -v ATL_SERVICE_INSTALLED_EXTERNALLY && $ATL_ROLE != prod && $ATL_SERVER_ROLE = prod ]]; then
		if atl_running; then
			read -rp "That the $ATL_SYSTEMD_SERVICENAME systemd service is not used only by $ATL_SHORTNAME, and stopping it may affect other apps on this $ATL_SERVER_ROLE server. You can (s)top the service, (c)ontinue without stopping, or (A)bort.  (scA) " yesno
			case $yesno in
			s*) return 0 ;;
			c*) return 1 ;;
			*) exit 1 ;;
			esac
		fi
	fi
}

main "$@"
# TODO: rotate catalina.out and logs in stop-post?
