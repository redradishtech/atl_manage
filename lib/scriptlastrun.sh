#!/bin/bash

SCRIPT_LAST_CHANGED_RECORD_DIRECTORY="$(statedir --global)/script_last_ran_revisions"

# Prints '<lastrunrevision>,<lastrunhash>,<currentrevision>,<currenthahs>', showing the HG versions and sha1 hash that script $1 was at when it last run, vs. now
lastchange_recorded_and_actual_revisions() {
	if ! command -v hg >/dev/null; then
		# Don't break if hg isn't installed
		echo "nohg,nohg,nohg,nohg,nohg"
		return
	fi
	local scriptpath="$1"
	scriptname="$(basename "$scriptpath")"
	mkdir -p "$SCRIPT_LAST_CHANGED_RECORD_DIRECTORY"
	# Note that this hg command will fail with 'not trusting file /opt/atl_manage/.hg/hgrc from untrusted user jturner, group jturner' if run as root, and jturner checked out /opt/atl_manage. This was fixed by /opt/atl_manage/.hgpatchscript/worldreadable chown'ing /opt/atl_manage as root
	# We have a bit of a dilemma regarding which 'hg' version to use: the system /usr/bin/hg, or $ATL_MANAGE/venv/bin/hg:
	# - If we rsync'ed /opt/atl_manage from another installation, then /usr/bin/hg can't update it, breaking with:
	#    abort: repository requires features unknown to this Mercurial: share-safe!
	# - But if we use /opt/atl_manage/venv/bin/hg, we get the error:
	#    ModuleNotFoundError: No module named 'hgdemandimport'
	# - OTOH, we might be executing this before 'atl_setup', in which case $ATL_MANAGE/venv/bin/hg may not be properly installed.
	newrevision="$(hg --cwd "$ATL_MANAGE" log -l 1 "$scriptpath" -T '{rev}')"
	newhash="$(sha1sum "$scriptpath" | cut -d " " -f 1 )"
	if [[ -f "$SCRIPT_LAST_CHANGED_RECORD_DIRECTORY/$scriptname" ]]; then
		cat "$SCRIPT_LAST_CHANGED_RECORD_DIRECTORY"/"$scriptname" | while IFS="	" read -r _scriptpath oldrevision oldhash; do
			
			printf "%s\t%s\t%s\t%s\n" "$oldrevision" "$oldhash" "$newrevision" "$newhash"
		done
	else
		printf "\t%s" "$newrevision"
	fi
}

record_script_run() {
	local scriptpath="$1"
	local out
	scriptname="$(basename "$scriptpath")"
	out="$(lastchange_recorded_and_actual_revisions "$scriptpath")"    # For some reason if this is done inside the <(..), the exit code is zero if $scriptpath hasn't been run
	IFS="	" read -r oldrev oldhash newrev newhash < <(echo "$out")
	[[ "$oldrev $oldhash" = "$newrev $newhash" ]] && SCRIPT_CHANGED=false || SCRIPT_CHANGED=true
	if $SCRIPT_CHANGED; then
		printf "%s\t%s\t%s\n" "$scriptpath" "$newrev" "$newhash" >"$SCRIPT_LAST_CHANGED_RECORD_DIRECTORY/$scriptname"
		debug "Recorded last run (rev=$newrev, hash=$newhash) of $scriptpath in: $SCRIPT_LAST_CHANGED_RECORD_DIRECTORY/$scriptname"
	else
		touch "$SCRIPT_LAST_CHANGED_RECORD_DIRECTORY/$scriptname"  # Update the timestamp so the timestamp check below refreshes
		debug "No change to $scriptpath"
	fi
}

show_scripts_needing_rerun() (
	shopt -s nullglob
	for f in "$SCRIPT_LAST_CHANGED_RECORD_DIRECTORY"/*; do
		cat "$f" | while IFS="	" read -r scriptpath _; do
			[[ -f "$scriptpath" ]] || log "Warning: $scriptpath has disappeared"
			# Proceed (don't 'continue' the loop) only if the script is modified more recently than its 'last change' marker file
			(( $(stat -c %Y "$scriptpath") > $(stat -c %Y "$f") )) || continue
			log "Considering $f / $scriptpath"
			lastchange_recorded_and_actual_revisions "$scriptpath" | while IFS="	" read -r oldrev oldhash newrev newhash; do
				if [[ -z $oldrev ]]; then
					warn "$scriptpath has never been run (per $f)"
				elif [[ $oldrev != "$newrev" ]]; then
					log "Warning: $scriptpath needs to be re-run (see 'hg diff -r $newrev -r $oldrev $scriptpath' to see what changed. Change recorded in $f)"
				elif [[ $oldhash != "$newhash" ]]; then
					log "Warning: $scriptpath needs to be re-run. hg rev $oldrev is the same but sha1sum of $f changed since it was last run. Check last field of the relevant file in $SCRIPT_LAST_CHANGED_RECORD_DIRECTORY - we expect the hash to be $newhash, not $oldhash"
				else
					: #log "There were no changes to $scriptpath since it was last run on this server"
				fi
			done
		done
	done
)
