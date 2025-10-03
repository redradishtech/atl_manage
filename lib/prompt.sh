# Function invoked before EVERY bash command, responsible for dynamically setting the prompt to reflect app status (online/offline, prod/staging, broken directories, etc).
# This is the only sane way to set colours and cmd output in a prompt. See
# http://stackoverflow.com/questions/6592077/bash-prompt-and-echoing-colors-inside-a-function
# See atl_set_prompt_command for where this is set.
atl_bash_prompt()
{
	# Capture the real command's exit code. This must always be the first line!
	local exitcode=$?
	# Store result in var since this must be fast. Also, I think it avoids breaking the \[...\]. https://superuser.com/questions/301353/escape-non-printing-characters-in-a-function-for-a-bash-prompt
	# http://rus.har.mn/blog/2010-07-05/subshells/
	_cross_if_last_command_failed()
	{
		# shellcheck disable=SC2181
		if (( exitcode == 0 )); then
			retval=''
		else
			retval=" \[\e[31m\]✘$exitcode "
		fi
	}

	# https://sjl.bitbucket.io/hg-prompt/quickstart/
	_hg_ps1() {
		# Note that if we ever wanted to emit ANSI colour codes, we would need to use \001...\002 codes, not \[...\]. See https://superuser.com/questions/301353/escape-non-printing-characters-in-a-function-for-a-bash-prompt 
		#START=$(date +%s.%N)
		# This stuff is slow. Only do it in the right directory
		[[ ! $PWD =~ $ATL_APPDIR_BASE ]] && return
		[[ $(basename "$PWD") != "$ATL_VER" && ! -L "$PWD" ]] && return	# 'current' and 'previous' are symlinks
		#hg prompt --mq "[{branch}{status}{update}]" 2>/dev/null
		#if [[ $(hg branch --mq 2>/dev/null) = "$ATL_LONGNAME" ]]; then
		# This is a bit faster:
		if [[ -f .hg/patches/.hg/branch ]]; then
			if [[ $(cat .hg/patches/.hg/branch) = "$ATL_LONGNAME-$ATL_VER" ]]; then
				# This is too slow! Anything invoking hg is >100ms
				#if hg qnext -q > /dev/null; then
				if ! grep -q "$(tail -1 .hg/patches/series)" .hg/patches/status; then
					#hg prompt "{ Unapplied: {patches|hide_applied}}" 2>/dev/null
					echo " (unapplied patches) "
				else
					echo " ✓"
				fi
			else
				hg prompt --mq " mq:{branch}{status}{update}" 2>/dev/null
			fi
		fi
		#END=$(date +%s.%N)
		#DIFF=$(echo "$END - $START" | bc)
		#echo -n $DIFF
		#hg prompt "{ on {branch}}{ at {bookmark}}{status}" 2> /dev/null
	}

	# Print the output of backgrounded commands, then delete the temporary file
	# Used in atl_bash_prompt (from lib/profile.sh)
	emit_backgrounded_output()
	{
	(
		flock --nonblock -E 123  -x 200
		local outfile
		outfile="$(cachedir --)/backgrounded_on_profile_load_output"
		if [[ -s "$outfile" ]]; then
			cat "$outfile" || :
			rm -f "$outfile"
		fi
	) 200>"$(cachedir --)/backgrounded_on_profile_load_output.lock" || echo "Emit background failed: exit code $?"
	}


	_cross_if_last_command_failed
	#local t0=$(date +%s%N)    # for profiling - see t1 at the end
	[[ -v ATL_SHORTNAME ]] || return 0   # Don't bother with any profile reloading or customization if we don't have a SHORTNAME
	# Each time the prompt loads, check to see if any of our profile files have changed since last prompt. If so, reload them.
	# To achieve this, '_atl_store_profile_timestamps' sets PROFILE_TIMESTAMPS to a string of all file timestamps appended together:
	_atl_store_profile_timestamps
	# Then we check if PROFILE_TIMESTAMPS differs from PROFILE_TIMESTAMPS_LASTACTIVATED, which was defined the last time a profile was loaded.
	# (note we don't do this check on the first profile load, when PROFILE_TIMESTAMPS_LASTACTIVATED isn't defined)
	if [[ -v PROFILE_TIMESTAMPS_LASTACTIVATED && $PROFILE_TIMESTAMPS != "$PROFILE_TIMESTAMPS_LASTACTIVATED" ]]; then
		if [[ -n $(jobs -s) ]]; then
			warn "Not reloading profiles despite change, because there is a stopped background job"
		else
			#echo "Reloading changed profile ($PROFILE_TIMESTAMPS_LASTACTIVATED != PROFILE_TIMESTAMPS)"
			atl_load "$ATL_FQDN"   # Not ATL_LONGNAME, as that doesn't capture the tenant in multitenant 
			warn "\$ATL_APPDIR/.env may be outdated, so recent profile var changes will not be noticed by cron-driven scripts. Run 'atl_freeze' to update .env"
			PROFILE_TIMESTAMPS_LASTACTIVATED="$PROFILE_TIMESTAMPS"
		fi
	fi
	local cross="$retval"
	# Hack to prevent changing the prompt 9/10 times
	# (( atl_bash_prompt_counter-- )) && return 0 || atl_bash_prompt_counter=10

	# The pattern here is:
	# \[		Prevent follow chars counting towards the line length calculation
	# \e[		ANSI escape code begins (see Wikipedia (https://en.wikipedia.org/wiki/ANSI_escape_code). Note that ESC can also be written as octal 033 as \\033. This ESC [ pattern is known as the Control Sequence Introducer (https://en.wikipedia.org/wiki/ANSI_escape_code#CSI_sequences). The CSI is followed by semicolon-separated parameter bytes, then a final byte. There are control sequences for setting cursor position and other operations. The control sequence we're interested in is 'CSI n m', i.e. Select Graphic Rendition (SGR).
	# 
	# For 'set graphic rendition' SGR control sequences, the parameter bytes for 3/4-bit are, per wikipedia (https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_(Select_Graphic_Rendition)_parameters):
	# 
	# 1			bold
	# 2			Faint (dim)
	# 4			Underline
	# 30-37			foreground colour
	# 40-47			background colour
	# 90-97			bright foreground colour (avoiding having to set bold mode)
	# 100-107		bright background colour (avoiding having to set bold mode)
	#
	#			So for instance 0;91 means non-bold 
	# 
	# The CSI parameter bytes for 24-bit are:
	#
	# 38;2;r;g;b		24-bit terminal for "Select RGB foreground color"
	# 48;2;r;g;b		24-bit terminal for "Select RGB background color"

	# or for 8-bit:		https://en.wikipedia.org/wiki/ANSI_escape_code#8-bit
	#
	# 38;5;n		8-bit terminal for "Select foreground color"		
	# 48;5;n		8-bit terminal for "Select foreground color"
	#
	# 
	# m			CSI n m means Select Graphic Rendition, so we end with 'm'
	# \]		Chars following should start counting to length again

	local yellow='\[\e[0;33m\]'	# yellow
	local red='\[\e[0;91m\]'	# bright red
	local purple='\[\e[1;95m\]'	# bold;bright magenta
	local green='\[\e[1;92m\]'	# bold;bright green
	# http://misc.flogisoft.com/bash/tip_colors_and_formatting
	local dim='\[\e[2m\]'
	local reset='\[\e[0m\]'
	local italic='\[\e[3m\]'
	#LOG "Got ${yellow}yellow${reset}, ${red}red${reset}, ${purple}purple${reset} and ${green}green${reset}"

	local warnings=
	local atlprofile=

	if [[ -v ATL_SHORTNAME ]]
	then
		[[ -v ATL_TENANT ]] && appname="$ATL_SHORTNAME $ATL_TENANT" || appname="$ATL_SHORTNAME"
		if [[ -v ATL_NEWVER && "$ATL_NEWVER" != "$ATL_VER" ]]; then
			local upgradenote=" → $ATL_NEWVER${ATL_NEWVER_HASH++$ATL_NEWVER_HASH}"
		else
			local upgradenote=""
		fi
		if [[ $ATL_PRODUCT_FULL = postgresql ]]; then
			apptype=" db"
		else
			apptype=''
		fi
		if [[ $ATL_ROLE = prod || $ATL_ROLE = 'standby prod' || $ATL_ROLE = standby || $ATL_ROLE = preprd ]]
		then
			# maintenance.sh defines an ATL variable and function used in our PS1 prompt
			# Added --nolog here for when this is sourced from scripts like ~/bin/client
			# shellcheck source=/opt/atl_manage/lib/maintenance.sh
			source "$ATL_MANAGE/lib/maintenance.sh" --nolog --no_profile_needed
			_atl_maintenance_remaining
			if [[ -n $retval ]]; then
				colour="${yellow}${italic}"
				maintenance="[$retval]"
			else
				maintenance=
				colour="$yellow"
			fi
			if [[ $ATL_ROLE = prod ]]; then
				atlprofile="${colour}[${appname}${apptype}${upgradenote}$(_hg_ps1)${cross}]${reset}"
			else
				atlprofile="${colour}[${appname}${apptype} ${ATL_ROLE}${upgradenote}$(_hg_ps1)${cross}]${reset}"
			fi
		elif [[ $ATL_ROLE =~ ^(sandbox|staging|dev|local)$ ]]
		then
			# Pure staging
			#LOG "staging - using ${purple}purple${reset} not ${green}green${reset}"
			atlprofile="${purple}[${appname}${apptype}${upgradenote}$(_hg_ps1)${cross}]${reset}"
		elif [[ $ATL_ROLE =~ staging ]]
		then
			# Staging standby, for example
			atlprofile="${purple}[${appname}${apptype} ${ATL_ROLE}${upgradenote}$(_hg_ps1)${cross}]${reset}"
		else
			# Non-staging but not production?? let's use prod colours
			colour="$green"
			atlprofile="${colour}[${appname}${apptype} ${ATL_ROLE}${upgradenote}$(_hg_ps1)${cross}]${reset}"
		fi
	fi

	if [[ $ATL_PRODUCT != none ]]; then

		local MainPID
		local ActiveState
		local SubState
		local LoadState
		# 'systemctl show' sets the variables for us, e.g.:
		# MainPID=970396
		# LoadState=loaded
		# ActiveState=active
		# SubState=running
		if [[ -v ATL_SYSTEMD_SERVICENAME ]]; then
			eval "$(systemctl show "$ATL_SYSTEMD_SERVICENAME".service --property=LoadState --property=ActiveState --property=SubState --property=MainPID)"
			local running
			[[ "$LoadState" = loaded ]] || warnings+="${red}LoadState=$LoadState${reset} "
			case "$ActiveState $SubState" in
				"active exited")
					# Catches the 'active (exited)' state, which I haven't seen in Java but have with icinga
					running=false
					;;
				"active running")
					if [[ $MainPID = 0 ]]; then
						running=false
					else
						if [[ $EUID != 0 ]] || kill -0 >&1 >/dev/null "$MainPID"; then
							running=true
						else
							warnings+="systemd-reported PID $MainPID is dead?!"
							running=false
						fi
					fi
					;;
				"failed failed") running=false ;;
				"inactive dead") running=false ;;
				*)
					warnings+="${red}unknown state $ActiveState/$SubState${reset} "
					running=false
					;;
			esac

			if [[ $ATL_ROLE = standby || $ATL_ROLE =~ standby ]]; then
				if [[ $running = true ]]; then
					warnings+="${red}(running on standby)${reset}"
				fi
			else
				if [[ $running != true ]]; then
					warnings+="${red}😟 (not running)${reset}"
				fi
			fi
		fi
		if [[ -v ATL_MONITORING ]]; then
			eval "$(systemctl show "$ATL_MONITORING".service --property=ActiveState --property=SubState)"
			if [[ "$ActiveState $SubState" != "active running" ]]; then
				warnings+="🤡 (monitoring $ActiveState $SubState)"
			fi
		fi

		# Find a Java process mentioning $ATL_APPDIR, which will normally end with /current. Since that is a symlink, also match on the APPDIR_BASE + VER
		if [[ $ATL_PRODUCT = postgres ]]; then
			:
		elif [[ $ATL_PRODUCT != fisheye ]]; then
			validate_versioned_directories()
			{
				local datareferent
				local base="$1"
				if [[ -v $base ]]; then

				if [[ -d ${!base} ]]; then
					if [[ -L ${!base}/current ]]; then
						datareferent="$(basename "$(readlink "${!base}/current")")"
						[[ "$datareferent" = "${ATL_VER}" ]] || warnings+="(Warning: $base/current symlink points to \"$datareferent\", not ATL_VER ($ATL_VER) data )"
						[[ -d "${!base}/$ATL_VER" ]] || warnings+="(Warning: $base/ATL_VER (${!base}/$ATL_VER) does not exist )"
					elif [[ -e ${!base}/current ]]; then
						warnings+="(Warning: $base/current (${!base}/current) is not a symlink)"
					else
						warnings+="(Warning: No 'current' symlink within $base (${!base}))"
					fi
					if [[ -L ${!base}/previous ]]; then
						datareferent="$(basename "$(readlink "${!base}/previous")")"
						[[ -d "${!base}/$datareferent" ]] || warnings+="(Warning: $base/previous symlink should point to $base/$datareferent, not $(readlink previous))"
						[[ -L ${!base}/old/$datareferent ]] || warnings+="(Warning: missing $base/old/$datareferent symlink)"
					fi
				else
					warnings+="(Warning: missing base $base (${!base})"
				fi
				fi

			}
			# 'none' role is for when the app isn't actually deployed locally (e.g. on jturner-desktop), and we don't want whining about missing dirs.
			if [[ $ATL_ROLE != none ]]; then
				if $ATL_DATADIR_VERSIONED; then
					validate_versioned_directories ATL_DATADIR_BASE
				fi
				validate_versioned_directories ATL_APPDIR_BASE
			fi
		fi
		if [[ $HOSTNAME = jturner-desktop && $ATL_PRODUCT = jethro ]]; then
			: #atl_check_appdeployment checkperms
		fi

		if [[ -v ATL_MONITORING && $ATL_ROLE = prod ]] && ! atl_maintenance in_maintenance; then
			# Prod servers not in maintenance mode should generally always have monitoring enabled.
			if ! atl_monitoring notifications-enabled 2>/dev/null; then
				warnings+="(no monitoring)"
			fi
		fi

		# When ATL_ZFS is set, atl_upgrade_switchver calls lib/zfs.sh functions to mess with ZFS filesystems, and if buggy, these can be left unmounted. 
		if [[ -v ATL_ZFS ]]; then
			if [[ -v ATL_DATADIR && ! -v ATL_MULTITENANT ]]; then   # ej_unload unsets ATL_DATADIR
				if ! mountpoint -q "$(readlink -f "$ATL_DATADIR")"; then
					warnings+="(zfs datadir not mounted)"
				fi
			fi
		fi
		if [[ -v ATL_NEXTSTEPS ]]; then
			warnings+="(next steps: $ATL_NEXTSTEPS)"
		fi
	fi
	if [[ -v ATL_PROFILE_INCOMPLETE ]]; then warnings+="(profile incomplete)"; fi

	if [[ -v ATL_PROFILE_SHLVL && $ATL_PROFILE_SHLVL != "$SHLVL" ]]; then
		warnings+=" $yellow✍ (editing)${reset}"
	fi

	if [[ $(shopt extglob) =~ off$ ]]; then
		# Breaks sourcing of /usr/share/bash-completion/completions/sudo when a new shell is launched
		warnings+="extglob is off. This will break subshells. Fix with 'shopt -s extglob'"
	fi

	

	#if [[ $(type -t "_atl_bash_prompt_$ATL_PRODUCT") = function ]]; then
	#	"_atl_bash_prompt_$ATL_PRODUCT" "$@"
	#fi

	PS1=
	if [[ -n "$warnings" && ! -v NOWARNINGS ]]; then PS1+="$warnings\n"; fi
	# http://tldp.org/HOWTO/Xterm-Title-3.html
	# Note that the escape sequence 'ESC ]' seems XTerm-specific. It is not the same as ANSI CSI 'ESC ['
	# For profiling
	#local t1=$(date +%s%N)
	#local waittime=$(((t1 - t0)/1000000))
	local TITLEBAR='\[\033]0;'${ATL_LONGNAME}' '${ATL_ROLE}' '${ATL_VER:-}${ATL_NEWVER:+→$ATL_NEWVER}':\w\007\]'
	PS1+="${TITLEBAR}\u@\h.${ATL_DOMAINCODE:-${ATL_ORGANIZATION}} ${dim}\A${maintenance:+ $maintenance}${reset} ${atlprofile}\w ${waittime:+$waittime }\\$ "
	emit_backgrounded_output
}

atl_set_prompt_command()
{
	# Set prompt dynamically based on application state
	if [[ $PROMPT_COMMAND =~ atl_bash_prompt ]]; then
		# This is normal e.g. if we 'atl conf' then later 'atl jira'.
		:
	else
		PROMPT_COMMAND_ORIG="${PROMPT_COMMAND:-}"
		PROMPT_COMMAND="atl_bash_prompt"
		if [[ -n $PROMPT_COMMAND_ORIG ]]; then
			export PROMPT_COMMAND+="; $PROMPT_COMMAND_ORIG"
		fi
		# Can't remember the use-case for this..
		if [[ -v ATL_PROMPT_COMMAND ]]; then
			export PROMPT_COMMAND+="; $ATL_PROMPT_COMMAND"
		fi
	fi
}
export -f atl_set_prompt_command

