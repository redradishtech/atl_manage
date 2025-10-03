#!/bin/bash

# Prints space-separated list of every ATL_ and JLO* variable we define, except those with passwords ('sensitive')
# Duplicated from lib/profile.sh because we don't want to pull that in as a dependency
_atl_vars_nonsensitive() {
	compgen -v | grep -E '^(ATL_[A-Z0-9_]+|JLOGDIR|JLOCKDIR)' | grep -vE "^${ATL_SENSITIVE_VARS:-thiswillneverexist}$" | tr '\n' ' '
}

declare -p $(_atl_vars_nonsensitive) | sed -e 's/^declare -x /export /g'
