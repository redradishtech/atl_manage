# shellcheck source=/opt/atl_manage/lib/common.sh shell=bash
. $ATL_MANAGE/lib/common.sh --nolog

addguard() {
	local guard="$1"
	if [[ ! -d .hg/patches ]]; then error "No .hg/patches within $PWD"; fi
	local guardfile=".hg/patches/guards"
	if [[ ! -f $guardfile ]] || ! grep -q "^$guard$" "$guardfile"; then
		log "Adding '$guard' to $guardfile in $PWD"
		{
			cat "$guardfile"
			echo "$guard"
		} | sort | sponge "$guardfile"
		log "How does $guardfile look? $(cat $guardfile)"
	else
		log "'$guard' already in $guardfile"
	fi
}

removeguard() {
	local guard="$1"
	if [[ ! -d .hg/patches ]]; then error "No .hg/patches within $PWD"; fi
	local guardfile=".hg/patches/guards"
	if [[ -f $guardfile ]] && grep -q "^$guard$" "$guardfile"; then
		log "Removing '$guard' to $guardfile"
		grep -v "^$guard$" "$guardfile" | sort | sponge "$guardfile"
	else
		:
		# log "'$guard' not present in $guardfile (or guardfile does not exist within $PWD)"
	fi
}
