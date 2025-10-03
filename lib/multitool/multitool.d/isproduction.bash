# [Plugin]
# Name = IsProduction
# Description = Restricts scripts to run on [Script] ProductionHost/AuxiliaryHost, if specified. Any function may be run on ProductionHost. Functions not tagged @main may be run on AuxiliaryHost.
#
# [Help:Script]
# ProductionHost = regex matching $HOSTNAME of hosts the script should normally run on.
# AuxiliaryHost = regex matching $HOSTNAME of hosts that non-@main functions are allowed to run on.
#
# [Script]

# @pre:*
_runtime__allowed() {
	local allow=true
	if [[ -v _script__productionhost || -v _script__auxiliaryhost ]]; then allow=false; fi
	if _isproduction; then allow=true; fi
	if ! $allow && _isauxiliary; then
		if __istaggedwith main; then
				__fail "@main function '$_invokedfunc' may not be run on auxiliary host"
			else
				allow=true
		fi
	fi
	if ! $allow; then
		__fail "Script is expected to run on '${_script__productionhost}' (ProductionHost)${_script__auxiliaryhost:+ or ${_script__auxiliaryhost} (AuxiliaryHost)}, not '$HOSTNAME'. Perhaps add '$HOSTNAME' as an AuxiliaryHost?"
	fi
}

_isproduction() {
	[[ -v _script__productionhost ]] && [[ $HOSTNAME =~ ^${_script__productionhost}$ ]]
}

_isauxiliary() {
	[[ -v _script__auxiliaryhost ]] && [[ $HOSTNAME =~ ^${_script__auxiliaryhost}$ ]]
}

