#!/bin/bash
redo pid

secs="$2"
case "$secs" in
	''|*[!0-9]*) { echo >&2 "First part must be a number of seconds to sleep. «$secs» is invalid."; exit 1; }
esac
sleep "$secs"  
jcmd "$(cat pid)" Thread.print -l -e
