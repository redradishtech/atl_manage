#!/bin/bash -eu
# [Parser]
# Description = Hacky functions to parse a bash script, extracting ini-style variables in the header, identifying functions and their comments.

# Parse file $1's header for #-commented ini-style key-value pairs, stored in $2, an associative array passed in by reference.
__parse_bash_headers() {
	local infile="$1"; shift
	[[ -f $infile ]] || fail "File does not exist: ${infile:-}"
	declare -n vars="$1"; shift

    local section=""
    
    while IFS= read -r line; do
		#__log >&2 "$infile line: $line"
        # Match section headers: "# [Section]"
        if [[ $line =~ ^#\ \[([a-zA-Z0-9_:]+)\] ]]; then
            section="${BASH_REMATCH[1],,}"  # Convert section name to lowercase
			#__log >&2 "# $infile: Matched section: $section"
			local sectionvar="_${section,,}"
			sectionvar="${sectionvar//[^a-zA-Z]/_}"	# Convert e.g. [PluginHelp:Foo] tag to bash-friendly variable name _pluginhelp_foo
			#printf "%-20s %s\n" "$sectionvar" true
			vars[$sectionvar]=true
        # Match key-value pairs: "# Key=Value"
        elif [[ $line =~ ^#\ ([a-zA-Z0-9_]+)\ *=\ *(.*) ]]; then
			local origkey="${BASH_REMATCH[1]}"
			local value="${BASH_REMATCH[2]}"
			value="$(echo "$value" | sed 's/[[:space:]]\+#.*$//')"  # strip any comment. Can't be done with BASH_REMATCH
			#__log "Matched line: $origkey = «$value»"
			#__log >&2 "# Matched kv"
            #local key="${origkey,,}"  # Convert key to lowercase
            local key="${origkey}"     # Preserve original case
			key="${key//[^a-zA-Z]/_}"
            local varname="${sectionvar}__${key}"
				#__log >&2 "$infile: $varname=$value"
			#__log "script.sh: setting $varname"
			#printf "%-20s %s\n" "$varname" "$value"
			vars[$varname]="$value"
		elif [[ $line =~ ^# ]]; then :
		elif [[ $line =~ ^\ *$ ]]; then :
		else
			break
        fi
    done < "$infile"
}

# Given $scriptvars array, and a ${_$plugin} array per plugin, merge their contents into $_vars, giving precedence to $scriptvars
# For example:
# - if given _scriptvars[_service__type]=complex, and _systemd[_service__type]=simple, sets $_vars[_service__type]=complex
# - if given _scriptvars[_service__type]=, and _systemd[_service__type]=simple, sets $_vars[_service__type]=simple
__squish_scriptvars_and_pluginvars_into() 
{
	declare -n vars="$1"
	local k v

	declare -a enabledplugins=($(for p in "${!_plugins[@]}"; do if ${_plugins[$p]}; then echo "$p"; fi; done))
	local pluginkey
	# 'scriptvars' isn't a real pluginkey but $_scriptvars contains the same set of variables as each _$plugin associative array
	for pluginkey in scriptvars "${enabledplugins[@]}"; do
		declare -n pluginvars=_$pluginkey					# Vars only from, in turn, our script.sh and then each plugin
		for k in "${!pluginvars[@]}"; do
			if [[ $k =~ ^_(plugin|help) ]]; then continue; fi		# The [Plugin] and [Help] sections of plugins is metadata that we don't want to declare vars for or expand
				#__log "$pluginkey: Got key $k"
				if [[ ! -v vars[$k] ]]; then				# This means the first occurrence of a var is used. Since script.sh (scriptvars) comes first,this gives script.sh vars precedence, with later plugins setting 'defaults'
				v="${pluginvars[$k]}"
				if [[ ! $k =~ __ ]]; then section=true; else section=false; fi
				# E.g. script.sh [Section] results in a $_section var (indicating the section is activated), but [Section] in a plugin does not. Key=Values are always set, but note the [[ ! -v vars[$k] ]] above - only the first value gets set. This is how script.sh values get precedence, with plugins filling in the gaps.
				if $section && [[ $pluginkey == scriptvars ]] || ! $section; then
					#printf "From %-40s %-40s %-40s\n" "$pluginkey" "$k" "$v"
					vars["$k"]="$v"
				fi
			fi
		done
	done
}

# Unset all ${_$plugin} arrays.
__unset_pluginvars() {
	for plugin in "${!_plugins[@]}"; do
		eval "unset _$pluginkey"
	done
}

# Given the populated $_vars array (e.g. $_vars[_script__Name]), do variable expansion on values, and also set equivalent string env variables ($_script__name).
#
# We will
# 1) Expand $variable references (recursively), unless in single quotes
# 2) Remove "double quote marks" if present
# 3) Map each $_vars key-value to an equivalent string environment var, in original and lowercase form (e.g. $_script__Name and $_script__name)
# 4) declare prefix-free variables of uppercase 'global' variables
#
# For 3), this means we now have two redundant sets of variables: the _keys array (e.g. ${_keys[_script__name]}, and flat string variables (e.g. $_script__name). Plugins should generally use $_script__name vars. However sometimes $_keys is still useful for iterating, both at plugin source time and at runtime. See systemd.bash, where $_keys is used both when sourced and in install()
#
# Also for 3), bash array keys is case-sensitive. We might get given _vars[_unit__Name], or _vars[_unit__NaMe] or any variant. Consumers (plugins) generally don't care, so we create a lowercase version of every variable $_unit__name, which should be the one used normally.
#
# As a rule:
#  - Use $_foo__bar **with LOWERCASE bar** in general, when the variable was set by the user e.g. in [Foo] Bar=.... and you want the case-insensitivity.
#  - Use $_vars for iterating, when you rely on only one $_vars per variable.
#
# For 4) As a special case, Uppercase variables like _vars[_restic__RESTIC_REPOSITORY] are additionally expanded without a prefix, to $RESTIC_REPOSITORY
__expand_vars()
{
	declare -n vars="$1"
	declare -A expandvars
	expandvars=()
	declare -A renameglobals
	local k v

	# This this first loop:
	# - strip double quotes
	# - if single quoted, mark variable for extra expansion later
	# - if all uppercase, mark variable to get a global alias later (e.g. $_restic__RESTIC_PASSWORD -> $RESTIC_PASSWORD)
	# - declare exact case and lowercase environment variables. Declaring both means plugins can reference e.g. $_restic__RESTIC_PASSWORD or $_restic__restic_password, or $_script__Name or $_script__name. Double-declaring vars is a pragmatic alternative to lowercasing all vars, which would be unnatural for e.g. _restic__RESTIC_PASSWORD where uppercase is meaningful.
	for k in "${!vars[@]}"; do
		ksect="${k%__*}"
		kkey="${k#*__}"
		#__log "Considering $k"
		v="${vars[$k]}"
		if [[ $v =~ ^\"(.+)\"$ ]]; then
			#__log "Stripping quotes off $v yielding ${BASH_REMATCH[1]}"
			v="${BASH_REMATCH[1]}"
			vars[$k]="$v"
		fi
		if [[ $v =~ ^\'(.+)\'$ ]]; then
			#__log "Stripping single quotes off $v yielding ${BASH_REMATCH[1]}"
			v="${BASH_REMATCH[1]}"
			vars[$k]="$v"
		else
			# Only expand dollar signs if we weren't in single quotes
			if [[ $v =~ \$ ]]; then
				expandvars[$k]="$v"
			fi
		fi
		if [[ $kkey =~ ^[A-Z_]+$ ]]; then
			renameglobals[$k]="$v"
		fi
		# Note it isn't an error for $v to be blank. E.g. [Timer] OnCalendar= will be blank if the plugin's default is set - which is fine as the plugin has logic to check that
		# -g = global, so they are defined outside this function. -x = exported so they are seen by e.g. envsubst below
		declare -gx "${k}"="${v}"
		# Declare lowercase variant if not already defined by script.sh, e.g. _healthchecks__url set per hostname
		declare -p "${k,,}" &>/dev/null || declare -gx "${k,,}"="${v}"
		# Note that we don't create lowercased versions of vars[$k], i.e. there is no vars[${k,,]=....
	done


	# Given the bulk of variables are declared above, we now use envsubst to expand those whose values contain ${variables}. Do this 4 times to account for nested evaluation.
	count=5
	while (( count-- )) && (( ${#expandvars[@]} )); do
		#__log "$count: We have ${#expandvars[@]} to expand: $(declare -p expandvars)}"
		for k in "${!expandvars[@]}"; do
			ksect="${k%__*}"
			kkey="${k#*__}"
			v="${expandvars[$k]}"
			vnew="$(echo "$v" | envsubst)"
			if [[ ! $vnew =~ \$ ]]; then
				vars[$k]="$vnew"  # so global replacements set below get the expanded version
				[[ -n $v ]] || __fail "$k evaluates to blank. Please set [${ksect:1}] $kkey = ..."
				declare -gx "${k}"="$vnew"
				# Note here we don't do the "if already defined leave alone" check, because as something expanding, of course it was already defined
				declare -gx "${k,,}"="${vnew}"
				unset expandvars[$k]
			else
				expandvars[$k]="$vnew"
			fi
		done
	done
	if (( ${#expandvars[@]} )); then
		__fail "Failed to expand vars: ${expandvars[*]}"
	fi

	for k in "${!renameglobals[@]}"; do
		ksect="${k%__*}"	# e.g. _restic
		[[ ! $ksect =~ ^_help ]] || continue  # Don't expand uppercase vars in [Help:*] sections. E.g [Help:Restic] defines RESTIC_REPOSITORY=... help text, not the value
		kkey="${k#*__}"		# e.g. RESTIC_REPOSITORY
		v="${vars[$k]}"		# value has had variables interpolated above
		#__log "Aliasing $kkey to $k"
		vars[$kkey]="$v"
		declare -gx "$kkey"="$v"     # -g = global, so they are defined outside this function. -x = exported so they are seen by child processes (?which?)
		set +x
	done
}

# Parse text file FILE, assumed to be bash/sh source code, known internally by key PLUGINKEY.
# Populates array FUNCS plus auxiliary info associative arrays FUNCSRC ARGS,
# COMMENTS and TAGS (all keyed by func). Args must all be predefined by the
# caller and passed in by name reference.
# @args FILE PLUGINKEY FUNCS FUNCSRC ARGS COMMENTS TAGS
__parse_bash_extracting_funcs() {
	local infile="$1"	
	local pluginkey="$2"
	declare -p "$3" >/dev/null || fail "Please 'declare -a $2' before passing in its name"
	declare -p "$4" >/dev/null || fail "Please 'declare -A $3' before passing in its name"
	declare -p "$5" >/dev/null || fail "Please 'declare -A $4' before passing in its name"
	declare -p "$6" >/dev/null || fail "Please 'declare -A $5' before passing in its name"
	declare -p "$7" >/dev/null || fail "Please 'declare -A $6' before passing in its name"
	declare -n funcs="$3"
	declare -n funcsrc="$4"
	declare -n args="$5"
	declare -n comments="$6"
	declare -n tags="$7"
	[[ -f $infile ]] || fail "File does not exist: ${infile:-}"
	local tmpcomments=()
	local tmptags=()
	local tmpargs tmpfunc linetags tmptags

	while read -r line; do

		# It would be nice if we could search for any @tag, e.g. 
		# @arg FILE The file to parse
		# But that would mean would return nested associative arrays which bash can't do
		if [[ $line =~ ^#\ *@args[:\ -]*(.+) ]]; then
			tmpargs="${BASH_REMATCH[1]}"
		elif [[ $line =~ ^#\ *(@.*) ]]; then
			# Allow more than one tag per line.
			linetags="${BASH_REMATCH[1]}"
			#__log "Considering possibly multiple tags $linetags"
			# The regex must allow @pre:install and @pre:* tags
			while [[ $linetags =~ @([a-zA-Z0-9_:\!\*]+) ]]; do
				tmptags+=("${BASH_REMATCH[1]}")
				linetags=${linetags#*"${BASH_REMATCH[1]}"}
			done
		elif [[ $line =~ ^#\ *(.+) ]]; then
			tmpcomments+=("${BASH_REMATCH[1]}")
		elif [[ $line =~ ^\ *(function\ +)?([a-z_][\.a-zA-Z0-9_-]+)\ *\(\) ]]; then
			tmpfunc="${BASH_REMATCH[2]}"
			funcsrc["$tmpfunc"]="$pluginkey"
			funcs["$tmpfunc"]=true
			if [[ -v tmpcomments ]]; then
				comments[$tmpfunc]="$(IFS=$'\n'; echo "${tmpcomments[*]}")"
			fi
			if [[ -v tmpargs ]]; then
				args[$tmpfunc]="$tmpargs"
			fi
			if [[ -v tmptags ]]; then
				tags[$tmpfunc]="${tmptags[*]}"
			fi
			# All 'used up' on this function
			unset tmpcomments
			unset tmptags
			unset tmpargs
		else
			# Reset everything when not in a comments-then-function section
			unset tmpcomments
			unset tmptags
			unset tmpargs
		fi
	done < <(cat "$infile")
}

__print_parsed_fields() {
	declare -n funcs="$1"
	declare -n args="$2"
	declare -n comments="$3"
	declare -n tags="$4"

	for f in "${!funcs[@]}"; do
		echo -n "function $f("
		if [[ -v _args[$f] ]]; then
			echo -n "${args[$f]}"
		fi
		echo ")"
		if [[ -v tags[$f] ]]; then echo -e "\t @${tags[$f]// / @}"; fi
		if [[ -v _comments[$f] ]]; then
			echo -e "\t # ${comments[$f]//$'\n'/$'\n'$'\t' # }"
		fi
	done
}

# Note $@ not $* - we pass through -n sometimes
declare -F __fail >/dev/null || __fail() { echo >&2 "$@"; exit 1; }
declare -F __log >/dev/null || __log() { echo >&2 "$@"; }

# If called directly, demonstrate by parsing ourselves
if [[ $(basename "$0") = parser.bash ]]; then
	_script__path="$0"
	declare -rx _script__basename="$(basename "$_script__path")"
	declare -A _scriptvars=()   # Array with config vars from our main script.sh.
	declare -A _funcs			# Function names, as keys mapped to true (enabled) or false
	declare -A _funcsrc			# Map of functions to their defining plugin
	declare -A _args			# Map of functions ot their args
	declare -A _comments		# Map of functions to function comments
	declare -A _tags			# Map of functions to tags (space-separated). E.g. if backup() has @sudo and @execstart tags, we'll have $_tags[backup]="sudo execstart"
	declare -A _vars=()		# Merged config vars set from the script ($_scriptvars) and plugin headers ($_$plugin). This variable can be read and edited by plugins when they are sourced.

	__parse_bash_extracting_funcs "$_script__path" "$_script__basename" _funcs _funcsrc _args _comments _tags	# Inspect script to learn available functions and tags
	__parse_bash_headers "$_script__path" _scriptvars
	printf "%-15s %s\n" File:  "$_script__path"
	printf "%-15s %s\n" Description: "${_scriptvars[_parser__Description]}"
	echo
	__print_parsed_fields _funcs _args _comments _tags

fi
