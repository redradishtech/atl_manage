# shellcheck shell=bash

# We use SemVer, and more specifically [git-semver](https://github.com/mdomke/git-semver) as our version format.
# E.g.
# 	8.0.1			 (Jira)
# 	v2.32.1-dev.20+f3b95bf4	(Git revision f3b95bf4)
#
# SemVer is a format that:
# - Lets us identify the product version (duh) - e.g. '8.0.1' for Jira
# - Is sortable/orderable, and usable with 'dpkg --compare-versions' and 'systemd-analyze compare-versions'
# - Lets us identify particular git commits, while retaining order
# - Doesn't contain colons, which break rsync (e.g. 'rsync foo git:12345' breaks thinking 'git' is a hostname) and hg branches (no colons allowed)

# Return true if $1 is less than $2. Useful e.g. if a patch needs to be applied to Jira below version 7.13.5
# There are some tests in lib/test.sh
# This used to be implemented in hideous shell before I discovered dpkg --compare-versions. It should be compatible with 'systemd-analyze compare-versions' in future too.
version_lessthan() { dpkg --compare-versions "$1" lt "$2"; }
version_equal() { dpkg --compare-versions "${1//\.0/}" eq "${2//\.0/}"; } # Note, we want 2.3 == 2.3.0 so we don't just compare directly
version_greaterthan() { dpkg --compare-versions "$1" gt "$2"; }
version_greaterequalthan() { dpkg --compare-versions "$1" ge "$2"; }
version_lessequalthan() { dpkg --compare-versions "$1" le "$2"; }

is_valid_version_pattern() {
	# https://gist.github.com/rverst/1f0b97da3cbeb7d93f4986df6e8e5695
	[[ $1 =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$ ]]
}

# Used in Jethro $ATL_APPDIR/jethro_upgrade_database
version_array() {
	#shellcheck disable=SC2034
	local ver="$1"
	declare -n arr=$2
	if [[ $ver =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$ ]]; then
		#shellcheck disable=SC2206
		#shellcheck disable=SC2034
		arr=(${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]})
	fi
}

# Note: Use version_array() instead.
version_hash() {
	if [[ $1 =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$ ]]; then
		echo "${BASH_REMATCH[1]}"
		echo "${BASH_REMATCH[2]}"
		echo "${BASH_REMATCH[3]}"
		echo "${BASH_REMATCH[4]}"
		echo "${BASH_REMATCH[5]}"
		echo "${BASH_REMATCH[6]}"
		echo "${BASH_REMATCH[7]}"
		echo "${BASH_REMATCH[8]}"
		echo >&2 "Deprecated: use version_array() instead"
	fi
}
