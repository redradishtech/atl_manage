#shellcheck shell=bash
## When symlinked to e.g. bin/atl, provides a frontend to all atl commands; e.g. 'atl list' is an alias for atl_list, 'atl load' for atl_load etc.
# The invoked thing (e.g. atl_*) may be either a function or an executable.
# Can be symlinked to any prefix; e.g. to $ATL_APPDIR/bin/ej, which then is a frontend for $ATL_APPDIR/bin/ej_*
# This file must not be marked executable, otherwise $ATL_MANAGE/lib/loadfuncs.sh won't source it

frontend_template() {
	cmd="PREFIX_${1:-help}"
	shift
	case "$(type -t "$cmd")" in
	file)
		# atl_foo exists in $PATH, which include both $ATL_APPDIR/bin and $ATL_MANAGE/bin
		# atl_foo is also executable
		#echo >&2 "Executable: $cmd"
		"$cmd" "$@"
		# We need to source our command in the caller's shell
		# E.g. 'atl load <profile' or 'atl upgrade'
		;;
	function)
		#echo >&2 "Function: $cmd"
		"$cmd" "$@"
		;;
	*)
		echo >&2 "$cmd isn't a function or executable"
		# shellcheck disable=SC2050
		if [[ PREFIX = atl ]]; then
			echo >&2 "Usage: PREFIX [list|load|unload|ls|freeze|help]"
		else
			"PREFIX_help"
		fi
		;;
	esac
}

prefix="$(basename "${BASH_SOURCE[0]}")" # Typically 'atl'
# We could just 'eval "atl() { ... }"' but that involves lots of quote escaping. Instead we use 'declare -f' to print the source code above, and tweak it
eval "$(declare -f frontend_template | sed -e "s/^frontend_template ()/$prefix ()/" -e "s/PREFIX/$prefix/g")"
# Export our frontend function so it can be called from subshells, like scripts.
export -f "$prefix"
unset prefix
unset -f frontend_template

# vim: set filetype=sh foldmethod=marker formatoptions+=cro :
