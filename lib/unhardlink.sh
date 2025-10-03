#!/bin/bash -eu
# Breaks hardlinks of files given as args. See https://serverfault.com/questions/386514/break-all-hardlinks-within-a-folder
# Used by events/install-post/.common.sh to de-hardlink cron files before installing them, since cron doesn't like hardlink>1 files (https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=647193)
set -x
for i in "$@"; do
	temp="$(mktemp -d -- "$(dirname "$i")/hardlnk-XXXXXXXX")"
	[ -e "$temp" ] && cp -ip "$i" "$temp/tempcopy" && mv "$temp/tempcopy" "$i" && rmdir "$temp"
done
