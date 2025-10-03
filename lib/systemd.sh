# shellcheck shell=bash source=/opt/atl_manage/lib/systemd.sh
#
# For containsElement
. "$ATL_MANAGE/lib/common.sh"

# Exports the $1 systemd service's properties ($2, $3, ...) if given; all of them otherwise
# Sample use: systemdvars "$ATL_SYSTEMD_SERVICENAME" ExecMainStartTimestamp ExecMainPID ActiveState
systemdvars() {
	(($# > 1)) || error "Usage: systemdvars <service> [properties]"
	local service="$1"
	shift
	while (($#)); do
		val="$(systemctl show --property "$1" --value "$service")"
		#log "Setting $1=$val"
		export "$1"="$val"
		shift
	done
}

# Installs a systemd service or socket. $1 must be relative to $ATL_APPDIR
installservice() {
	local servicefile 
	if [[ ${1:0:1} = / ]]; then servicefile="$1"; else servicefile="$ATL_APPDIR"/"$1"; fi
	[[ -f $servicefile ]] ||  error "Unable to find $servicefile. This is usually created by the patch queue"
	chronic systemd-analyze verify "$servicefile" || error "Invalid systemd service file. Not installing: $servicefile"

	local servicename="$(basename "$servicefile")"    # E.g. jira.service or jira-oomhandler.socket
	# Note: servicefile must be an absolute path for the 'link' and 'enable' commands later to succeed - hence the 'readlink -f'. It also must use the 'current' symlink (not $deploymentdir) or we'll break across upgrades.
	local servicedest=/etc/systemd/system/"$servicename"

	# All we have to do for template units like *-oom@.service is copy them over
	if [[ $servicename =~ @.service$ ]]; then
		log "Copied $servicefile to /etc/systemd/system"
		install -o root -g root -m 644 "$servicefile" /etc/systemd/system/
		systemctl daemon-reload
		return
	fi

	# FIXME: separate this into a 'link' and then 'possibly enable' phases. Support an ATL_SERVICE_INITIALSTATE variable to generalise the check for 'standby'. This would allow sandboxes on the primary VM to be installed shut down.
	if systemctl is-enabled "$servicename" >/dev/null 2>&1; then
		log "$servicename is already enabled"

		# Even if we're enabled, our systemd script might have changed, and if we didn't use a symlink then we need to copy the new file to /etc/systemd/system
		if ! systemd_servicefiles_symlinked; then
			if cmp "$servicefile" "$servicedest" >/dev/null; then
				local reload_after=true
			else
				local reload_after=false
			fi
			log "Updating non-symlink systemd service: $servicedest"
			# Always copy, even if no content change, to ensure permissions are correct
			install -o root -g root -m 644 "$servicefile" /etc/systemd/system/
			if [[ $reload_after ]]; then
				log "Reloading systemd to pick up $servicedest change"
				systemctl daemon-reload
			fi
		fi

		expectedstate=(enabled static)
		if [[ $ATL_ROLE =~ standby ]]; then
			# The app should not be started automatically on the standby. If it is enabled (e.g. due to previously being live), disable it
			systemctl disable "$servicename"
			log "Disabling systemd service on standby"
			expectedstate=(disabled linked)
		fi
	else
		# not enabled; perhaps not even existing yet

		# On ZFS we must copy, not symlink the service file to /etc/systemd/system, because systemd needs to resolve all its dependencies before starting the ZFS filesystem. This section ensures the file is present in /etc/systemd/system in this case.
		if ! systemd_servicefiles_symlinked; then
			if [[ -L $servicedest ]]; then
				error "Uh-oh, $servicedest should not be a symlink on ZFS systems. Please fix manually"
			fi
			if [[ ! -f $servicedest ]]; then
				log "Installing non-symlink systemd service: $servicedest"
			elif ! cmp "$servicefile" "$servicedest" >/dev/null; then
				log "Updating non-symlink systemd service: $servicedest"
			fi
			install -o root -g root -m 644 "$servicefile" /etc/systemd/system/
		else
			if [[ -f $servicedest && ! -L $servicedest ]]; then
				warn "$servicedest was not a symlink, as expected. Replacing it with a symlink to $servicefile"
				rm "$servicedest"
			fi
			if [[ -L $servicedest ]]; then
				# Probably an older version. If we don't get rid of it, 'systemctl link' fails with: Failed to link unit: File /etc/systemd/system/jira.service already exists and is a symlink to /opt/atlassian/jira/8.20.11/systemd/jira.service
				rm "$servicedest"
			fi
			systemctl link "$servicefile"
		fi

		# At this point we have our service file in /etc/systemd/system/foo.service.

		if [[ ! $ATL_ROLE =~ standby ]]; then
			# Systemd 252+ doesn't like enabling a $servicefile which is already in-place
			systemctl enable "$servicename" # This symlinks $servicefile into /etc/systemd/system, and also creates symlink in default.target.wants/
			expectedstate=(enabled static)
		else
			log "Not enabling systemd service on standby"
			# From a clean install on standby, my service is 'linked' not 'disabled'. I'm not sure of the difference.
			expectedstate=(disabled linked)
		fi
		log "This service may be edited with 'systemctl edit --full $servicename'"
	fi
	# We don't need to explicitly daemon-reload, as 'enable' and 'disable' do it implicitly
	#log "systemctl daemon-reload'ing"
	#systemctl daemon-reload

	loadstate=$(systemctl is-enabled "$servicename" || true)
	if ! containsElement "$loadstate" "${expectedstate[@]}"; then
		error "$servicename 'is-enabled' reports unexpected state '$loadstate' (expected '${expectedstate[*]}')"
	fi
}

uninstallservice() {
	local servicefile service activestate loadstate
	servicefile="$1"
	service="$(basename "$servicefile")"

	set -x
	# First handle uninstalls of service templates, like oomhandler/$ATL_SHORTNAME-oomhandler@.service that is socket-instantiated.
	if [[ $service =~ @\.service$ ]]; then
		# It's just a template, not an instantiated service.
		if systemctl | grep "${service%.service}"; then
			fail "Asked to uninstall service template '$service', but the abovementioned instantiated services are already running. Please uninstall the instances, not the template"
		fi
		rm -f "/etc/systemd/system/$service"
		return
	fi
	set +x

	activestate=$(systemctl show "$service" | grep ActiveState)
	case $activestate in
	ActiveState=active)
		log "Shutting down $service"
		systemctl stop "$service" || systemctl kill "$service"
		;;
	ActiveState=inactive)
		log "$service is not running"
		;;
	ActiveState=failed)
		: # Last startup failed for some reason. We don't care.
		;;
	*)
		error "$service: Unexpected state $activestate"
		;;
	esac
	loadstate=$(systemctl show "$service" | grep LoadState)
	case $loadstate in
	LoadState=not-found)
		log "No such service: $service"
		;;
	LoadState=loaded)
		#SERVICEFILE=/etc/systemd/system/$ATL_SYSTEMD_SERVICENAME.service # Note: this must be an absolute path for the 'link' and 'enable' commands later to succeed
		systemctl disable "$service"
		[[ ! -e /etc/systemd/system/$service ]] || rm "/etc/systemd/system/$service"
		warn "Disabled and removed $service"
		#rm "$SERVICEFILE"
		#log "Removed $SERVICEFILE"
		systemctl daemon-reload
		;;
	*)
		error "Unexpected systemctl LoadState - expected either 'not-found' or 'loaded', but got '${loadstate}'"
		;;
	esac
}

systemd_servicefiles_symlinked() {
	[[ ! -v ATL_SERVICEFILE_SYMLINK ]] || error "Please unset ATL_SERVICEFILE_SYMLINK. We now infer it based on ATL_ZFS, which we ASSUME is set here??"
	# It seems that when systemd boots and scans /etc/systemd/system/*.service, ZFS filesystems may not be mounted yet, and symlinked .services aren't found.
	[[ ! -v ATL_ZFS || $ATL_ZFS != true ]]
}

