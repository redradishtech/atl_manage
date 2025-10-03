# [Plugin]
# Name = Healthchecks
# Description = Notifies https://healthchecks.io of the start and end of the @main-tagged function. For more fine-grained control, tag a function @healthchecks:manual, and in the function call _healthcheck_start / _healthcheck_end.
#
# [Help:Healthchecks]
# URL = Sets the Healthcheck URL, e.g. https://hc-ping.com/<uuid>. See https://healthchecks.io/docs/
# APIKey = Set the Healthchecks.io project API key (visible under Settings), allowing us to register our own endpoint. Note: APIKey may be stored in cross-project ~/.config/multitool/defaultheader.bash
#
# [Healthchecks]
# URL =


_processtags() {
	if [[ -v _tag_healthchecks_manual ]]; then
		echo "Note: function calls start() and healthcheck_end() manually"
	elif [[ -v _tag_main ]]; then
		for mainfunc in ${_tag_main}; do
			# For example, if mainfunc=backup, i.e.:
			# @main
			# backup() { ... }
			#
			# this has the effect of setting tags:
			#
			# @pre:backup
			# _healthcheck_start() { ... }
			# @post:backup
			# _healthcheck_end() { ... }
			#
			# thus indicating _healthcheck_start() is to run before backup(), and  _healthcheck_end() afterwards.
			
			# Set both array and expanded form
			_tags[_healthcheck_start]=" pre:$_tag_main"
			_tags[_healthcheck_end]=" post:$_tag_main"
			tagname="_tag_pre_$mainfunc"
			declare -n tag="$tagname"
			tag+=" _healthcheck_start"
			tagname="_tag_post_$mainfunc"
			declare -n tag="$tagname"
			tag+=" _healthcheck_end"
		done
	else
		__fail "Please tag a function @main if you want something healthchecked, or tag with @healthchecks:manual if your function does it itself"
	fi
}
_processtags

_validate_vars() {
	if [[ -v __url || -v _healthcheck__apikey ]]; then __fail "Please use [Healthchecks], not [Healthcheck]"; fi
	if [[ -n $_healthchecks__url ]]; then
		# This shouldn't fail when only APIKey is set
		: #[[ -n $_healthchecks__url ]] || __fail "_healthchecks__url is blank"
	else
		[[ -v _script__name ]] || __fail "Please define [Script] Name=..., which will be used in the healthchecks.io check"
		[[ -v _timer__oncalendar ]] || __fail "Please define [Timer] OnCalendar=..., which will be used in the healthchecks.io check"
		if [[ -v _healthchecks__apikey ]]; then
			__warn "Please run ./healthcheck_register, then save the URL in the script header in the [Healthchecks] section"
		else
			___fail "Please define [Healthchecks] URL = ... (endpoint ping url). Alternatively, generate an API key in your healthchecks.io project, set it in [Healthchecks] Apikey=... , and call ./healthcheck_register"
		fi
	fi
}
_validate_vars

_healthchecks__curl() {
	curl --user-agent "Curl-on-$HOSTNAME/1" -m 10 --retry 5 "$@"
}

# Call this function in your code to notify healthchecks.io that processing has started.
_healthcheck_start() {
	[[ -v _script__productionhost ]] || fail "If healthchecks.io is to be notified of this run, please define [Script] ProductionHost = $HOSTNAME"
	_isproduction || return 0
	[[ -v _healthchecks__url ]] || { __warn "No [Healthchecks] URL=... set. Not notifying healthchecks.io"; return 0; }
	echo "_healthcheck_start called (args $*, url=$_healthchecks__url)"
	echo "Notifying «${_healthchecks__url}»"
	_healthchecks__curl -fsS -o /dev/null "$_healthchecks__url"/start
}

# Call this function in your code to notify healthchecks.io of success/failure.
_healthcheck_end() {
	_isproduction || return 0
	echo "_healthcheck_end called (args $*, invoked function = $_invokedfunc)"
	_healthchecks__curl -fsS -o /dev/null "$_healthchecks__url${1:+/$1}" 
}


__arr2json() {
	# https://stackoverflow.com/a/73862706/7538322
	declare -n arr="$1"; shift
	jq -n '[$ARGS.positional | _nwise(2) | {(.[0]): .[1]}] | add' --args "${arr[@]@k}"
}

# Registers a healthchecks.io Check for this script. Requires [Healthchecks] APIKey to be set" 
healthcheck_register() {
	if [[ -v _healthchecks__apikey ]]; then

		if [[ -v _tag_main ]]; then
			for mainfunc in ${_tag_main}; do
				if [[ -v _comments[$mainfunc] ]]; then
					declare -n mainfunccomment=_comments[$mainfunc]
				else
					declare -n mainfunccomment=_script__description
					: #__log "$mainfunc has no comment"
				fi
			done
		fi

		declare -A req=(
			[name]="${_script__name}"
			[desc]="${mainfunccomment:-$_script__description}
			Generated on $HOSTNAME by ${_script__abspath}."
			[channels]="*"
			[schedule]="${_timer__oncalendar}"
			[tz]="$(timedatectl show -p Timezone --value)"
		)
		request="$(__arr2json req | jq '. + {unique:["name"]}')"
		response="$(mktemp)"
		headers="$(mktemp)"
		#__log "$request" | jq .
		echo >&2 "Registering healthchecks.io endpoint for ${_script__name} ..."
		local uuid
		uuid="$(__uuid)"
		__apicurl "/${uuid:-}" -o "$response" -w "%{http_code}" --data "$request" > "$headers"
		curlcode=$?
		httpstatus="$(cat "$headers")"
		body="$(cat "$response")"
		rm "$response" "$headers"
		if (( httpstatus == 201 )); then   # Created
			_healthchecks__url="$(echo "$body" | jq  -r .ping_url)"
			echo >&2 "Registered new healthchecks.io endpoint. To avoid constantly re-registering, set:"
			echo >&2 "[Healthchecks] URL = $_healthchecks__url"
		elif (( httpstatus == 200 )); then
				_healthchecks__url="$(echo "$body" | jq  -r .ping_url)"
				echo "Re-synced healthcheck (name, schedule, description etc). URL = $_healthchecks__url"
		else
			echo "Response code: $httpstatus"
			echo "curl exit code: $curlcode"
			echo "Body:"
			echo "$body" | jq .
			__fail "Failed to register/update healthchecks.io endpoint"
		fi
	else
		echo "No [Healthchecks] APIKey set"
	fi
}

__apicurl() {
	slug="$1"; shift
	_healthchecks__curl -s --header "X-Api-Key: $_healthchecks__apikey" https://healthchecks.io/api/v3/checks"$slug" "$@"
}


if [[ -v _healthchecks__apikey ]]; then
healthcheck_status() {
	local uuid
	uuid="$(__uuid)"
	if [[ -n $uuid ]]; then
		echo "Healthchecks.io status:"
		__apicurl "/${uuid:-}" | jq '{name, status, last_ping}'
	fi
}
fi

__uuid() {
	if [[ -v _healthchecks__url && $_healthchecks__url =~ ^https://hc-ping.com/(.+)$ ]]; then
		echo "${BASH_REMATCH[1]}"
	fi
}

