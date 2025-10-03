#shellcheck source=bash

ssh_for_atlassianapps_installed_correctly() {
	for src in ATL_BACKUPMIRROR_SOURCE ATL_REPLICATION_PRIMARY; do 
		s=ssh_for_atlassianapps.service
		if [[ -v $src && ${!src} = true ]]; then
			systemctl -q is-enabled $s || warn "$s should be installed, as $src is set"
			systemctl -q is-active $s || warn "$s is not running, and is probably needed because $src is set. "
		fi
	done
	for src in ATL_BACKUPMIRROR_DESTINATION ATL_REPLICATION_STANDBY; do 
		if [[ -v ${src} ]]; then
			! systemctl -q is-enabled "ssh_for_atlassianapps.service" || warn "ssh_for_atlassianapps.service should NOT installed on $(uname -n), as $src is set, indicating this is not a source/primary server"
		fi
	done
}
