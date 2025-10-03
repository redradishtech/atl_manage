# [Plugin]
# Name = Restic
# Description = Enable restic, defaulting to ./restic_repo.
#
# [Help:Restic]
# RESTIC_PASSWORD = sets the Restic password (required)
# RESTIC_REPOSITORY = sets the repo location
#
# [Restic]
# RESTIC_PASSWORD =
# RESTIC_REPOSITORY = "${_script__basedir}/restic_repo"

command -v restic >&/dev/null || __fail "Please install restic"

# ./restic --help is passed through to the binary

# Invokes restic with RESTIC_PASSWORD and RESTIC_REPOSITORY set as specified.
# @nohelp
restic() {
	#trap stop_rclone_backend TERM EXIT
	__log "Restic running with repo: $RESTIC_REPOSITORY"
	# For security, don't print the password
	#__log "Restic running with password: $RESTIC_PASSWORD"
	RESTIC_REPOSITORY="$RESTIC_REPOSITORY" RESTIC_PASSWORD="$RESTIC_PASSWORD" "$(which restic)" "$@"
	__log "Restic finished"
	#stop_rclone_backend
}

# Invokes 'restic init --repository-version 2'
# @sudo
restic-init() {
	# This gives us compression. https://forum.restic.net/t/compression-support-has-landed-in-master/4997
	restic init --repository-version 2
}
