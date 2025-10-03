#!/bin/bash -eu
# [Script]
# Name = multitool_test
# Description = multitool unit tests
# ProductionHost = jturner-desktop
# [Unit]

# my amazing function
# @main
# @execstart
myfunc() {
	[[ -v _sudofunc_called ]] || _fail "sudofunc was tagged pre:myfunc, but here we are in myfunc, and sudofunc was never called"
	[[ $EUID = 0 ]] || _fail "Ought to be running under root, because our pre-function 'sudofunc' is marked @sudo, and multitool isn't currently smart enough to 'drop' sudo when it is no longer needed."
	[[ -v _vars[_script__Name] && ${_vars[_script__Name]} = multitool_test ]] || _fail "There should be the original uppercased form of our var: $(declare -p _vars)"
	[[ ! -v _vars[_script__name] ]] || _fail "We do not actually created a lowercased version of the _vars, only in the flat string variables"
	[[ $_script__name = multitool_test ]] || _fail "There should be a lowercased variant of our string expanded var"
	[[ $_script__Name = multitool_test ]] || _fail "There should be the original uppercased form of our Name variable"
	[[ $_script__description = "multitool unit tests" ]] || _fail
	[[ -v _vars[_script__Name] && ${_vars[_script__Name]} == multitool_test ]] || _fail dsf
	[[ -v _tags[myfunc] && ${_tags[myfunc]} =~ main ]] || _fail "__parse_bash_extracting_funcs should have populated _tags with function-to-space-separated-tags: $(declare -p _tags)"
	[[ -v _tag_main && $_tag_main = myfunc ]] || _fail "__expand_tags should have created _tag_main=myfunc. ${!_tag_@}"
	[[ ${_function__comment} = "my amazing function" ]] || _fail "_function__comment is broken"
	[[ $_function__tags =~ ^(main execstart|execstart main)$ ]] || _fail "Wrong tags: «$_function_tags»"
	echo "Success!"
}

# @pre:myfunc
# @sudo
sudofunc() {
	[[ $EUID = 0 ]] || _fail "Should have been run under sudo (EUID = $EUID)"
	_sudofunc_called=1
}

# @sudo
moresudo() {
	[[ $EUID = 0 ]] || _fail "Should have been run under sudo (EUID = $EUID)"
}


_fail() {
	echo >&2 "Failure on line ${BASH_LINENO[0]}${*:+: $*}"
	exit 1
}

. "$(dirname "$(realpath "${BASH_SOURCE[0]}")")"/../../multitool.bash
