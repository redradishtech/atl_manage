# [Plugin]
# Name = Help
# Description = Generate --help from function headers.

# Define 'help' if not already done so. If script.sh defines help(), it may then call _help
if ! declare -F help >/dev/null; then
	# Awful hack: help() must be on a newline so parser.sh sees it
	declare -F help >/dev/null ||
help() { _help "$@"; }
fi

# Print help, either of all functions or of the $1 function only.
_help() {
	local PARSED
	PARSED=$(getopt --options '' --longoptions 'plugins,plugin:' --name "$0" -- "$@")
	# use eval with "$PARSED" to properly handle the quoting
	eval set -- "$PARSED"
	local showplugins=false
	local showhelpforplugin=
	while true; do
		case "$1" in
		--plugins) showplugins=true ;;
		--plugin)
			shift
			showhelpforplugin="$1"
			showplugins=true
			;;
		--)
			shift
			break
			;;
		esac
		shift
	done
	declare -A pluginfuncs pluginfuncs_enabled pluginfuncs_disabled
	local f
	for f in "${!_funcsrc[@]}"; do
		local plugin="${_funcsrc[$f]}"
		pluginfuncs[$plugin]+=" $f"
		if ${_funcs[$f]}; then
			pluginfuncs_enabled[$plugin]+=" $f"
		else
			pluginfuncs_disabled[$plugin]+=" $f"
		fi
	done

	if (( $# == 0)); then

		if [[ $showplugins = false ]]; then

			if [[ -v _script__description ]]; then
				echo "Description: ${_script__description:-}"
			fi
			if $_script_invoked_via_symlink; then
				echo "Commands"
			else
				echo "Usage: $(basename "$0") COMMAND"
				echo "Where COMMAND is:"
			fi
			for p in "${!pluginfuncs_enabled[@]}"; do
				for f in ${pluginfuncs_enabled[$p]}; do
					[[ ! $f =~ ^_ ]] || continue
					_help "$f"
				done
			done
			echo
			echo "Run './help --plugins' to see functions made available by plugins"
		else
			echo "Plugins:"
			local pluginkeys=("${!_plugins[@]}")
			if [[ $showhelpforplugin != '' ]]; then
				pluginkeys=($showhelpforplugin)
			fi
			for pluginkey in "${pluginkeys[@]}"; do	# e.g. 'systemd', the name of an assoc. array with plugin header info
				[[ $showhelpforplugin = '' || $showhelpforplugin = "$pluginkey" ]] || continue
				declare -n pp=_$pluginkey
				#if ! ${_plugins[$pluginkey]}; then
				#	echo "	FYI: Plugin $pluginkey is disabled"
				#fi

				#declare -p _restic_rclone_backend
				local k

				# Annoyingly, keys are not listed in order, so we must accumulate parts of the help text ($sectiontext, $sectionvars), and then display them in the right order at the end)
				declare -A helptext=()
				for k in "${!pp[@]}"; do
					#__log "k=$k"
					# We have tricky keys like _help_service___Type, where 'service' should match the first (.+) and '_Type' the second (.*). But bash doesn't support non-greedy (.+?) in the first, so we have to explicitly deal with that case in the first regex
					if [[ $k =~ ^_help_(.+)__(_.+)$ || $k =~ ^_help_(.+)__(.+)$ ]]; then
						local pluginsection="${BASH_REMATCH[1]}"
						[[ -v pp[_$pluginsection] ]] || __fail "Got help for $pluginsection, but no such section exists??"
						local pluginvar="${BASH_REMATCH[2]}"
						local help="${pp[$k]}"
						# Note: no var expansion of $help until we have a way of preventing it when necessary, e.g. the '$HOSTNAME' in [Help:Script] -> ProductionHost
						# This is no longer an error. E.g. isproduction.bash defines [Help:Script] ProductionHost=..., but deliberately doesn't define a default [Script] ProductionHost
						#[[ -v pp[_${pluginsection}__${pluginvar}] ]] || __fail "Got help for ${pluginsection}__${pluginvar} but no default value for it is set in the plugin settings"
						local pluginvalue="${pp[_${pluginsection}__${pluginvar}]:-}"
						printf -v help "    %-20s %s %s\n" "$pluginvar" "$help" "(default: ${pluginvalue:-none})"
						helptext[$pluginsection]+="$help"
					elif [[ $k =~ ^_help_(.+)$ ]]; then
						local pluginsection="${BASH_REMATCH[1]}"
						[[ -v pp[_$pluginsection] ]] || __fail "Got help for $pluginsection, but no such section exists??"
					fi
				done

				echo
				echo "${pp[_plugin__Name]} - ${pp[_plugin__Description]}"
				for section in "${!helptext[@]}"; do
					echo "  [$section]"
					echo -n "${helptext[$section]}"
				done
				for f in ${pluginfuncs[$pluginkey]:-}; do
					[[ ! $f =~ ^_ ]] || continue
					[[ $showhelpforplugin = '' || $showhelpforplugin = "$pluginkey" ]] || continue
					_help "$f"
				done
			done
		fi
	else
		local helpfunc="${1:-}"
		local funcargs comment
		local f

		if [[ -v _args[$helpfunc] ]]; then
			funcargs="${_args[$helpfunc]}"
		else
			funcargs=""
		fi
		if [[ -v _comments[$helpfunc] ]]; then
			# Indent multiline comments to match the %-25s
			comment="${_comments[$helpfunc]//$'\n'/$'\n'                            # }"
		else
			comment=
		fi
		src="$(basename "${_funcsrc[$helpfunc]:-no source for $helpfunc}")"
		if $_script_invoked_via_symlink; then
			printf "  %-20s # %-70s %s\n" "$helpfunc $funcargs" " $(echo "$comment" | envsubst)" "[$src]"
		else
			printf "  %-20s # %-70s %s\n" "$helpfunc $funcargs" " $(echo "$comment" | envsubst)" "[$src]"
		fi
	fi
}

