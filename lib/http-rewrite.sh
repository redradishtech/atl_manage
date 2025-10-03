#!/bin/bash
# shellcheck shell=bash

# This exports all functions, which is necessary for subshells (e.g. standlone scripts) to be able to invoke e.g. geturlfile
set -a


# curl wrapper that uses the correct cookie store, handles webSudo if encountered, and sets HTTP_STATUS and HTTP_OUTPUT to convey the result.
_curl() {
	if [[ ${1:0:1} != / ]]; then
		fail "First arg to _curl must be the URL component beginning with /, e.g. '/status'. Other args can follow"
	fi
	url="$1"
	shift
	url="$ATL_BASEURL_INTERNAL""$url"
	#shellcheck disable=SC2119
	#shellcheck disable=SC2119
	HTTP_OUTPUT="$(mktemp --tmpdir="$(cachedir)")"   # Permissions should be safe per umask
	local COOKIEJAR="$(cookiejar)"
	HTTP_STATUS=$(curl -sS -k --header "X-Atlassian-Token: no-check" -w "%{http_code}" -o "$HTTP_OUTPUT" -b "$COOKIEJAR" "$url" "$@")
	case "$HTTP_STATUS" in
		2?? | 100)
			# 200 response
			log "All good ($HTTP_STATUS)"
			exitcode=0
			;;
		401)
			# Authentication failed, possibly due to wrong credentials, possibly due to websudo
			if [[ "$(jq -r '.subCode == "upm.websudo.error"' <"$HTTP_OUTPUT")" = true ]]; then
				log "Hit websudo."
				if [[ -z ${ATL_PASSWORD:-} ]]; then
					read -r -s -p "$ATL_BASEURL_INTERNAL Password: " ATL_PASSWORD
				else
					log "Using cached password (ATL_PASSWORD)"
				fi
				rm -f "$HTTP_OUTPUT"
				# Note that websudo re-issues a new session, hence the -c
				if [[ $ATL_PRODUCT = jira ]]; then
					_curl "/secure/admin/WebSudoAuthenticate.jspa"  -D "$tmpheaders" --data-urlencode "webSudoPassword=${ATL_PASSWORD}" --data "&webSudoDestination=/someredirect&webSudoIsPost=false&atl_token=$(upmtoken)"
				elif [[ $ATL_PRODUCT = confluence ]]; then
					_curl /doauthenticate.action -D "$tmpheaders" --data-urlencode "password=${ATL_PASSWORD}" --data '&authenticate=Confirm&destination=/someredirect'
				fi
				# From Apache we get "302" for HTTP1.1, "HTTP/2 302" for HTTP2
				if [[ ! $HTTP_STATUS =~ 302 ]]; then
					error "Assertion failed: we expect a 302 response from the websudo URL regardless of success, yet we got '$HTTP_STATUS'. Headers: $(cat "$tmpheaders")"
				elif ! grep -q "Location: /someredirect" "$tmpheaders"; then
					error "Assertion failed: we got a 302 redirect to an unexpected location. See headers: $(cat "$tmpheaders")"
				fi
				if cat "$tmpheaders" | grep -q "X-Atlassian-WebSudo: Has-Authentication"; then
					log "Hooray, websudo auth worked"
				else
					error "Boo, websudo auth failed requesting $url. Exit code $HTTP_STATUS. Headers: $(cat "$tmpheaders")"
					exit 1
					sleep 1
				fi
			else
				log "Wrong credentials. Nuking cookies"
				rm "$COOKIEJAR"
				unset ATL_USERNAME
				unset ATL_PASSWORD
			fi
			;;
		503)
			exitcode=53
			warn "Service Unavailable (503): $url"
			;;
		400)
			exitcode=40
			warn "Bad request: 400"
			;;
		404)
			exitcode=4
			warn "Not found: 404"
			;;
		50?)
			exitcode=5
			warn "Server error ($exitcode): $url"
			;;
		302)
			# A normal redirect
			exitcode=0
			;;
		*)
			exitcode=1
			log "HTTP Status $HTTP_STATUS"
			;;
	esac
	if [[ -s "$tmpfile" ]]; then
		cat "$tmpfile"
		rm "$tmpfile"
	fi
	return $exitcode
}

cookiejar() {
	if [[ -v ATL_PRODUCT ]]; then
		echo "$(cachedir)/.${ATL_LONGNAME:-}-cookies.txt"
	fi
}

# Succeeds (returns 0) if a HTTP response (code in $1, JSON body in $2) indicates a successful login.
loginsuccessful() {
	local logincode="$1"
	local loginjson="$2"
	if [[ $logincode != 200 ]]; then return $((logincode % 255)); fi
	if [[ $ATL_PRODUCT = jira ]]; then
		# On success JIRA gives us JSON like:
		# {
		#   "self": "https://jira-sandbox.corp.example.com/rest/api/latest/user?username=jturner",
		#   "name": "jturner",
		#   "loginInfo": {
		#     "failedLoginCount": 497,
		#     "loginCount": 636,
		#     "lastFailedLoginTime": "2017-11-24T11:56:35.697+0000",
		#     "previousLoginTime": "2017-11-24T11:53:33.739+0000"
		#   }
		# }
		#
		# Or sometimes:
		# {
		#   "errorMessages": [
		#     "You are not authenticated. Authentication required to perform this operation."
		#   ],
		#   "errors": {}
		# }
		#
		[[ "$(cat "$loginjson" | jq -r '.name')" != "null" ]]
	elif [[ $ATL_PRODUCT = confluence ]]; then
		# Confluence gives us JSON like:
		# {
		#   "type": "known",
		#   "username": "wikiadmin",
		#   "userKey": "2c908c4f4458ad14014458af304a00d8",
		#   "profilePicture": {
		#     "path": "/download/attachments/1114113/wikiadmin-55295-pp-barney.jpg",
		#     "width": 48,
		#     "height": 48,
		#     "isDefault": false
		#   },
		#   "displayName": "Confluence Administrator",
		#   "_links": {
		#     "base": "https://confluence-sandbox.corp.example.com",
		#     "context": "",
		#     "self": "https://confluence-sandbox.corp.example.com/rest/experimental/user?key=2c908c4f4458ad14014458af304a00d8"
		#   }
		# }
		[[ $(cat "$loginjson" | jq -r '.type == "known"') == true ]]
	elif [[ $ATL_PRODUCT = crowd ]]; then
		cat "$loginjson" | jq -e '.next' >/dev/null
	fi
}
# Use curl to log in to the application, storing cookies in $(cookiejar) for further operations via geturlfile()
login() {
	loginjson=$(mktemp)
	trap 'rm -f "$loginjson"' EXIT TERM

	if [[ $ATL_PRODUCT = crowd ]]; then
		trylogin() {
			loginurl="/rest/security/login?next=/success"

			_curl "$loginurl" -H 'Content-Type: application/json' --data-binary $'{"username":"'"${ATL_USERNAME:-}"'","password":"'"${ATL_PASSWORD:-}"'","rememberMe":true}' > "$loginjson"
		}
		setusername() {
			:
		}
	## JIRA and Confluence both have a login URL which, which authenticated via HTTP Basic auth, returns a 200 response.
	else
		if [[ $ATL_PRODUCT = jira ]]; then
			loginurl="/rest/auth/1/session"
			setusername() { ATL_USERNAME="$(cat "$loginjson" | jq -r .name)"; }
		elif [[ $ATL_PRODUCT = confluence ]]; then
			loginurl="/rest/api/user/current"
			setusername() { ATL_USERNAME="$(cat "$loginjson" | jq -r .username)"; }
		else
			error "Don't know how to login to app: $ATL_PRODUCT"
		fi
		trylogin() {
			log "_curl login with $ATL_USERNAME:$ATL_PASSWORD"
			_curl "$loginurl" -u "${ATL_USERNAME:-}:${ATL_PASSWORD:-}" > "$loginjson"
		}
	fi

	#log "Trying to log in through cookies, and then inferring our username from the app..."
	trylogin
	if loginsuccessful "$HTTP_STATUS" "$loginjson"; then
		setusername
		#log "Successful login as '$ATL_USERNAME'"
	fi
	local failcount=0
	fail

	while ! loginsuccessful "$HTTP_STATUS" "$loginjson"; do
		failcount=$((failcount + 1))
		if [[ -z ${ATL_USERNAME:-} ]]; then read -r -p "$ATL_BASEURL_INTERNAL Username: " ATL_USERNAME; else log "$? Using cached username '$ATL_USERNAME' (ATL_USERNAME)"; fi
		if [[ -z ${ATL_PASSWORD:-} ]]; then read -r -s -p "$ATL_BASEURL_INTERNAL Password: " ATL_PASSWORD; else log "Using cached password (ATL_PASSWORD)"; fi
		[[ -n $ATL_USERNAME ]] || {
			log "No username given; aborting"
			return $?
		}
		[[ -n $ATL_PASSWORD ]] || {
			log "No password given; aborting"
			return $?
		}
		trylogin
		if loginsuccessful "$HTTP_STATUS" "$loginjson"; then
			setusername
		elif [[ $HTTP_STATUS -ge 500 ]]; then
			error "Server is down (exit code $HTTP_STATUS)"
		else
			log "Login as '$ATL_USERNAME' failed ($HTTP_STATUS). Trying again.."
			if ((failcount > 1)); then log "Perhaps your login is blocked by a captcha requirement? Or perhaps an upstream Crowd/Jira instance used for auth is down? You might like to try this manually: curl --insecure --header \"X-Atlassian-Token: no-check\" -u \"$ATL_USERNAME:$ATL_PASSWORD\" \"${loginurl}\""; fi
			if ((failcount > 3)); then
				log "Too many failures ($failcount). Exiting"
				return 1
			fi
			unset ATL_USERNAME
			unset ATL_PASSWORD
		fi
	done
}

upmtoken() {
	cat "$(geturlfile '/rest/plugins/1.0/' 0 --headers)" 2>&1 | grep -Po "(?<=upm-token: )(-?[0-9]+)" || error "Unable to extract upm-token from /rest/plugins/1.0/"
}

DEFAULT_LOCAL_CACHETIMEOUT=$((60 * 6))
DEFAULT_REMOTE_CACHETIMEOUT=
# HTTP GET a URL for this app, auto-logging in if necessary. $1 should be the part after the base URL, e.g. '/secure/Dashboard.jspa'
# Return code is 0 if successful, HTTP code % 256 otherwise (bash exit codes are 8-bit)
geturlfile() {

	#[[ $# = 1 ]] && [[ -n "$1" ]] || error "Invalid call to geturlfile: $@"
	# The above check prevented us setting a cache timeout
	
	if [[ -n ${1:-} && $1 =~ [0-9]+ ]]; then
		CACHETIMEOUT=${1:-}
		shift
	fi
	# All further args go straight to curl

	set -o pipefail
	if [[ ${url:0:1} == / ]]; then
		#if [[ -z ${ATL_USERNAME:-} ]]; then read -r -p "$ATL_BASEURL_INTERNAL Username: " ATL_USERNAME; else log "Using cached username '$ATL_USERNAME' (ATL_USERNAME)"; fi
		#if [[ -z ${ATL_PASSWORD:-} ]]; then read -r -s -p "$ATL_BASEURL_INTERNAL Password: " ATL_PASSWORD; else log "Using cached password (ATL_PASSWORD)"; fi
		# https://superuser.com/questions/272265/getting-curl-to-output-http-status-code
		#creates a new file descriptor 3 that redirects to 1 (STDOUT)
		cachefilename="${url//[:\/?#=]/_}"
		if ((${#cachefilename} > 255)); then
			cachefilename="$(echo "$url" | sha1sum | awk '{print $1}')"
		fi
		cachefile="$(cachedir)/$cachefilename"
		if [[ $* =~ --headers ]]; then
			cachefile+=".headers"
		fi
		# Awful hack: $refresh is a global var set in atl_plugins. If this wasn't bash we could pass this through as an arg.
		if [[ ! -v refresh || $refresh = false ]]; then
			CACHETIMEOUT=${CACHETIMEOUT:-$DEFAULT_LOCAL_CACHETIMEOUT}
		else
			CACHETIMEOUT=0
		fi
		tmpfile="$(mktemp -p "$(cachedir)")"
		#warn "Created tmpfile to store $url: $tmpfile"
		tmpheaders="$(mktemp -p "$(cachedir)")"
		#warn "If $cachefile does not exist or is zero bytes, or if we have a cache timeout of ${CACHETIMEOUT} and $cachefile is not younger than it"

		if [[ ! -s $cachefile || (-n ${CACHETIMEOUT:-} && -z $(find $cachefile -mmin -${CACHETIMEOUT})) ]]; then
		else
			# Cache has not expired
			#log "$url: cached in $cachefile ($(ls -la $cachefile))"
			echo "$cachefile"
		fi
		# For some reason trap '...' EXIT doesn't trigger, so we remove our tmpfiles manually
		rm -f "$tmpheaders"
		rm -f "$tmpfile"
		if [[ -n ${exitcode:-} && $exitcode != 0 ]]; then
			error "$url fetch failed with exit code $exitcode"
		fi
	elif [[ ${url:0:4} == http ]]; then
		# For URLs like https://marketplace.atlassian.com/download/plugins/com.midori.confluence.plugin.archiving/version/700200000 we want to return a filename with the correct extension. So we do this in two steps:
		# Request headers (-I), following redirects (-L), silent except for errors (-sS) and print the final location (-w %{url_effective})
		# Request the final location, writing to a filename with the correct extension
		CACHETIMEOUT=${CACHETIMEOUT:-$DEFAULT_REMOTE_CACHETIMEOUT}
		cachefilename="${url//[:\/?#]/_}"
		cachefile="$(cachedir)/$cachefilename"
		cacheheadersfile="$cachefile".headers
		cachestatusfile="$cachefile".status
		if [[ ! -s $cacheheadersfile || ! -s $cachestatusfile || (-n ${CACHETIMEOUT:-} && $(find "$cacheheadersfile" -mmin +${CACHETIMEOUT})) ]]; then
			debug "Refreshing $cachestatusfile"
			curl -LI -sS -k -w "%{http_code}%{url_effective}" -b "$COOKIEJAR" "$url" -o "$cacheheadersfile" >"$cachestatusfile"
		else
			log "Using cached $cachestatusfile"
		fi
		HTTP_STATUS_AND_URL="$(cat "$cachestatusfile")"
		IFS="" read -r HTTP_STATUS HTTP_URL <<<"$HTTP_STATUS_AND_URL"
		if [[ $HTTP_STATUS != 200 && $HTTP_STATUS != 100 ]]; then
			error "HTTP GET failed, response code '$HTTP_STATUS': $url. Response body: $(cat "$cacheheadersfile"). Perhaps cookie data in $COOKIEJAR is stale"
		fi
		cachefilename="${HTTP_URL//[:\/?#]/_}"
		cachefile="$(cachedir)/$cachefilename"
		# Note: I attempted to validate the file size based on Content-Length header, but some plugins don't respond with it and the -L redirects give 0 size Content-Lengths, so it's too confusing
		if [[ ! -s $cachefile || (-n ${CACHETIMEOUT:-} && $(find "$cachefile" -mmin +${CACHETIMEOUT})) ]]; then
			debug "Downloading $HTTP_URL, since the cachefile $cachefile is -mmin +$CACHETIMEOUT"
			# Note that the $* is deliberately unquoted as usually it will be blank, and curl doesn't like a '' arg
			#shellcheck disable=SC2048,SC2086
			HTTP_STATUS="$(curl -L -sS -k -w "%{http_code}" $* -b "$COOKIEJAR" "$HTTP_URL" -o "$cachefile")"
			if [[ $HTTP_STATUS != 200 && $HTTP_STATUS != 100 ]]; then
				error "HTTP GET of final URL $HTTP_URL failed, response code '$HTTP_STATUS': $url. Response body is in '$cachefilename'. This should not normally happen as auth failures happen a step earlier with the header-only query."
			fi
		else
			debug "Using cached copy of $HTTP_URL"
		fi
		(
			cd "$(cachedir)" || return
			simplename="$(basename "$HTTP_URL")"
			ln -f "$cachefilename" "$simplename"
			echo "$PWD/$simplename"
		)
	else
		error "Invalid URL format: $1"
	fi

}

# Get the UPM plugin data as JSON. Cached to avoid excessive slowness
# Globals (set in bin/atl_plugins):
# 	$load	boolean, if true then plugin data is loaded from disk
#	$save	boolean, if true then plugin data is saved to disk
getplugindata() {
	# We make multiple REST queries:
	# The first to /rest/plugins/1.0/ gives us 'local' plugin info, notably whether the plugin is enabled.
	# The second to /rest/plugins/1.0/?installed-marketplace gives us additional plugin info such as license details
	# Finally, for each plugin that can be updated (updateAvailable='true'), we fetch the new version's JSON metadata, and include it as a 'newVersion' node in the plugin JSON

	local datafile="$ATL_PLUGINDATA_JSON"
	#shellcheck disable=SC2154
	if $load; then
		if [[ -f $datafile ]]; then
			cat "$datafile"
			return
		else
			error "No plugin data available for loading at $datafile"
		fi
	fi

	local pcache=$(cachedir)/"${ATL_LONGNAME:-}"-plugins.json
	local p1cache=$(geturlfile "/rest/plugins/1.0/")
	[[ -n $p1cache ]] || error "Failed to get URL /rest/plugins/1.0/"
	local p2cache=$(geturlfile "/rest/plugins/1.0/installed-marketplace?updates=true")
	[[ -n $p2cache ]] || error "URL fetch failed"
	# FIXME: this is an inner join, which will be eliminating plugins not on PAC.
	# Figure out how to use this outer join instead:
	# FIXME: inner join is losing plugins not on PAC
	#log "Now merging json '$p1cache' with json '$p2cache'"
	#	jq -s 'flatten | group_by(.key) | map(reduce .[] as $x ({}; . * $x))' "$pcache" "$details" | sponge "$pcache"
	jq -n --slurpfile file1 "$p1cache" --slurpfile file2 "$p2cache" '
	# https://stackoverflow.com/questions/39830426/join-two-json-files-based-on-common-key-with-jq-utility-or-alternative-way-from/39836412#39836412
	# A relational join is performed on "field".

	def hashJoin(a1; a2; field):
	# hash phase:
	(reduce a1[] as $o ({};  . + { ($o | field): $o } )) as $h1
	| (reduce a2[] as $o ({};  . + { ($o | field): $o } )) as $h2
	# join phase:
	| reduce ($h1|keys[]) as $key
	([]; if $h2|has($key) then . + [ $h1[$key] + $h2[$key] ] else . end) ;

	{"plugins": hashJoin( ($file1|.[].plugins); ($file2|.[].plugins); .key)}' >"$pcache"
	#log "How did that go? $pcache"
	# .userInstalled == true eliminates 'com.springsource.org.jdom-1.0.0', 'system.entity.property.conditions'

	cat "$pcache" | jq -r '.plugins[] 
	| select(.userInstalled == true)
	| select(
	.key | ( startswith("com.atlassian.jira") and ( startswith("com.atlassian.jira.trello") | not ) )
		or startswith("com.atlassian.confluence.plugins.editor")
		or startswith("com.atlassian.confluence.plugins.presentation")
		or startswith("com.atlassian.confluence.plugins.sherpa")
		or startswith("com.atlassian.confluence.plugins.ssl")
		or startswith("com.atlassian.confluence.ext.mailpage")
		or startswith("com.atlassian.upm")
		or startswith("com.atlassian.troubleshooting")
		or startswith("com.atlassian.querydsl")
		or startswith("com.atlassian.jpo")    # Sub-plugin for Portfolio
		or startswith("com.atlassian.teams")  # Sub-plugin for Portfolio
		or startswith("com.atlassian.jwt")
		or startswith("com.atlassian.plugin.timedpromise")
		or startswith("com.atlassian.plugins.atlassian-chaperone")
		or startswith("com.atlassian.plugins.atlassian-client-resource")
		or startswith("com.atlassian.plugins.base-hipchat-integration-plugin")
		or startswith("com.atlassian.plugins.base-hipchat-integration-plugin-api")
		or startswith("com.atlassian.plugins.authentication.atlassian-authentication-plugin")
		or startswith("com.atlassian.pocketknife")
		or startswith("com.atlassian.psmq")
		or startswith("com.atlassian.servicedesk.")
		or startswith("com.atlassian.servicedesk.")
		or startswith("com.atlassian.support.")
		or startswith("com.atlassian.labs.hipchat.confluence-hipchat")
		or startswith("com.adaptavist.plm.plugin.plm-plugin")
		or startswith("tac.")
		or startswith("jira.")
		or startswith("io.atlassian")
		or startswith("whisper.messages")
		or startswith("rome")
		or startswith("org.apache") 
		or startswith("crowd-rest-") 
		or startswith("crowd.system.passwordencoders")
		or startswith("confluence.") or startswith("com.springsource.net.jcip.annotations")
		or startswith("net.customware.plugins.connector.")
		or startswith("net.customware.reporting.reporting-core")
		or startswith("pl.craftware.jira.cp-jira-facade-7")
		or startswith("pl.craftware.jira.cp-jira-commons-plugin")
		or startswith("ch.bitvoodoo.confluence.plugins.registration")
		or startswith("ch.bitvoodoo.confluence.plugins.analytics-core")
		or startswith("ch.bitvoodoo.confluence.plugins.attachment-tracking")
		or startswith("ch.bitvoodoo.atlassian.plugins.bitvoodoo-admin")
		or startswith("ch.bitvoodoo.confluence.plugins.searchtracker")
		or startswith("com.servicerocket.confluence.plugin.servicerocket-utility-library")
		or startswith("com.thed.zephyr.zapi")
		or startswith("com.k15t.js.aui-ng")
		or startswith("com.tempoplugin.tempo-accounts")
		or startswith("com.tempoplugin.tempo-core")
		or startswith("com.tempoplugin.tempo-plan-core")
		or startswith("com.tempoplugin.tempo-platform-api")
		or startswith("com.tempoplugin.tempo-platform-jira")
		or startswith("com.tempoplugin.tempo-teams")
		or startswith("com.k15t.scroll.scroll-exporter-extensions")
		or startswith("com.k15t.scroll.scroll-runtime-confluence")
		or startswith("com.atlassian.migration.agent")
		or startswith("com.atlassian.frontend.atlassian-frontend-runtime-plugin")
		or startswith("com.atlassian.confluence.plugins.confluence-mobile-plugin")
		or startswith("com.decadis.jira.xapps-library")
		or startswith("org.swift.confluence.tablesorter")
		or startswith("org.randombits")
		or startswith("com.atlassian.confluence.plugins.confluence-macro-indexer-plugin")
		or startswith("com.atlassian.confluence.plugins.confluence-copy-page-hierarchy-plugin")
		or startswith("com.atlassian.confluence.plugins.confluence-healthcheck-plugin")
		or startswith("com.atlassian.confluence.plugins.confluence-hipchat-integration-plugin")
		or startswith("com.atlassian.confluence.plugins.confluence-macro-indexer-plugin")
		or startswith("com.atlassian.labs.hipchat.confluence-hipchat")
		or startswith("com.atlassian.support.healthcheck.support-healthcheck-plugin")
		| not
		)
		' | sponge "$pcache"
	# An example of how to assert that a particular plugin is represented:
	#[[ "Tempo Planner" = "$(< "$pcache" jq -r '.plugins[] | select( .key == "com.tempoplugin.tempo-planner").name')" ]] || error "$pcache is bad"

	local details=$(cachedir)/"${ATL_LONGNAME:-}"-plugins.details.json
	: >"$details"
	# Note there is also an 'update-details' link. It contains a superset of 'pac-details' information, but mostly information about the already-installed version, which we're not interested in.
	while IFS=$'\t' read -r key detailsurl <&4; do
		# Like 'update-details', 'pac-details' contains stuff about the currently installed version. We want just the 'update' section, containing info about the upgradable version
		cat "$(geturlfile "$detailsurl")" | jq '{"key": "'"$key"'", "newVersion": .update}' >>"$details"
	done 4< <(cat "${pcache}" | jq -r 'select(.updateAvailable) | .key + "\t" + .links."pac-details"')
	# Don't mess with stdin - we need it later to prompt for passwords. https://stackoverflow.com/questions/19727576/looping-through-lines-in-a-file-in-bash-without-using-stdin
	# https://stackoverflow.com/a/49039053
	jq -s 'flatten | group_by(.key) | map(reduce .[] as $x ({}; . * $x))' "$pcache" "$details" | sponge "$pcache"
	#shellcheck disable=SC2154
	if $save; then
		if [[ -L "$datafile" ]]; then
			warn "Deleting symlink $datafile (probably symlinked to the test instance)"
			rm "$datafile"
		fi
		log "Saving plugin data to $datafile"
		mkdir -p "$(dirname "$datafile")"
		cat "$pcache" >"$datafile"
	fi
	cat "$pcache"
}

getcompatibility() {
	local build="$1"
	if [[ -z $build ]]; then return; fi
	local pcache=$(geturlfile "/rest/plugins/1.0/product-updates/$build/compatibility")
	cat "$pcache"
}

urlencode() {
	pkginstall libany-uri-escape-perl
	perl -MURI::Escape -ne 'chomp;print uri_escape($_),"\n"'
}
