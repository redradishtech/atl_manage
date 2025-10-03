#shellcheck shell=bash
# 
# [Plugin]
# Name = RClone
# Description = Adds ./rclone wrapper, set up for this project.
#
# [Help:RClone]
# RCLONE_CONFIG = sets the rclone.conf location
# RCLONE_CONFIG_PASS = sets a password
#
# [RClone]
# RCLONE_CONFIG=${_script__basedir}/rclone.conf
# RCLONE_CONFIG_PASS=

# ./restic --help is passed through to the restic binary
command -v rclone >&/dev/null || __fail "Please install rclone (used as a backend to restic)"

# Invokes rclone with RCLONE_CONFIG and RCLONE_CONFIG_PASS set as specified
# @nohelp
# ./rclone --help is passed through to the binary
rclone() {
	#__log "In rclone: $(declare -p RCLONE_CONFIG)"
	#__log "In rclone: $(declare -p RCLONE_CONFIG_PASS)"
	__log "Running rclone ${RCLONE_CONFIG}"
	"$(which rclone)" "$@"
}

__addhelp rclone 'Calls rclone with the script-specific settings'
