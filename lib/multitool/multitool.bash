#shellcheck shell=bash

set -eu

_multitool_basedir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
. "$_multitool_basedir/parser.bash"
. "$_multitool_basedir/tagutils.bash"

# The multitool _invokesubcommand function is called automatically (at the bottom), unless --source is given.
# It invokes the function indicated by the invoked symlink (./backup -> script.sh), or first arg ('./script.sh backup').
# If --help if the only arg, the multitool _help function is called instead of the function, unless @nohelp is given, in which case --help is passed on to the function.
# Plugins are sourced, which define further functions. Some (sudo.bash, devbox.bash) may re-execute the invoked function.
_invokesubcommand() {
	local func
	# These must all be exported for use in sub-functions
	declare -x _script__path
	declare -x _script__abspath
	declare -x _invokedfunc
	declare -A _funcs			# Function names, as keys mapped to true (enabled) or false
	declare -A _funcsrc			# Map of functions to their defining plugin
	declare -A _args			# Map of functions ot their args
	declare -A _comments		# Map of functions to function comments
	declare -A _tags			# Map of functions to tags (space-separated). E.g. if backup() has @sudo and @execstart tags, we'll have $_tags[backup]="sudo execstart"

	declare -A _plugins			# Plugins, as keys mapped to true (enabled) or false
	declare -A _pluginsrc		# Map of plugin keys to their bash source file path

	__fail_if_looping

	# Set $_script__path and $_invokedfunc, and manipulate $@ (hence this can't be a function)
	if [[ -L $0 ]]; then
		_script_invoked_via_symlink=true   # used by help plugin
		_invokedfunc="$(basename "$0")"	# E.g. 'backup' (symlink)
		# $0 is function name symlink. First resolve the symlink to get the script path, then get the absolute version of it.
		# The --no-symlinks is to avoid resolving any more symlinks when going from rel to abs.
		local relbase="$(dirname "$(realpath --no-symlinks --relative-to=. "$0")")"  # E.g. 'backups/backup-foo-to-cloudflare'
		local absbase="$(dirname "$(realpath --no-symlinks "$0")")"  # E.g. 'backups/backup-foo-to-cloudflare'
		local referent="$(basename "$(realpath "$0")")"  # E.g. 'script.sh'
		_script__path="$relbase/$referent"
		_script__abspath="$absbase/$referent"
		# Relative path, used for symlinking (and by default). The './' is needed for when invoked by sudo -E
	else
		_script_invoked_via_symlink=false   # used by help plugin
		_script__path="$0"
		_script__abspath="$(realpath --no-symlinks "$_script__path")"
		if (( $# > 0 )); then
			if [[ $1 = --help ]]; then
				_invokedfunc=help
			else
				_invokedfunc="$1"     # E.g. 'script.sh'
			fi
			shift
		fi
	fi

	declare -rx _script__basename="$(basename "$_script__path")"
	declare -rx _script__basedir="$(dirname "$_script__abspath")"
	# For backwards-compatibility
	declare -rx _BASE="$_script__basedir"

	# Put our baedir first, as we often override versions of other apps, e.g. ./restic or ./systemd, and want our version called preferentially.
	# When invoked in devbox --pure, our PATH contains nothing but .devbox/* stuff. We need a handful of things from /usr/bin
	export PATH=$PATH:/usr/bin


	declare -A _scriptvars=()   # Array with config vars from our main script.sh.
	declare -A _vars=()		# Merged config vars set from the script ($_scriptvars) and plugin headers ($_$plugin). This variable can be read and edited by plugins when they are sourced.

	__parse_bash_extracting_funcs "$_script__path" "$_script__basename" _funcs _funcsrc _args _comments _tags	# Inspect script to learn available functions and tags
	__parse_bash_headers "$_script__path" _scriptvars

	# Don't use $XDG_CONFIG_HOME as it is user-specific and breaks when running in root systemd.
	export _rcfile="/etc/multitool/defaultheader.bash"
	if [[ -f $_rcfile ]]; then
		echo >&2 "Parsing $_rcfile"
		__parse_bash_headers "$_rcfile" _scriptvars
	fi

	local pluginkey
	for f in "$_multitool_basedir"/multitool.d/*.bash; do
		pluginkey="$(basename "${f%.bash}")"		# e.g. systemd
		_plugins["$pluginkey"]=true
		_pluginsrc["$pluginkey"]="$f"
		__parse_bash_extracting_funcs "$f" "$pluginkey" _funcs _funcsrc _args _comments _tags	# Inspect script to learn available functions and tags
		eval "declare -A _$pluginkey=()"
		__parse_bash_headers "$f" "_$pluginkey"
	done

	__trim_unused_plugins			# Reduce _plugins to only those actually used
	#__print_enabled_plugins

	__squish_scriptvars_and_pluginvars_into _vars	# Merge _scriptvars and all plugin arrays into $_vars, which is the finally actually-useful form
	__unset_pluginvars								# We're done with the $_$plugins arrays (their contents has been merged into $_vars), so delete them
	__expand_vars _vars								# Expand header config vars, e.g. ${_script[Name]} becomes ${_script__name}
	__expand_tags _tags								# Set a string variable for each tag, with value being a space-separated list of tagged functions.  E.g. if we have _tags=([backup]="main" [sudo]="pre:*"), this function sets _tag_main="backup" and _tag_pre_STAR="sudo". I.e. _tags is inverted.  Plugins can then evaluate _tag_foo to see how they apply to them e.g. systemd reads $_tag_execstart to find the @execstart-tagged function.

	# Source enabled plugin functions
	local pluginkey
	for pluginkey in "${!_plugins[@]}"; do
		[[ ${_plugins[$pluginkey]} == true ]] || continue
		local fsrc="${_pluginsrc[$pluginkey]}"
		# Plugins, when sourced here, may read and modify _vars and _tags. E.g.:
		# - validate that required variables are set (_validate_vars), e.g. systemd.bash checking for _script__name
		# - inspect tags and set NEW variables (_processtags), e.g. systemd.bash reading @execstart and setting _service__execstart
		# - set new tags on functions, e.g.:
		# -- systemd.bash setting @sudo on functions if [Service] _Type=root
		# -- healthchecks.bash setting pre:_healthchecks_start on the @main-tagged function
		# - check for the presence of required binaries, e.g. rclone.bash, restic.bash
		#
		#echo "Sourcing $pluginkey"
		. "$fsrc"
	done

	# It is tempting to unset _vars here, and have plugins, now initialized, just used the expanded $_section__variable vars. However systemd.bash makes good use of _vars to generate systemd service files. 
	# unset _vars

	#__print_parsed_fields _funcs _args _comments _tags

	# Now we know all available functions, and have all bash variables, defined, actually invoke _invokedfunc

	# e.g. the user ran ./backup --help
	if [[ ${1:-} = --help && ! ${_tags[$_invokedfunc]:-} =~ nohelp ]]; then
		_help "$_invokedfunc"
		exit
	fi

	if [[ -v _invokedfunc ]]; then
		: # E.g. ./foo, ./script.sh foo
	else   # No particular function invoked via symlink or first arg
		if [[ -v _tag_main ]]; then
			# No function chosen, but we have a @main. Invoke it
			_invokedfunc="$_tag_main"
		else
			# No function, no @main. Default to help 
			_invokedfunc=help
		fi
	fi

	if [[ -v _args[$_invokedfunc] ]]; then
		if (( $# < ${#_args[$_invokedfunc]} )); then
			# $_invokedfunc requires args, but there aren't any given! Print help and exit
			_help "$_invokedfunc"
			exit
		fi
	fi

	# Possibly a bad idea, but convenient.
	# The tty check is so we don't do this from a systemd service.
	if [[ -t 1 ]]; then _createsymlinks; fi


	# Finally we can invoke the function. Actually, because many plugins define functions tagged 'pre:*', we have to call a whole dependency graph's worth of functions. The dependency graph is figured out in tagutils.bash (from $_tags)

	local _invokedfuncs
	_invokedfuncs=($(function_with_tag_dependencies _tags "$_invokedfunc"))
	# TODO: handle ./script.sh --plugins user error nicely
	__log "Invoking funcs: ${_invokedfuncs[*]}"
	for func in "${_invokedfuncs[@]}"; do
		__invokefunc "$func" "$@"
	done
}

__fail_if_looping() {
	declare -gx __multitool_invokecount
	: "${__multitool_invokecount:=0}" 
	(( __multitool_invokecount+=1 )) || :
	if (( __multitool_invokecount > 3 )); then
		echo >&2 "multitool looped $__multitool_invokecount times!"
		exit 1
	fi
}

__invokefunc() {
	local func="$1"; shift
	#echo >&2 "Invoking $func" 
	[[ -v _funcs[$func] && ${_funcs[$func]} == true ]] || return 0   # Funcs of disabled plugins
	_function__comment="${_comments[$func]:-}"
	if [[ -v _tags[$func] ]]; then
		_function__tags="${_tags[$func]}"
		#echo "$func: has tags $_function__tags"
	else
		: #echo "$func: no tags"
	fi
	if [[ -v _tags[$func] ]]; then declare -n _function_tags=_tags[$func]; fi
	_function__tags="${_tags[$func]:-}"
	"$func" "$@"
}

# Returns true if $_invokedfunc was tagged with $1. This is a fast alternative to inverting $_tags into $_$tag arrays
__istaggedwith() {
	local tag="$1"
	# ${_tags[*]@K} expands to e.g. backup "main sudo execstart" _shutdown "@execstop"
	#echo >&2 "Checking for tag $tag in: ${_tags[*]@K}"
	[[ -v _invokedfunc && ${_tags[*]@K} =~ $_invokedfunc\ \"[^\"]*$tag  ]]
}

__trim_unused_plugins() {
	# At this point we know all sections defined by a plugin ($_$plugin[_section]=true), and whether any were referenced ($_scriptvars[_section]=true). We can thus remove from $_plugins all unused plugins, and later we know all variables defined are used in some way.
	local pluginkey

	# This loop sets _plugins[$pluginkey] to false if none of $pluginkey's sections were referenced in script.sh
	for pluginkey in "${!_plugins[@]}"; do
		declare -n pluginvars=_$pluginkey					# Vars only from our script.sh or a particular plugin
		local plugin_has_sections=false										
		local script_uses_plugin_section=false
		local k
		# set used=true if any of this plugin's sections are enabled in script.sh's header (_scriptvars)
		for k in "${!pluginvars[@]}"; do					# e.g. _service or __service__Description
			if [[ $k =~ __ ]]; then continue; fi			# We're only interested in sections (e.g. '_service') not vars (e.g. '_service__description')
			if [[ $k = _plugin ]]; then continue; fi		# The '[Plugin]' tag doesn't count for the purposes of "something to reference in the main script"
			plugin_has_sections=true
			if [[ -v _scriptvars[$k] ]]; then
				script_uses_plugin_section=true
			fi
		done
		if $plugin_has_sections && $script_uses_plugin_section || ! $plugin_has_sections; then
			:
			#echo "Keeping $pluginkey, as it is used"
		else
			#echo "Dropping $pluginkey as it is unused"
			_plugins[$pluginkey]=false
		fi
	done

	# Mark functions (known from parsing, not yet sourced) as disabled if they are from a disabled plugin. This is used in help() to distinguish enabled and disabled functions
	local func 
	for func in "${!_funcs[@]}"; do
		local pluginkey="${_funcsrc[$func]}"
		# script.sh funcs are not in _plugins and are always enabled
		if [[ ! -v _plugins[$pluginkey] ]] || ${_plugins[$pluginkey]}; then
			:
			#echo "Function $f from plugin $p is enabled"
		else
			#echo "Function $f from plugin $p is DISABLED"
			_funcs[$func]=false
		fi
	done
}

__print_enabled_plugins() {
	local pluginkey
	echo "Plugins:"
	for pluginkey in "${!_plugins[@]}"; do
		if ${_plugins[$pluginkey]}; then
			printf "%-25s %s\n" "$pluginkey" "✓"
		else
			printf "%-25s %s\n" "$pluginkey" "X"
		fi
	done
}

__addhelp() {
	_funcsrc["$1"]="$_script__basename"
	_funcs["$1"]=true
	_comments["$1"]="$(eval "echo \"${2}\"")"
}

_createsymlinks() {
	local f
	if [[ $(realpath "$PWD") = "$_script__basedir" ]]; then
		for f in "${!_funcs[@]}"; do
			[[ ${_funcs[$f]} == true ]] || continue   # Funcs of disabled plugins
			[[ ${f:0:1} != _ ]] || continue
			if [[ ! -e $f ]]; then
				echo "Creating symlink: $f"
				# Note we use $_script__path, not $_script__abspath because it's nice to have non-absolute symlinks. Then they don't all break if the directory is relocated
				ln -s "$_script__path" "$f"
			fi
		done
	else
		echo "Not creating symlinks in $PWD, as it is not $_script__path's directory"
	fi


	# While developing a script, functions come and go, and so should their symlinks. Creating
	# new symlinks for new functions is easy, but we also need to remove symlinks for removed
	# functions. Only do this if we are in $_script__path's directory, where we can reasonably assume
	# all symlinks are from past _createsymlinks runs.

	if [[ $(realpath "$PWD") = "$(realpath "$(dirname "$_script__path")")" ]]; then
		# Of existing $CWD symlinks, filter out those mapping to functions, and the rest are likely obsolete symlinks created by this script, pointing to functions that no longer exist.
		# Note: we want to read from the user's stdin here, so we can't have a pipe of filenames, but rather use map variables. 
		# symlinks may contain whitespace, hence \n separator
		local oldsymlinks unusedsymlinks
		#__fail "rclone backend plugin is ${_plugins[restic_rclone_backend]}, and function is ${_funcs[rclone_backend_listening]}. They should both be false"
		IFS=$'\n' mapfile -t oldsymlinks < <(find "." -maxdepth 1 -type l -exec basename {} \;)
		mapfile -t unusedsymlinks < <(comm -23 <(IFS=$'\n'; echo "${oldsymlinks[*]}"|sort) <( for f in "${!_funcs[@]}"; do if ${_funcs[$f]}; then echo "$f"; fi; done |sort))

		for unused in "${unusedsymlinks[@]}"; do
			local referent 
			echo "Considering symlink $unused"
			referent="$(realpath --no-symlinks "$(readlink "$unused")")"
			if [[ $referent = "$_script__abspath" ]]; then
				echo "Removing $unused, as it is a symlink to our script, but isn't the name of a function"
				rm "$unused"
			fi

			if [[ ! -e "$referent" ]]; then
				# Normally one would have a directory dedicated to our multitool-using script, and the directory would
				# contain symlinks for each function. In that scenario it is fine to delete broken symlinks, as it is
				# highly likely multitool created them. But just in case someone runs 'multitool.bash _createsymlinks'
				# in their home directory, let's ask before deleting.
				read -rp "Remove $unused? It is a symlink whose referent ($referent) does not exist (Y/n) " yesno
				case "$yesno" in 
					[yY]*) rm "$unused";;
				esac
			fi
		done
	else
		echo "Not deleting symlinks in $PWD, as it is not $_script__path's directory"
	fi
}

__fail() { echo >&2 "$*"; exit 1; }


case "${1:-}" in
	--source) : ;;
	*) _invokesubcommand "$@";;
esac

# vim:set ft=sh:
