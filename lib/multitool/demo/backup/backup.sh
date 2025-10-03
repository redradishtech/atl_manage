#!/bin/bash -eu
# [Script]
# Name = backup-etc
# Description = Backup /etc with Restic
#
# [Restic]
# RESTIC_PASSWORD='hunter2'
# RESTIC_REPOSITORY="/var/backups/my-etc-backup"
#
# [RClone]
# RCLONE_CONFIG_PASS=hunter2
#
# [Devbox]

printenv() {
	echo "$PATH"
}


# Trigger a backup
# @sudo
# @main
backup() {
	restic version
    dirs=( /etc )
    restic backup --one-file-system --verbose=1 "${dirs[@]}"
}

# Restore files to DIR
# @sudo
restore() {
    (( $# == 1 )) || { echo >&2 "Usage: $0 DIR"; exit 1; }
    local restoredir="$1"
    restic restore latest --target "$restoredir"
}

# Print what is in the latest Restic backup
# @sudo
lsbackup() {
    restic ls latest
}

. ../../multitool.bash
