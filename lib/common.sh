# shellcheck shell=bash

# We rely on extglob in various places, notably lib/profile.sh's timestamp calculation
shopt -s extglob
# Expand **/ where used.
shopt -s globstar
# Don't set pipefail globally (https://mywiki.wooledge.org/BashPitfalls#pipefail). Specifically it breaks events/start-pre/set_banner
#set -o pipefail
# Catch undeclared variables e.g. from .env. Set after a nasty incident where ${ATL_DATALOGDIR} was introduced and used but was undeclared in some instances.  "nounset (set -u) is the least bad of the three options, but has its fair share of gotchas too"
# FIXME: set this one day. For now it causes chaos
#set -u

#https://news.ycombinator.com/item?id=34346346
export TZ=:/etc/localtime

[[ -v ATL_MANAGE ]] || ATL_MANAGE="$(realpath -m "$(dirname "${BASH_SOURCE[0]}")/..")" # Normally set by the caller, but ad-hoc scripts might include common.sh without bothering

# shellcheck source=/opt/atl_manage/lib/logging.sh
. "$ATL_MANAGE/lib/logging.sh"
# shellcheck source=/opt/atl_manage/lib/version.sh
. "$ATL_MANAGE/lib/version.sh"
# shellcheck source=/opt/atl_manage/lib/jeventutils/lib/jeventutils.sh
. "$ATL_MANAGE/lib/jeventutils/lib/jeventutils.sh"

# ATL_TMPDIR overrides TMPDIR, if set. Allows caller to set TMPDIR for scripts by setting ATL_TMPDIR in a profile file. This lets us choose a directory with adequate space for e.g. lib/backup_database to generate huge pg_dumps
# Note that previously we tried to do this with one line:
# export TMPDIR=${ATL_TMPDIR:-${TMPDIR:-}}
# This would leave TMPDIR as blank if ATL_TMPDIR is unset, and blank is not the same as unset. For instance the 'sponge' command would try to write tmpfiles to root if TMPDIR=''
if [[ -v ATL_TMPDIR ]]; then
	export TMPDIR=${ATL_TMPDIR}
fi

umask 027 # A highly restrictive umask - files we create will have flags -rw-r-----. Any script writing a file needs to explicitly make it available to non-root users. NOTE THIS IS A TERRIBLE IDEA. It breaks random other things when sourced in a standard root shell

# Print a directory for locks, application-specific (by default) or global with --global (notably for monitoring.lock and backup.lock)
# FIXME: do we need this? Can't code use ATL_LOCKDIR and ATL_LOCKDIR_GLOBAL? Do we ever rely on the fallback behaviour here?
lockdir() {
	if [[ ${1:-} = --global ]] ||
		[[ ! -v ATL_LOCKDIR ]] || 
		[[ ! -d $ATL_LOCKDIR ]]
		then
			[[ -v ATL_LOCKDIR_GLOBAL ]] ||  { warn "Please define ATL_LOCKDIR_GLOBAL. This should have been sourced from lib/profile.sh"; ATL_LOCKDIR_GLOBAL=/var/lock/atl_manage; }
			[[ -d $ATL_LOCKDIR_GLOBAL ]] || mkdir -p "$ATL_LOCKDIR_GLOBAL"
			echo "$ATL_LOCKDIR_GLOBAL"
		else
			echo "$ATL_LOCKDIR"
	fi
}

tmpdir() { echo "$ATL_TMPDIR"; }

# Print the (existing) cache directory, app-specific by default, or global if passed arg '--global'
# A 'cache' directory contains state that does not need to persist across reboots or app restarts. For more persistent things, use statedir()
cachedir() {
	# Duplicated in setup.bash
	# Note that /run has noexec set - can't execute binaries in it.
	local cachedir_global="${ATL_ROOT:-}"/var/cache/atl_manage
	[[ -d $cachedir_global ]] || mkdir -p "$cachedir_global"
	if [[ ${1:-} = --global ]]; then
		echo "$cachedir_global"
	else
		if [[ ! -v ATL_CACHEDIR ]]; then
			if [[ -v ATL_PRODUCT ]]; then
				# For temporary files like .feature markers and plugin info caches
				# Versioned so that when we upgrade, the cache is implicitly invalidated.
				export ATL_CACHEDIR="$cachedir_global/$ATL_LONGNAME/$ATL_VER"
			else
				export ATL_CACHEDIR="$cachedir_global/"
			fi
			if [[ ! -d $ATL_CACHEDIR ]]; then
				mkdir -p "$ATL_CACHEDIR" # may fail with 'Permission Denied'
			fi
		fi
		echo "$ATL_CACHEDIR"
	fi
}

# Print the (existing) state directory, app-specific by default, or global if passed arg '--global'
# A 'state' directory contains state persistent across reboots, like marker flags indicating whether atl_setup / atl_install_monitoring have been run
statedir() {
	local statedir_global="${ATL_ROOT:-}"/var/lib/atl_manage
	# Make world-readable so $statedir/.in_maintenance can be read by Apache
	if [[ ! -d $statedir_global ]]; then
		mkdir -p -m 755 "$statedir_global"
		chmod 755 "$statedir_global"
	fi
	if [[ ${1:-} = --global ]]; then
		echo "$statedir_global"
	else
		if [[ ! -v ATL_STATEDIR ]]; then
			if [[ -v ATL_PRODUCT ]]; then
				# For temporary files like .feature markers and plugin info states
				# Versioned so that when we upgrade, the state is implicitly invalidated.
				export ATL_STATEDIR="$statedir_global/$ATL_LONGNAME/$ATL_VER"
			else
				error "ATL_PRODUCT unset; can't create ATL_STATEDIR"
			fi
		fi
		if [[ ! -d $ATL_STATEDIR ]]; then
			mkdir -p "$ATL_STATEDIR" # may fail with 'Permission Denied'
		fi
		echo "$ATL_STATEDIR"
	fi
}

# After defining statedir
# shellcheck source=/opt/atl_manage/lib/scriptlastrun.sh
# Broken since migrating from hg to git
#. "$ATL_MANAGE/lib/scriptlastrun.sh"

# When sourcing common.sh, args may be given, which set $@ here but not in the caller
# If we used the usual 'eval set -- $OPTS' getopt technique we would clobber the caller's $@, so instead
# we iterate over $@

c=1
while ((c <= $#)); do
	arg="${!c}"
	case "$arg" in
	--no_profile_needed | --nolog)
		# Whatever the variable is, declare its name=true
		#echo "Declared ${arg#--}=true"
		declare "${arg#--}"=true
		;;
	--required_vars)
		((c++)) || true
		val="${!c}"
		# For some reason our value is quoted. Strip quotes here.
		val=${val#\'}
		val=${val%\'}
		declare required_vars=("$val")
		#echo "Declared $arg=$val"
		;;
	--record_last_run)
		# Record the hg revision ID of this script. This lets setup.bash ensure that the most recent variant of this script has been run.
		# It would be nice if we could do this in an EXIT trap, so it only happens if the script succeeds, but we're already using the trap for other things.
		record_script_run "${BASH_SOURCE[1]}"
		;;

	--)
		shift || break
		break
		;;
	esac
	# 'let' returns exitcode if the result is 0, so increment first
	((++c))
done

if [[ ! -v nolog ]] && [[ ${FUNCNAME[-1]:-} != "source" ]]; then
	# If a script exits halfway due to an error, the user has no way to know that the script wasn't successful. This trap prints a success message.
	# The 'errhandler' function is triggered on the ERR signal in logging.sh. We thus have success and failure conditions covered.
	# TODO: often script A is called by script B. In that case we only want to do this if A is called (the outermost script), not B. E.g. atl_pg_usage_conf_plugin calling atl_plugin_macros
	# Note: 'echo', not 'log', as log() prints a onelinestack which is confusing in this context
	# Note: to stderr, because scripts may pipe stdout to another script
	trap 'if [[ $? = 0 ]]; then echo >&2 "$(basename $0) complete"; else echo >&2 "$(basename $0) failed"; fi' EXIT
fi

#echo "nolog: ${nolog:-}"
#echo "no_profile_needed: ${no_profile_needed:-}"
#echo "required_vars:	${required_vars:-}"

[[ $EUID != 0 ]] && SUDO=sudo || SUDO=""

# Replaces tokens of the form:
# %{FOO}   		replaced with env variable $FOO if FOO is defined.
# %{FOO:-default}	replaced with $FOO if FOO is defined, 'default' otherwise.
#replace_tokens()
#{
#	perl -p -e 's/(%\{([^:}]+)(:-([^}]+))?\})/defined $ENV{$2} ? $ENV{$2} : defined $4 ? $4 : $1/eg'
#}

# Replaces %{...} variables in stdin with ${...} bash variable output. Allows Bash parameter substitution
# Derived from https://stackoverflow.com/questions/2914220/bash-templating-how-to-build-configuration-files-from-templates-with-bash
# See tests in ../test/test.sh
# Backslash escaping of %{..} is not yet allowed.
replace_tokens() {
	local line var fullvar
	# The 'awk 1' hack adds a newline to strings that don't, e.g. atl_plugins --format=report-data which uses 'jq -j', resulting in no newline. Can also be simulated with 'echo -n foo | replace_tokens'
	# https://unix.stackexchange.com/questions/418060/read-a-line-oriented-file-which-may-not-end-with-a-newline
	# TODO: replace this with something in a saner language
	awk 1 | while IFS= read -r line; do
		#log "Read line '$line'"
		# Allow special chars for parameter substitions like ${FOO:-default}, ${FOO/-/_}, ${FOO#stripfromstart}, etc
		# See ../test/test.sh for test cases

		# Match either simple or nested:
		# The first regex matches simple non-nested expressions, '%{ATL_FOO}'.
		# If there are none of those, then the greedy regex matches expressions like '%{ATL_FOO:+Got %{ATL_FOO}}'
		# We couldn't put the greedy regex first or '%{ATL_FOO} %{ATL_FOO}' would match as 'ATL_FOO} %{ATL_FOO'
		# This ordering means that if simple and nested expressions are present on a single line, our loop will first process the simple ones, then the nested.
		while [[ "$line" =~ %\{(ATL_[A-Za-z_0-9:+ \?\/%#-]*)\} || "$line" =~ %\{(ATL_.*)\} ]]; do
			fullvar="${BASH_REMATCH[0]}" # E.g. '%{ATL_VER}'
			var="${BASH_REMATCH[1]}"     # e.g. 'ATL_VER'

			#log "Matched var $var"
			# Note: if we had:
			# var=bob
			# we want to evaluate the expression:
			# echo ${var/\}/\\\}
			# so that:
			# var='bob}'
			# evaluates to 'bob\}'
			#local varval="$(set -vx; eval echo \${${var/\}/\\\}}})"
			#if [ -z ${var+x} ]; then echo "$var is unset"; else echo "$var is set"; fi
			# TODO: This gives a non-fatal error of 'unbound variable' on lines like %{ATL_SSLCERTCHAINFILE:+SSLCertificateChainFile %{ATL_SSLCERTCHAINFILE}}"
			# We previously had:
			#local result="$(eval echo \${${var/\}/\\\}}})"
			# but that didn't preserve newlines in %{ATL_SSLCERT} variable in letsencrypt-dns01-cloudflare patch
			# This wasn't previously allowed because "our templating language would need a way to iterate over results, and the madness goes too far" ???
			local result
			if [[ $var =~ (.+)\ \?(.*?):(.*) ]]; then
				# If We matched something like %{ATL_NOEMAIL::?yes:no} then
				local cond="${BASH_REMATCH[1]}"
				local iftrue="${BASH_REMATCH[2]}"
				local iffalse="${BASH_REMATCH[3]}"
				if [[ -v "$cond" ]]; then
					result="$iftrue"
				else
					result="$iffalse"
				fi
				exitcode=0
			else
				var="${var/\}/\\\}}"
				var="${var//$/\\$}"
				result="$(eval "echo \"\${${var}}\"")"
				exitcode=$?
			fi
			#[[ -n $result ]] || error "No substitution for ${BASH_REMATCH[0]} on line: $line"
			if ((exitcode != 0)); then error "Undefined variable: ${fullvar}"; fi
			if ! [[ ${var:0:4} = ATL_ ]]; then
				warn "Replacing non-ATL variable ${BASH_REMATCH[0]}"
			fi
			#log "\${${var}} evaluated to: $result"
			#log "Token-replaced result: $(replace_tokens $result)"
			#log "Found match ${BASH_REMATCH[0]}. Parsed as $var -> $result"
			#log "old line: '$line'. Now replacing ${BASH_REMATCH[0]} with $result"
			# Replace '\' with '\\' so that backslashes e.g. in '%{ATL_MULTITENANT:+\$pool}' are matched
			line="${line//${fullvar//\\/\\\\}/$result}"
			#log "new line: '$line'"
		done
		echo "$line"
	done
}

# Wait for the current app's process to die. This can be called immediately after atl_stop to block until the app is really down, e.g. in atl_upgrade
wait_for_stop() {
	local count
	((count = 60))
	while ((count > 0)); do
		#shellcheck disable=SC2153
		if pgrep --full "java .+$ATL_APPDIR" >/dev/null; then
			log "Waiting for $ATL_SHORTNAME to stop ($count).."
			count=$((count - 1))
			sleep 1
		else
			log "$ATL_SHORTNAME is stopped"
			break
		fi
	done

}

###########################
# atl_log and atl_vimlog need the logfile location
get_rawlogfiles() {
	case "$ATL_PRODUCT" in
	jira)
		# Note: we use the non-symlink version because lsof returns the non-symlink version too, and we want to avoid duplicates
		atl_logfile="${ATL_DATALOGDIR?}/atlassian-jira.log"
		atl_rawlogfiles=("$atl_logfile" $(lsof +D "${ATL_DATALOGDIR?}/" -u "$ATL_USER" -a -Fn | grep ^n | cut -c2-))
		;;
	confluence)
		#atl_rawlogfiles=("${ATL_DATALOGDIR?}/atlassian-synchrony.log");;
		#atl_rawlogfiles=("${ATL_DATALOGDIR?}/atlassian-confluence.log" "${ATL_DATALOGDIR?}/atlassian-synchrony.log");;
		atl_logfile="${ATL_DATALOGDIR?}/atlassian-confluence.log"
		atl_rawlogfiles=("$atl_logfile" $(lsof +D "${ATL_DATALOGDIR?}/" -u "$ATL_USER" -a -Fn | grep ^n | cut -c2-))
		;;
	crowd)
		atl_logfile="${ATL_DATALOGDIR?}/atlassian-crowd.log"
		atl_rawlogfiles=("$atl_logfile" $(lsof +D "${ATL_DATALOGDIR?}/" -u "$ATL_USER" -a -Fn | grep ^n | cut -c2-))
		;;
	none)
		:
		;;
	*) warn "Don't know where to find logs for $ATL_PRODUCT" ;;
	esac

	# Find all actually-in-use logfiles. In the lsof command:
	# -u means 'find owned by this user'
	# -D means 'find in this directory'
	# -A means 'logical AND the conditions together'
	# -Fn means 'print only the filename (and pid) prepended by n'
	atl_rawlogfiles+=($(lsof +D "$ATL_APPDIR/${ATL_TOMCAT_SUBDIR}logs" -u "$ATL_USER" -a -Fn | grep ^n | cut -c2-))

	# Finding actually-in-use logfiles is great, but sometimes we run atl_log after the process has stopped. Hardcode catalina.out for that (our systemd script redirects stdout/err here)
	if [[ -n ${ATL_APPDIR-} && -f "$ATL_LOGDIR"/catalina.out ]]; then
		# If using systemd, catalina.out should contain nothing but stdout/stderr from the app
		atl_rawlogfiles+=("$ATL_APPDIR/${ATL_TOMCAT_SUBDIR}logs/catalina.out")
	fi

	# Eliminate duplicates. https://stackoverflow.com/questions/13648410/how-can-i-get-unique-values-from-an-array-in-bash
	atl_rawlogfiles=($(echo "${atl_rawlogfiles[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
	#log "We have RAW logfiles: \n$(echo ${atl_rawlogfiles[*]:-} | tr ' ' '\n')"

}
###########################

parse_jiraconfig() {
	local conf="$1"
	cat "$conf" | grep -q jdbc-datasource || error "No '<jdbc-datasource>' node found in $conf"
	jdbcpath=$(cat $conf | grep '^\s*<url>jdbc:postgresql.*</url>\s*$' | sed -e 's,.*<url>jdbc:postgresql://\(.*\)</url>,\1,')
	hostport=$(echo "$jdbcpath" | awk -F'/' '{print $1}')
	export PGHOST=$(echo "$hostport" | awk -F':' '{print $1}')
	export PGPORT=$(echo "$hostport" | awk -F':' '{print $2}')
	export PGDATABASE=$(echo "$jdbcpath" | awk -F'/' '{print $2}')
	export PGUSER=$(cat "$conf" | grep '^\s*<username>.*</username>\s*$' | sed -e 's,.*<username>\(.*\)</username>.*,\1,')
	export PGPASSWORD=$(cat "$conf" | grep '^\s*<password>.*</password>\s*$' | sed -e 's,.*<password>\(.*\)</password>.*,\1,')
}

#get_from_serverxml()
#{
#	# If no datasource was named, use .* to match any and hope for the best
#	local dsname="${1:-.*}"
#		conf=$ATL_APPDIR/${ATL_TOMCAT_SUBDIR}conf/server.xml
#		jdbcpath=$(cat "$conf" | awk "/<Resource name=\"${dsname/\//.}\" .*type=.javax.sql.DataSource./ { s=1 }; /\/>/ {s=0}  s==1 { print; }" | grep "jdbc:postgresql" | sed -e 's,url=.jdbc:postgresql://\(.*\)"\s*$,\1,')
#		hostport=$(echo "$jdbcpath" | awk -F'/' '{print $1}')
#		export PGHOST=$(echo "$hostport" | awk -F':' '{print $1}')
#		export PGPORT=$(echo "$hostport" | awk -F':' '{print $2}')
#		export PGDATABASE=$(echo "$jdbcpath" | awk -F'/' '{print $2}')
#		export PGUSER=$(cat "$conf" | awk "/<Resource name=\"${dsname/\//.}\" .*type=.javax.sql.DataSource./ { s=1 }; /\/>/ {s=0}  s==1 { print; }" | grep "username=" | sed -e 's,.*username="\(.*\)"\s*$,\1,')
#		export PGPASSWORD=$(cat "$conf" | awk "/<Resource name=\"${dsname/\//.}\" .*type=.javax.sql.DataSource./ { s=1 }; /\/>/ {s=0}  s==1 { print; }" | grep "password=" | sed -e 's,.*password="\(.*\)"\s*$,\1,')
#}

#parents() {
#        local ourbranch="$1"
#        #local nextbranches="first(sort(parents(branch($ourbranch)) and not(branch($ourbranch)), -date))"
#        # Find the first 'merge' rev on our branch, and return the foreign parent
#        local nextbranches="p2(first(sort(branch($ourbranch) and merge(), -date))) and !(branch($ourbranch))"
#        local parentbranch
#	parentbranch=$(hg -q log -r "$nextbranches" --template "{branch}\n")
#        log "Found $parentbranch → $ourbranch"
#        if [[ $ourbranch = "$parentbranch" ]]; then
#                error "Oops. In $PWD, hg log -r \"$nextbranches\" gave us a rev on our branch, $ourbranch. We were hoping to see the other branch. apparently p2() doesn't work"; return 1
#        fi
#        if [[ -n $parentbranch ]]; then
#                parents "$parentbranch"
#                echo "$parentbranch $ourbranch"
#        fi
#}

require_profile() { [[ -v ATL_SHORTNAME ]] || error "No app profile selected. Use 'atl profile load' to pick one: \n$(atl_profile list)"; }

# uninstall packages. Pass -P as the first option to purge
pkguninstall() {
	if [[ $1 = -P ]]; then
		local dpkgflag='-P'
		shift
	else local dpkgflag='-r'; fi
	for pkg in "$@"; do
		if dpkg -s "$pkg" &>/dev/null; then
			log "Uninstalling $pkg"
			dpkg $dpkgflag "$pkg"
		else
			log "$pkg already uninstalled"
		fi
	done
}

pkginstall() {
	local aptpkgs=()
	for pkg in "$@"; do
		if [[ "$pkg" = tarsnapper ]]; then
			(
				set +eu
				#shellcheck source=/opt/atl_manage/venv/bin/activate
				source "$ATL_MANAGE"/venv/bin/activate
				pip3 --quiet install tarsnapper
			)
			continue # On to next package
		fi
		# We used to use 'dpkg -s $pkg' for this, but that incorrectly considered uninstalled (rc) packages as installed
		# Note the annoying trailing whitespace
		if pkginstalled "$pkg"; then
			debug "Already installed: $pkg"
			continue # On to next package
		fi
		if [[ "$pkg" = tarsnap ]]; then
			# Configure tarsnap repo
			if [[ ! -f /etc/apt/sources.list.d/tarsnap.list ]]; then
				cd /tmp || :
				curl -OJ https://pkg.tarsnap.com/tarsnap-deb-packaging-key.asc
				$SUDO apt-key add tarsnap-deb-packaging-key.asc
				[ -f /etc/apt/sources.list.d/tarsnap.list ] || echo "deb http://pkg.tarsnap.com/deb/$(lsb_release -s -c) ./" >>/etc/apt/sources.list.d/tarsnap.list
				$SUDO apt update
			fi
		fi
		if [[ "$pkg" =~ adoptopenjdk-.*-hotspot ]]; then
			wget -qO - https://adoptopenjdk.jfrog.io/adoptopenjdk/api/gpg/key/public | $SUDO apt-key add -
			$SUDO add-apt-repository --yes https://adoptopenjdk.jfrog.io/adoptopenjdk/deb/
			$SUDO apt update
		fi
		aptpkgs+=("$pkg")
	done

	if ((${#aptpkgs[@]})); then
		if [[ ${ATL_ROLE:-} = prod ]]; then
			# On production servers, run interactive
			$SUDO apt install "${aptpkgs[@]}"
		else
			DEBIAN_FRONTEND=noninteractive sudo apt-get install -y "${aptpkgs[@]}" || {
				echo >&2 "Failed to install packages: ${aptpkgs[*]}"
				return 1
			}
		fi
	fi
}

pkginstalled() {
	[[ $(dpkg-query -Wf'${db:Status-abbrev}' "$1" 2>/dev/null) == ii\  ]]
}

# Ensures that a user (e.g. 'nagios') can read all files in a subdirectory
validate_user_can_read_all() {
	local user="$1"
	local dir="$2"
	# Ascend up our directory hierarchy testing for readability.
	# Stop as soon as we *can* read a directory; then print an error saying we couldn't read $child (n-1'th)
	while ! sudo -u "$user" test -r "$dir"; do
		local child="$dir"
		dir="$(dirname "$dir")"
	done
	if [[ -v child ]]; then
		error "User '$user' cannot read $child"
	fi
	local out
	# Ignore hidden directories like .git and .redo, which we might like to be root-only
	out="$(
		set -o pipefail
		cd /tmp || exit 1
		sudo -u "$user" find "$dir" ! -readable -not -path '*/.*'
	)"
	[[ -z $out ]] || error " $user cannot read a file: $out . You may need to create an $ATL_APPDIR/.hgpatchscript/$(cd "$ATL_APPDIR" && hg -q qtop) script that runs 'setfacl -R -m u:$user:rX $dir'"
}

# Installs a /etc/sudoers.d/$ATL_SHORTNAME-* snippet, with the given contents.
sudosnippet() {
	local subname="$1"
	shift
	local contents="$1"
	shift
	sudofile="/etc/sudoers.d/${ATL_SHORTNAME}-$subname"
	tmpfile="/tmp/sudoers-${ATL_SHORTNAME}-$subname"
	visudo -qc || error "sudo was broken before we did anything"
	echo -e "$contents" >"$tmpfile"
	chown root: "$tmpfile"
	chmod 0440 "$tmpfile"
	if visudo -qc -f "$tmpfile"; then
		mv "$tmpfile" "$sudofile"
	else
		echo >&2 "Inexplicably broken sudo snippet: $tmpfile"
		exit 1
	fi
	visudo -qc || error "Oops, we somehow broke sudo despite snippet file $sudofile being okay before"
}

mktemp() {
	local scriptpath scriptname lineno tempfile
	scriptpath="${BASH_SOURCE[1]}"
	scriptname="$(basename "$scriptpath")"
	lineno=${BASH_LINENO[0]}
	tempfile="$(/bin/mktemp "$@" --suffix=".${scriptname}_${lineno}")"
	echo "$tempfile"
}

# Use this instead of 'ln -sf a b' as that results in symlinks inside symlinks. https://unix.stackexchange.com/questions/267566/how-to-prevent-symlink-from-creating-within-itself
symlink() {
	if [[ -L $2 ]]; then rm "$2"; fi
	ln -s "$1" "$2"
}

# Some sudo snippets are system-wide, not for any particular app. See atl_install_monitoring which uses this to allow nagios to run the postfix mailqueue check
sudosnippet_systemwide() {
	ATL_SHORTNAME=atlassianservices sudosnippet "$@"
}

installjq() {

	if [[ $(command -v jq) != $ATL_MANAGE/bin/jq ]] && [[ ! -x $ATL_MANAGE/bin/jq ]]; then
		log "Installing the required version of 'jq' locally"
		curl -L -o "$ATL_MANAGE"/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
		chmod +x "$ATL_MANAGE"/bin/jq
	fi
}

# Remove the contents of a directory, including dotfiles.
rm_dir_contents() {
	[[ -d "$1" ]] || fail "Expected directory «$1» does not exist"
	# https://unix.stackexchange.com/questions/77127/rm-rf-all-files-and-all-hidden-files-without-error
	rm -rf "${1:?}"/{..?*,.[!.]*,*}
}

# Atlassian apps store passwords encrypted with a key on the filesystem. This applied to Crowd passwords (cwd_directory_attributes) - atl_check_userdirectories) and LDAP (atl_ldap_users / atl_ldap_groups)
# {"keyFilePath":"javax.crypto.spec.SecretKeySpec_1747048575167","serializedSealedObject":"rO0ABXNyABlqYXZheC5jcnlwdG8uU2VhbGVkT2JqZWN0PjY9psO3VHACAARbAA1lbmNvZGVkUGFyYW1zdAACW0JbABBlbmNyeXB0ZWRDb250ZW50cQB+AAFMAAlwYXJhbXNBbGd0ABJMamF2YS9sYW5nL1N0cmluZztMAAdzZWFsQWxncQB+AAJ4cHVyAAJbQqzzF/gGCFTgAgAAeHAAAAASBBD4QGE9wTgx4fvo+kGntn2idXEAfgAEAAAAMEBbIuvDs3EQ6dZuVBqDOrR9/l5XNeS1+F5hzBiMJh58RSOfq41VqqFFVNc5PKBbxnQAA0FFU3QAFEFFUy9DQkMvUEtDUzVQYWRkaW5n"}
decode_password() {
	if [[ $1 =~ .*\{AES_CBC_PKCS5Padding\}(\{[^\}]+}) ]]; then
		json="${BASH_REMATCH[1]}"
		json="${json/KEY_DIR/$ATL_DATADIR/keys}"
		#warn "Got JSON $json"
		decrypted="$("$ATL_MANAGE/lib/ciphertool/atl_ciphertool" -m decrypt -p "$json" --silent | grep -v DEBUG)"
		if [[ $decrypted =~ (.*)\|SALT- ]]; then
			password="${BASH_REMATCH[1]}"
			#shellcheck disable=SC2001
			echo "$1" | sed -e 's/{AES_CBC_PKCS5Padding}{[^}]\+}/'"$password"/
		else
			error "Unexpectedly unsalty password: $decrypted"
		fi
	else
		echo "$1"
	fi
}

# lsof, but excluding any nonstandard filesystems
_lsof() {
	local x=()
	# https://unix.stackexchange.com/questions/171519/lsof-warning-cant-stat-fuse-gvfsd-fuse-file-system
	for a in $(mount | cut -d' ' -f3); do 
		test -e "$a" 2>/dev/null || x+=("-e$a")
	done
	
	# lsof returns non-zero when seemingly successful. This is annoying, so swallow the exit code
	lsof "${x[@]}" "$@" || :
}

# "Files must conform to the same naming convention as used by run-parts(8): they must consist solely of upper- and lower-case letters, digits, underscores, and hyphens. " - https://bugs.launchpad.net/ubuntu/+source/cron/+bug/706565
cronfriendlyname() {
	sed -e 's/[^a-zA-Z0-9_-]/_/g'
}

#http://stackoverflow.com/questions/1715137/the-best-way-to-ensure-only-1-copy-of-bash-script-is-running

## Copyright (C) 2009  Przemyslaw Pawelczyk <przemoc@gmail.com>
## License: GNU General Public License v2, v3
#
# Lockable script boilerplate

### HEADER ###

# Note: this lets the caller assign a more specific lockfile, in case sub-script granularity is required (e.g. atl_psql)
LOCKFILE=${LOCKFILE:-"${ATL_LOCKDIR:-/var/lock}/$(basename -- "$0")"}
LOCKFD=${LOCKFD:-98}

# PRIVATE
_no_more_locking() {
	_lock u
	_lock xn && rm -f "$LOCKFILE"
}
_prepare_locking() {
	eval "exec $LOCKFD>\"$LOCKFILE\""
	trap _no_more_locking EXIT
}
_lock() {
	_prepare_locking
	flock -"$1" "$LOCKFD"
}

# PUBLIC
exlock_now() { _lock xn; } # obtain an exclusive lock immediately or fail
exlock() { _lock x; }      # obtain an exclusive lock
shlock() { _lock s; }      # obtain a shared lock
unlock() { _lock u; }      # drop a lock

### BEGIN OF SCRIPT ###

# Simplest example is avoiding running multiple instances of script.
#exlock_now || exit 1

# Remember! Lock file is removed when one of the scripts exits and it is
#           the only script holding the lock or lock is not acquired at all.

if [[ -n ${ATL_PROFILEDIR:-} && -f ${ATL_PROFILEDIR:-}/'*' ]]; then
	fail "No longer supporting '*' file: ${ATL_PROFILEDIR}/*"
fi

if [[ -v required_vars ]]; then
	for v in "${required_vars[@]}"; do
		#echo "Considering reqvar: $v"
		if [[ ! -v $v ]]; then
			error "Required var not provided: $v"
		fi
	done
fi

# https://stackoverflow.com/questions/3685970/check-if-a-bash-array-contains-a-value
containsElement() {
	local e match="$1"
	shift
	for e; do [[ "$e" == "$match" ]] && return 0; done
	return 1
}

#command_not_found_handle() {
#	if [[ $1 =~ ^ATL_ ]] && [[ -v $1 ]]; then
#		echo "${!1}"
#	else
#		printf "%s: command not found\n" "$1" >&2
#		return 127
#	fi
#}
# vim: set ft=sh:
