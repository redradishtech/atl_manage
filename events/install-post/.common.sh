#shellcheck shell=bash

. /opt/atl_manage/lib/systemd.sh

installcron() {
	local src="$1"
	[[ -f "$src" ]] || error "Asked to install cron '$src' but it does not exist"
	[[ "$src" =~ .*\.cron ]] || error "Unexpected 'cron' filename: «$src». Expected file to end with .cron"
	local hardlink_count="$(stat --printf=%h "$src")"
	if ((hardlink_count > 1)); then
		warn "While installing cron '$src', we found it has $hardlink_count hardlinks. De-hardlinking cron file $src, as otherwise Cron would break. See https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=647193"
		"$ATL_MANAGE/lib/unhardlink.sh" "$src"
	fi
	local hardlink_count="$(stat --printf=%h "$src")"
	[[ $hardlink_count = 1 ]] || error "De-hardlinking failed: $src"
	# If our umask if too restrictive, the cron file won't be readably by 'other'. Fix now:
	chmod 644 "$src"
	dst="/etc/cron.d/$ATL_SHORTNAME-$(basename "${src/.cron/}")"
	ln -sf "$src" "$dst"
	log "Cron file installed: $dst"
}

uninstallcron() {
	local src="$1"
	dst="/etc/cron.d/$ATL_SHORTNAME-$(basename "${src/.cron/}")"
	if [[ -f $dst ]]; then
		rm -f "$dst"
		log "Cron file uninstalled: $dst"
	else
		# This is a normal codepath. E.g. a service with ATL_BACKUP_TYPE=rsnapshot but ATL_ROLE=standby means it isn't enabled, then ../.run.sh calls deactivate, called uninstall-pre calls uninstallcron()
		debug "Asked to uninstall cron file derived from «$src», expected to be at «$dst», but no file was found there"
	fi
}

# shellcheck source=/opt/atl_manage/events/.run.sh
. "$(dirname "${BASH_SOURCE[0]}")"/../.run.sh

# vim: set ft=sh:
