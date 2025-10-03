# shellcheck shell=bash
## Source this from your .bashrc (not .bash_profile) to make 'atl' scripts and functions in $ATL_MANAGE/bin available to your shell.

#eval "$(devbox global shellenv)"
# This script is being sourced, so we can't use $0 to figure out this file's path
[[ -v ATL_MANAGE ]] || { ATL_MANAGE="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"; export ATL_MANAGE; }  # Note, realpath is not present on CentOS 6.4

# We put our stuff in front of PATH so that our 'lnav' gets priority
# venv/bin is for the updated mercurial (installed in bin/atl_setup). Note that it is AFTER /usr/bin so that the default /usr/bin/python is found. If python3 resolves to something non-standard then 'python3 setup.py' in e.g. ~/src/github.com/iovisor/bcc/build/src/python installs eggs to the w  rong directory.
# Because 'activate' is called by non-root, this means venv/** must be readable by all
# Note that ATLMANAGE_PATH is defined separately so it can be used in $ATL_MANAGE/lib/profile.sh#atl_freeze() to define PATH
# The /usr/lib/nagios/plugins path isn't strictly necessary for any ATL_MANAGE scripts (as of Mar/23) but is very useful for cli testing
# FIXME: /usr/local/bin isn't used, but my PATH somehow doesn't contain it after sudo -sE
# The devbox path is for python2.7 for 'atl monitoring'
export ATLMANAGE_PATH="$ATL_MANAGE"/bin:"$ATL_MANAGE"/lib/jeventutils/bin:"$ATL_MANAGE"/monitoring/plugins:"$ATL_MANAGE"/lib/requiresort:"$ATL_MANAGE"/lib/redo/bin:/usr/bin:"$ATL_MANAGE"/venv/bin:/usr/sbin:/sbin:/usr/lib/nagios/plugins:/usr/local/bin:"$ATL_MANAGE"/.devbox/nix/profile/default/bin
export PATH="$ATLMANAGE_PATH":"$PATH"
export ATL_PROFILEDIR="${ATL_PROFILEDIR:-/etc/atlassian_app_profiles}"

if [[ $EUID = 0 ]]; then

	[[ ! -x "$ATL_MANAGE/bin/atl_upgrade.sh" ]] || echo >&2 "bin/atl_upgrade.sh must not be executable or its functions won't be sourced"

	# profile.sh contains 'atl_load', 'atl_list' etc. Perhaps they should be broken into separate bin/atl_*.sh files so loadfuncs.sh works
	#shellcheck source=/opt/atl_manage/lib/profile.sh
	. "$ATL_MANAGE/lib/profile.sh"
	#shellcheck source=/opt/atl_manage/lib/loadfuncs.sh
	. "$ATL_MANAGE/lib/loadfuncs.sh" "$ATL_MANAGE/bin"

	if [[ -v ATL_SHORTNAME ]]; then
		:
		# ATL_SHORTNAME indicates we already have a profile loaded
		#echo >&2 "We are probably in a sub-shell (e.g. 'atl edit')."
		# Source our functions again, which aren't inherited by subshells, but don't mess with existing ATL vars
		# ?? ^^ which functions? do we actually source functions again somehow?
	# Normal users won't have read access to $ATL_PROFILEDIR, but will when running 'sudo -sE'
	elif [[ -v ATL_PROFILE_DEFAULT ]]; then
		:
		echo >&2 "Loading default profile $ATL_PROFILE_DEFAULT"
		atl_load "$ATL_PROFILE_DEFAULT"
	else
		# Load global profile if a profile isn't already loaded (e.g. via 'atl edit')
		#echo "No profile loaded. Loading global"
		echo >&2 "Loading global profile"
		atl_load global
	fi
fi
# vim: set ft=sh:
