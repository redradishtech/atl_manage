#shellcheck shell=bash
# Note that atl_upgrade is SOURCED, so there is no hashbang, meaning:
# - we need to explicitly set -eu if we need it
# - the script must not exit(), but rather return()

atl_upgrade() (
	#shellcheck source=/opt/atl_manage/lib/common.sh
	source "$ATL_MANAGE/lib/common.sh" --nolog

	# In subshell so we can rely on set -eu quickfail behaviour
	set -eu

	local upgradelockfile
	upgradelockfile="$(lockdir)/upgrade.lock"

	deploynew() {
		# We wrap atl_install and the rest of the script in lockfiles
		# This is because atl_install may invoke vim to resolve conflicts, and if one ctrl-Z's vim, atl_install exits with code 148, either killing the script or causing the remainder to run prematurely. By claiming a lockfile we ensure that the rest of the script won't run until atl_install really is finished.
		(
			set -eu
			log "Now locking $upgradelockfile and calling atl_install --rebase"
			flock -x 200
			rm -f "$ATL_APPDIR_BASE/$ATL_NEWVER/UPGRADING_DO_NOT_START" # If we're running after an initial failure, delete the marker file so atl_deploy doesn't complain
			if [[ -d $ATL_APPDIR_BASE/$ATL_NEWVER ]]; then
				atl_redeploy --rebase                                         # Deploy new version without activating it yet (since our 'current' symlink isn't updated that would be pointless)
			else
				atl_deploy --rebase
			fi
			cd "$ATL_APPDIR_BASE/$ATL_NEWVER"
			# Add a marker in case the upgrade fails past the point of no return ('atl_profile') but before we've activated and taken a backup.
			# This marker is checked for by $ATL_MANAGE/events/start-pre/check_mid_upgrade, and removed later in this script.
			# FIXME: Perhaps instead we could a) put the backup into 'upgrade-stopped-post', b) somehow have 'install-post' and 'upgrade-stopped-post' events record a marker of their action ($ATL_LOGDIR/events/), c) check for those records before allowing startup.
			echo "$(date): This app is not yet ready to be started, as the old version has yet to be backed up." >UPGRADING_DO_NOT_START
			# FIXME: why would there ever be unpushed changes? The 'push_patches_upstream' function in 'create_patchqueue' should do it.
			#hg push --mq || true # if there's nothing to push, continue. Note that it is okay for .hg/patches/guards to contain uncommitted changes (transient guards)
		) 200>"$upgradelockfile"
		# Note that [[...]] is itself a statement resetting $?, so we must capture $? in a variable
		exitcode=$?
		if [[ $exitcode != 0 ]]; then
			echo >&2 "Failed to obtain lock $upgradelockfile ($(_lsof "$upgradelockfile"))"
			return $exitcode
		fi
	}

	doupgrade() {
		stop_app() {
			case "$ATL_PRODUCT_RUNTIME_TECHNOLOGY" in
			php*-fpm) : ;; # Don't stop php-fpm - it is unnecessary and is bad when a dev instance is upgraded on a prod server
			*)
				atl_stop
				wait_for_stop
				log "The app MUST be dead at this point, or $ATL_DATADIR might contain lockfiles. Is it?"
				! atl_running || error "App is not dead"
				;;
			esac
		}

		start_app() {
			case "$ATL_PRODUCT_RUNTIME_TECHNOLOGY" in
			php*-fpm)
				atl_restart
				;;
			*)
				atl_stop
				atl_start || error "atl_start failed, but $ATL_SHORTNAME is upgraded. Fix the cause, then run 'atl_event upgrade-running-post'"
				;;
			esac
		}

		(
			set -eu
			flock 200
			if $ATL_DATADIR_VERSIONED; then atl_upgrade_copydata -f "$@"; fi
			#|| { echo >&2 "switchver check failed"; return $?; }
			# Note: OLD version's event script
			atl_event upgrade-running-pre || {
				warn "upgrade-running-pre event failed. Not proceeding with upgrade."
				return 1
			} #  Check that rsnapshot backups are fresh. Saves a JSON of the plugins. Other misc tasks. Note that if the app is offline (and isn't a standby), this event's actions will fail. This is intentional as we might really need those plugin definitions, for instance, but there might be cases where we want to upgrade an offline app. For now, just append '|| true' in that case.
			stop_app
			if $ATL_DATADIR_VERSIONED; then atl_upgrade_copydata -f "$@"; fi
			atl_event upgrade-stopped-pre # Tag our most recent rsnapshot backup. Note this is the OLD version's event script

			newver="$ATL_NEWVER"
			atl_upgrade_switchver upgrade
			set +eu
			#shellcheck source=/opt/atl_manage/lib/profile.sh
			source "$ATL_MANAGE/lib/profile.sh"
			atl_load "$ATL_FQDN" # FIXME: Can't use ATL_LONGNAME in multitenant
			set -eu
			if [[ $ATL_VER != "$newver" ]]; then
				warn "Unfortunately 'atl_upgrade_switchver upgrade' failed to change our version to $newver. Please fix the profile file manually, then exit this subshell"
				bash
			fi
			[[ $ATL_VER = "$newver" ]] || fail "Manual intervention failed: ATL_VER is still '$ATL_VER', not $newver as expected"
			log "Hooray, after switching versions we're at $ATL_VER"
			# Our previous run of atl_install wouldn't have reloaded systemd, apache etc, because current/ didn't point to $ATL_NEWVER. Do it now.

			atl_activate || {
				local msg="Sadly 'atl_activate' failed, which means the upgraded-to app is now in place, offline, but our upgrade steps (notably backup) are not yet complete. Proceed as follows:"
				nextsteps="Fix 'atl_activate'"
				if [[ $ATL_ROLE =~ prod ]]; then
					nextsteps+="\natl_upgrade_database_backup\n"
				fi
				if ! [[ $ATL_ROLE =~ standby ]]; then
					nextsteps+="\natl_start\n"
					nextsteps+="\natl_event upgrade-running-post\n"
				fi
				error "$msg $nextsteps"
				export ATL_NEXTSTEPS="$nextsteps"
			}
			if [[ $ATL_ROLE =~ prod ]]; then
				atl_upgrade_database_backup
			else
				log "Not backing up database in non-prod ($ATL_ROLE) environment"
			fi
			atl_event upgrade-stopped-post # E.g. Jethro applies post-upgrade SQL changes. Note that this is the NEW version's event script

			rm -f "$ATL_APPDIR"/UPGRADING_DO_NOT_START
			if [[ $ATL_ROLE =~ standby ]]; then
				:
			else
				echo "Not starting. Do this manually after deleting plugins"
				echo start_app
				case "$ATL_PRODUCT" in
				jira | confluence)
					log "Now go to $ATL_BASEURL/plugins/servlet/upm/manage/action-required to upgrade plugins"
					#ATL_SHORTNAME=jira ATL_VER=7.11.1 getplugindata --load | jq '.[] | select(.key=="com.atlassian.servicedesk").key '
					if [[ $ATL_PRODUCT = jira ]]; then log "Also go to $ATL_BASEURL/plugins/servlet/applications/versions-licenses to upgrade ServiceDesk (if installed)"; fi
					log "When $ATL_PRODUCT upgrade tasks are complete (and note before): run atl_event upgrade-running-post. This reinstates SQL views which can break upgrade tasks."
					;;
				esac
			fi
		) 200>"$upgradelockfile"
		exitcode=$?
		if [[ $exitcode != 0 ]]; then return $exitcode; fi
	}

	##################################################################################################################################
	# atl_upgrade begins
	##################################################################################################################################

	[[ -v ATL_NEWVER ]] || error "ATL_NEWVER is not defined"
	# Disable 'maintenance' until it is per-app
	#atl_maintenance check
	atl_upgrade_switchver check
	atl_upgrade_cleanup_old_directories &
	deploynew "$@"
	atl_upgrade_switchver check
	doupgrade "$@"

	log "Upgrade completed, hopefully successfully. Now: 'cd $ATL_PROFILEDIR; hg commit'"
)

# vim: set filetype=sh:
