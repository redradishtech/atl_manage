#shellcheck shell=bash
# Invoked at the end of an event command (e.g. install-post/backups-rsnapshot)
# - usually via an intermdiate common.sh script) - this snippet infers the
# event name from the subdirectory name (e.g. 'install-pre'), then calls the
# shell function ('install-pre' $@).
#
# This allows a single script file ('backups-rsnapshot') to be symlinked into
# various 'event' directories, and have different functions invoked depending
# on which symlink is called. For instance, we currently have 1 file with 3
# events:
#
# install-post/backups-rsnapshot
# cleanup/backups-rsnapshot -> ../install-post/backups-rsnapshot
# uninstall-pre/backups-rsnapshot -> ../install-post/backups-rsnapshot

# shellcheck source=/opt/atl_manage/events/.common.sh
. "$(dirname "${BASH_SOURCE[0]}")"/.common.sh --nolog
if [[ $(type -t "$event") = function ]]; then
	#log "$event function exists"
	# Event commands like events/install-post/backups-tarsnap have an 'enabled' script.
	if [[ $(type -t "enabled") != function ]] || explanation=$(enabled); then
		# atl_event logs the event and command, so don't do it here.
		#log "Running $(basename "$0") $event"
		$event
	else
		# If not enabled, run the 'deactivate' function, if present
		log "$(basename "$0") not enabled ($explanation)"
		if [[ $(type -t "deactivate") = function ]]; then
			log "$(basename "$0") deactivating (in case previously enabled).."
			# FIXME: We need some way to tell 'this was previously enabled, but now isn't', and only the invoke 'deactivate'. Currently we call deactivate for any disabled command on every run. We could avoid doing so with a .getcommands in the event directory, but then we'd never have the opportunity to call deactivate even once.
			# Calling deactivate() every time forces the function to be idempotent. E.g. replication#deactivate has to work even if the replication/ directory isn't present.
			deactivate
		fi
	fi
else
	warn "No function '$event' in $0"
fi

#fn_exists install-post
#if fn_exists "$event"; then
#	log "$event function exists"
#	#$event
#fi
