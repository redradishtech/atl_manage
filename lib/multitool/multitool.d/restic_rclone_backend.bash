#shellcheck shell=bash
# [Plugin]
# Name = Restic RClone Backend
# Description = RClone backend for Restic
# Tags = Restic_rclone_backend
# Enabling_tag = Restic_rclone_backend
#
# [Help:Restic_rclone_backend]
# Address = Set the port the RClone restic backend listens for connections on. IPaddress:Port, :Port or [unix://]/path/to/socket to bind server to (default [127.0.0.1:8999])
# RESTIC_REPOSITORY = URL to rclone backend. E.g. rest:http://... or unix:///path/to/socket
# Servicename = Name of the systemd service to run rclone backend in. Not normally needed.
#
# [Restic_rclone_backend]
# Address = localhost:8999
# Socketaddr = localhost:8999
# RESTIC_REPOSITORY = rest:http://${_restic_rclone_backend__address}
# Servicename = ${_script__name}-rclone-backend

_validate_headervars() {
	[[ -v _script__name ]] || __fail "Please define [Script] Name = ... to be used in rclone background service name"
	[[ -v _rclone__remote ]] || __fail "Please define [RClone] Remote = .... as the RClone remote to serve the backend from. See available remotes with ./rclone listremotes"
	[[ -v _rclone__remotepath ]] || __fail "Please define [RClone] RemotePath = .... as the path within ${_rclone__remote} to serve the backend from. See available remotes with ./rclone listremotes"
}
_validate_headervars
unset -f _validate_headervars

	#[[ -f $BASE/rclone.conf ]] || __fail "Please run ./rclone config and define $_restic_rclone_backend__rclone_path"

# Starts 'rclone serve restic' in the background, serving the Restic API at $_restic_rclone_backend__socketaddr
# @pre:*
rclone_backend_start() {
	rclone listremotes | grep -q "$_rclone__remote" || __fail "Could not find remote $_rclone__remote defined"
	# FIXME: detect properly whether the service is installed at all, vs. runnning
	if _rrb_systemctl list-unit-files "$_restic_rclone_backend__servicename".service >/dev/null; then
		#__log >&2 "Hey, we already have a $_restic_rclone_backend__servicename.service"
		out="$(_rrb_systemctl is-active "$_restic_rclone_backend__servicename" || :)"
		case "$out" in
			active) __log >&2 "$_restic_rclone_backend__servicename is already active" ;;
			failed)
				__log "Starting existing (failed, e.g. due to timeout) $_restic_rclone_backend__servicename"
				_rrb_systemctl start "$_restic_rclone_backend__servicename"
				;;
			inactive)
				_rrb_systemctl start "$_restic_rclone_backend__servicename"
				;;
			*) 
				__fail "Unhandled transient service state '$out'"
				;;
		esac
	else
		# This creates a 'transient' service - handy!
		# The password is to decrypt rclone.conf. It is slightly pointless since this file is equally vunerable. There is nothing else important in GDrive.
		__log "Starting new $_restic_rclone_backend__servicename"
		_rrb_systemd-run -u "$_restic_rclone_backend__servicename" \
			--description="rclone backend for $_script__name restic" \
			-p Restart=on-failure \
			-p SuccessExitStatus=143 \
			"$_script__path" rclone \
			serve restic -vv \
			"$_rclone__remote:$_rclone__remotepath" \
			--addr "${_restic_rclone_backend__address}"
		_rrb_systemctl reset-failed
	fi
	_rrb_systemctl is-active --quiet "$_restic_rclone_backend__servicename" || __fail "Failed to launch rclone backend for restic"
	# Give rclone a chance to start
	rclone_backend_waitfor
}

rclone_backend_stop() {
	if _rrb_systemctl is-active --quiet "$_restic_rclone_backend__servicename"; then
		__log "Stopping active restic backend"
		_rrb_systemctl stop "$_restic_rclone_backend__servicename"
	else
		if pgrep -x rclone; then
			pgrep -a rclone
			__log "Problem: $_restic_rclone_backend__servicename is not active, but rclone is running"
		fi
	fi
}

rclone_backend_listening() {
	lsof -sTCP:LISTEN -i "@$_restic_rclone_backend__socketaddr" >/dev/null
}

rclone_backend_waitfor() {
	local c=10
	while (( c-- > 0)) && ! rclone_backend_listening; do
		__log -n .
		sleep 0.1
	done
}

rclone_backend_status() {
	_rrb_systemctl status "$_restic_rclone_backend__servicename"
}

# For our restic rclone backend, we want --user services if run by non-root, and root if run as EUID 0
_rrb_systemctl() {
	if [[ $EUID = 0 ]]; then
		$(which systemctl) "$@"
	else
		$(which systemctl) --user "$@"
	fi
}

# For our restic rclone backend, we want --user services if run by non-root, and root if run as EUID 0
_rrb_systemd-run() {
	if [[ $EUID = 0 ]]; then
		$(which systemd-run) "$@"
	else
		$(which systemd-run) --user "$@"
	fi
}


