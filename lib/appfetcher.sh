# shellcheck shell=bash source=/opt/atl_manage/lib/appfetcher/fetch
. "$ATL_MANAGE/lib/appfetcher/fetch"

## Bash library for fetching and transforming application files, building on appfetcher/fetch. Each function here receives as arg 1 a directory containing some app content, and emits to stdout the name of another directory containing transformed content. Used by ../bin/atl_deploy


# Return a path to a ready-do-deploy ATL_LONGNAME + ATL_VER app, customized with correct ownerships and permissions.
# Input is an unarchived, uncustomized app directory.
# Must be a subshell for lastpipe to have any effect
customized_app() (
	set -eu
	shopt -s lastpipe
	appdir="$1"

	# We don't want ATL_UID, which varies per ATL_TENANT instance but not per deployment (ATL_LONGNAME distinguishes e.g. dev.easyjethro.com.au from easyjethro.com.au)
	customizedapp="$(cacheslot "$ATL_LONGNAME-$ATL_VER-customized")"
	_log() { log "customized_app:$customizedapp: $*"; }
	if [[ ! -d $customizedapp ]]; then
		tmp=$(cacheslot_tmp)
		mkdir "$tmp"
		# Don't use hardlinks. If app/ is a git 'tip' checkout then the contents of .git/objects/* may change under us if hardlinked.
		cp -a "${appdir?}" "$tmp"/app
		cd "$tmp" || exit 1
		# FIXME: we need a place to set permissions that isn't customize_app - since we shouldn't have app-specific permissions in our cache
		customize_app "$@"
		mv "$tmp" "$customizedapp"
		_log "Successfully customized"
		# Our customized app is unpacked upstream ($appdir.inputhash), with UID/GID specific to ATL_LONGNAME
		{ echo "$ATL_LONGNAME-$ATL_VER:"; cat "$appdir.inputhash"; } > "$customizedapp.inputhash"
	else
		_log "No change in upstream unarchived $appdir - using cached content"
	fi
	echo "$customizedapp"
)

# Customise permissions for atlmanage user/groups
customize_atlmanage_apps() {
	# Grant ATL_USER read-only access to the app it runs (granted with root:$ATL_GROUP ownership). Later in this script we grant write permission to specific directories (logs/, temp/, work/), and later still (in the app patchqueue's $ATL_APPDIR/.hgpatchscript/*) permissions more will be granted, e.g. to 'nagios' to access monitoring/, and to 'www-data' access apache2/.
	# That sibling directories of app/ (backups/, monitoring/, replication/ etc) need never be accessible by ATL_USER/ATL_GROUP (only ATL_SERVICES_USER), so don't get the chown.


	case "$ATL_PRODUCT" in
	jira | confluence | crowd)
		rm -f app/bin/*.bat # We're not Windows
		# Atlassian app TLDs are sufficiently clean that we can dispense with app/
		mv app/* .
		rm -rf app
		# Note: these permissions are now set in .hgpatchscript/app. Setting them here in appfetcher is no use, because VCS patchqueue operations change permissions. The permissions need to be settable at runtime, not just deploy time.
	
		# The running app needs write access to these dirs
		#chown -R "$ATL_USER" "${ATL_TOMCAT_SUBDIR}"{logs,temp,work}
		# Allow services to write to their log file. This is checked in atl_check_appdeployment
		#setfacl -m "u:$ATL_SERVICES_USER:rwX" "${ATL_TOMCAT_SUBDIR}"{logs,temp}
		#chgrp "$ATL_GROUP" "${ATL_TOMCAT_SUBDIR}"webapps # Old versions of Confluence tried to evaluate webapps/../confluence, and so need read access to webapps/ (otherwise unused)


		# Jira and Confluence's Tomcat assumes a webapps/ directory, which Tomcat will create if it doesn't already exist. If Tomcat lacks permissions to create it, we get errors like:
		#  Caused by: java.lang.IllegalArgumentException: The main resource set specified [/opt/atlassian/confluence/6.3.1/webapps/../confluence] is not valid
		# We just create webapps/ here to avoid drama. Its permissions are set in .hgpatchscript/app
		mkdir -p "$ATL_TOMCAT_SUBDIR"webapps

		case "$ATL_PRODUCT" in
		jira) install -d -m 2750 "${ATL_TOMCAT_SUBDIR}conf/Catalina/localhost" ;;
		confluence) install -d -m 2750 "${ATL_TOMCAT_SUBDIR}conf/Standalone/localhost" ;;
		crowd)
			install -d -m 2750 "${ATL_TOMCAT_SUBDIR}conf/Catalina/localhost"
			chmod g+x "${ATL_TOMCAT_SUBDIR}"bin/*.sh # Crowd devs didn't give +x to the group
			;;

		esac
		# We don't want these random temp/ files in hg as Tomcat nukes temp/ on start, and their disappearance breaks commits
		if [[ -f ${ATL_TOMCAT_SUBDIR}temp/README.txt ]]; then rm -f "${ATL_TOMCAT_SUBDIR}temp/README.txt"; fi
		if [[ -f ${ATL_TOMCAT_SUBDIR}temp/safeToDelete.tmp ]]; then rm -f "${ATL_TOMCAT_SUBDIR}temp/safeToDelete.tmp"; fi
		;;
	fisheye)
		log "Attempting to customize $ATL_PRODUCT"
		mv app/* .
		rm -rf app
		warn "FIXME: chowns should be done in .hgpatchscript/app, not here in $0"
		chown -R "$ATL_USER" ./var
		chown "$ATL_USER" config.xml
		;;
	jethro)
		# We can't have any +x files in app. See bin/atl_check_appdeployment warning:
		# addwarning "Some files in app/ are executable. This will cause the .hgpatchscript/webserver-apache line 'setfacl -R -m u:www-data:rX app/resources app/favicon.ico app/robots.txt' to make them generally executable by www-data, which will cause jujutsu to start noticing.  The files are: $executable"

		chmod -x app/vendor/swiftmailer/swiftmailer/lib/swiftmailer_generate_mimes_config.php
		chmod -x app/vendor/drewm/mailchimp-api/scripts/travis.sh
		;;
	*)
		echo >&2 "We don't know how to customize $ATL_PRODUCT. Dropping to shell"
		bash
		;;
	esac
}

fetcher_confluence_definitions() {

	info() { echo "https://www.atlassian.com/software/confluence/download-archives"; }

	url() { echo "https://product-downloads.atlassian.com/software/confluence/downloads/atlassian-confluence-$(ver).tar.gz"; }

	validate() {
		tar_validator "$@"
		# As of Aug/23 there are no sha1s
		#if dpkg --compare-versions "$(ver)" ge 8; then
		#	sha1_validator "$@"
		#else
		#	tar_validator "$@"
		#fi

	}

	customize_app() {
		customize_atlmanage_apps "$@"
	}
}

fetcher_jira_definitions() {

	url() {
		#if dpkg --compare-versions "$ver" le 6.4.14; then
		#	# Older versions were just 'jira', not 'jira-software' / 'jira-core'
		#	this=jira
		#fi
		echo "https://product-downloads.atlassian.com/software/jira/downloads/atlassian-$ATL_PRODUCT_FULL-$(ver).tar.gz"
	}

	validate() {
		# As of Nov/24 there are no sha1s
		#if dpkg --compare-versions "$(ver)" ge 8; then
		#	sha1_validator "$@"
		#else
		tar_validator "$@"
		#fi

	}

	customize_app() {
		customize_atlmanage_apps "$@"
	}

}

fetcher_fisheye_definitions() {

	url() {
		#if dpkg --compare-versions "$ver" le 6.4.14; then
		#	# Older versions were just 'jira', not 'jira-software' / 'jira-core'
		#	this=jira
		#fi
		echo "https://product-downloads.atlassian.com/software/fisheye/downloads/$ATL_PRODUCT_FULL-$(ver).zip"
	}

	validate() {
		zip_validator "$@"
	}

	customize_app() {
		customize_atlmanage_apps "$@"
	}

}

fetcher_crowd_definitions() {

	url() { echo "https://product-downloads.atlassian.com/software/crowd/downloads/atlassian-crowd-$(ver).tar.gz"; }

	validate() {
		# Crowd doesn't have sha1 files
		tar_validator "$@"

	}

	customize_app() {
		customize_atlmanage_apps "$@"
	}
}

fetcher_jethro_definitions() {

	ver() { 
		case "$ATL_VER" in
			tip) echo "tip";;
			# Git tags start with 'v'
			*) echo "v${ATL_VER}";;
		esac
	}

	url() {
		case "$ATL_PRODUCT_FULL" in
			jethro-jeff) echo "git@github.com:jefft/jethro-pmm.git";;
			jethro*) echo "git@github.com:tbar0970/jethro-pmm.git";;
		esac
	}

	validate() { :; }

	customize_app() {
		customize_app_jethro_jujutsu "$@"
		customize_app_jethro_generate_js "$@"
		customize_app_jethro_generate_versiontxt "$@"
		customize_atlmanage_apps "$@"
		# THERES NO POINT SETTING OWNERSHIP OR PERMS HERE BECAUSE THE PATCHQUEUE TRASHES THEM
		# Our auxiliary scripts depend on temp/ and logs/ being present. Atlassian apps have them already
		mkdir temp logs                        # 'install -d' doesn't respect the parent's g+s flag
		#chown "$ATL_USER:$ATL_GROUP" temp logs # temp/ is known as ATL_LOCKDIR
	}

	# Create Jujutsu repo from git, adding Tom's or Jeff's git content as required
	customize_app_jethro_jujutsu() (
		pushd app
		jj git init --colocate
		local originurl
		originurl="$(git remote get-url origin)"
		[[ -n $originurl ]] || fail "Unexpectedly no 'origin' git remote"
		case "$originurl" in
			"git@github.com:jefft/jethro-pmm.git") 
				set -x
				# Create a local bookmark tracking each remote push-* bookmark
				jj bookmark track master@origin 'glob:push-*@origin'
				jj git remote add tom git@github.com:tbar0970/jethro-pmm.git
				#jj git fetch --remote tom
				;;
			"git@github.com:tbar0970/jethro-pmm.git")
				jj git remote rename origin tom
				jj config set --repo git.fetch "tom"
				jj config set --repo git.push "jeff"
				perl -i -pe 's/master\@origin/master/g' .jj/repo/config.toml
				jj git remote add jeff git@github.com:jefft/jethro-pmm.git
				jj git fetch --remote jeff
				jj bookmark track 'glob:push-*@jeff'
				jj git remote add ej git@github.com:jefft/jethro-pmm-easyjethro.git
				jj git fetch --remote ej
				jj bookmark track 'glob:*@ej'
				;;
			*)
				fail "Unexpected git origin url: $originurl"
				;;
		esac
		popd
	) >&2

	customize_app_jethro_generate_js() (
		# Jethro from Git lacks static jethro-ATL_VER.{js,css} files, so generate them before adding the app to mercurial.
		if [[ ! -f app/resources/js/jethro-$ATL_VER.js || ! -f app/resources/css/jethro-$ATL_VER.css ]]; then
			_log "Doing devbox stuff"
			devbox init
			devbox -q add nodejs
			grep -qF 'less.js/1.7.5/less.min.js' app/templates/head.template.php || fail "Cannot validate that Jethro is still using less 1.7.5. Check app/templates/header.template.php where it used to be included"
			devbox -q run -- npm init -y
			devbox -q run npm add less@1.7.5

			# Add via npm instead of devbox because devbox doesn't have v1.7.5, and we'd have to patch variables.css
			#devbox -q add nodePackages.less

			cd app/resources/js
			[[ ! -f jethro-$ATL_VER.js ]] || fail "Already have jethro-$ATL_VER.js"
			[[ -z $(ls -1 | grep -vP "(jethro-${ATL_VER}.js|jquery.js|jquery-ui.min.js|bootstrap.js|jquery.min.js|bootstrap.min.js|tb_lib.js|bsn_autosuggest.js|jethro.js|jquery-ui.js|jquery.ui.touch-punch.min.js|stupidtable.min.js)") ]] || fail "Extra js files have been added, and might be now included in the combined jethro-$ATL_VER.js"
			# shellcheck disable=SC2016
			php -r '$files=["jquery.min.js", "bootstrap.min.js", "tb_lib.js", "bsn_autosuggest.js", "jethro.js", "jquery-ui.js", "jquery.ui.touch-punch.min.js", "stupidtable.min.js"]; echo implode("/* --- */\n", array_map(fn($f)=>file_get_contents($f), $files));' > "jethro-$ATL_VER.js"


			cd ../less
			[[ ! -f ../css/jethro-$ATL_VER.css ]] || fail "Already have jethro-$ATL_VER.css"
			devbox run -c ../../../devbox.json npx lessc --include-path=app/resources/less <(php jethro.less.php) > "../css/jethro-$ATL_VER.css"
			cd ../../..
			# Clean up after ourselves
			rm -r devbox.{lock,json} package.json package-lock.json .devbox node_modules
		fi
		# Stdout to stderr because stdout is reserved for returning a path
	) >&2

	# Even tagged versions (v2.36.1) don't contain include/version.txt, so regenerate it, just like we regenerate
	# JS/CSS
	customize_app_jethro_generate_versiontxt() (
		if [[ -f app/include/version.txt ]]; then
			echo "Jethro in $PWD already has a version.txt containing $(cat app/include/version.txt)"
		else
			echo "Jethro in $PWD has no version.txt. Creating one containing $ATL_VER" 
			# Don't customize the version here, or if you do, make sure it matches jethro-$whatever.js and
			# jethro-$whatever.css
			echo "$ATL_VER" > app/include/version.txt
		fi
	) >&2

}

fetcher_invoiceninja_definitions() {

	#url() { echo "https://download.invoiceninja.com/ninja-v$(ver).zip"; }
	url() { echo "https://github.com/invoiceninja/invoiceninja/releases/download/v${ver}/invoiceninja.tar.gz"; }


	# validate() { :; }

	customize_app() {

		# THERES NO POINT SETTING OWNERSHIP OR PERMS HERE BECAUSE THE PATCHQUEUE TRASHES THEM
		# From https://invoice-ninja.readthedocs.io/en/latest/install.html
		chown -R "$ATL_USER" app/{storage,bootstrap,public/logo}

		if [[ -d $ATL_DATADIR/storage ]]; then
			rm -rf app/storage
			ln -s "$ATL_DATADIR/storage" app/storage
		else
			log "Please move app/storage/ to $ATL_DATADIR/storage, and symlink it back"
			bash
		fi
		if [[ -d $ATL_DATADIR/public/logo ]]; then
			rm -rf app/public/logo
			ln -s "$ATL_DATADIR/public/logo" app/public/logo
		else
			log "Please move app/public/logo to $ATL_DATADIR/public/logo, and symlink it back"
			bash
		fi

		mkdir temp logs                        # 'install -d' doesn't respect the parent's g+s flag
		#chown "$ATL_USER:$ATL_GROUP" temp logs # temp/ is known as ATL_LOCKDIR
		#log "This deployment script does not know how to set permissions on a new $ATL_PRODUCT deployment. We have dumped you in a bash session in the app directory $PWD. IF root:$ATL_GROUP is sufficient then nothing further needs doing. Please exit when satisfied"
		#mv storage storage-template
		#install -d -o "$ATL_USER" temp
		#install -d -o "$ATL_USER" logs
		#(
		#cd app
		#bash
		#)

	}

}

jujutsuize() {
	mercurialize "$@"
}

# Returns $1 committed into a mercurial repository
mercurialize() {
	set -eu
	local dir inputhash oldhash dir cache
	dir="$(readlink -f "$1")"  # normalize

	[[ -d "$dir" ]] || {
		errmsg "Cannot mercurialize nonexistent upstream dir '$dir'"
		return 1
	}

	read -r inputhash <"$dir.inputhash"
	[[ -n $inputhash ]] || fail "Upstream $dir.inputhash missing."

	[[ -f "$dir.id" ]] || fail "Missing $dir.id. Is this because we removed it from cacheslot?"
	cache=$(cacheslot "$(cat "$dir".id)-hg")
	_log() { log "mercurialize:$cache: $*"; }

	if [[ -d $cache ]]; then
		read -r oldhash <"$cache.inputhash"
		if [[ $oldhash == "$inputhash" ]]; then
			_log "To-be-mercurialized content hasn't changed. Reusing"
		else
			_log "Stale (upstream hash '$inputhash' is not '$oldhash'); recreating"
			rm -rf "${cache?}" "$cache".*
		fi
	fi

	if [[ ! -d "$cache" ]]; then
		_log "Mercurializing $dir"
		tmp=$(cacheslot_tmp)
		cp -al "$dir" "$tmp"
		cd "$tmp" || fail
		# The app/ directory will be under git control, and if .idea/ is ever allowed (e.g. when editing a pre-patchqueue commit), it's files get auto-added by jujutsu. Hence we block .idea here, before the patchqueue
		{
			echo ".idea"
			echo ".jj"
		} | if [[ -d app ]]; then cat - >> app/.gitignore; else cat - >> .gitignore; fi
		#
		hg -q init >&2
		[[ ! -d .git ]] || fail "What?? Why would there ever be a .git directory here, in $PWD, and not in $PWD/app/.git (if any)?"
		[[ ! -f .hgignore ]] || fail "Unexpected .hgignore"

		# Create a basic .hgignore that ignores itself, because .hgignore.d/* will contain further patch-specific
		# ignores that can be appended.
		{
			echo "## Regexes of paths containing 'runtime' files created by the running app (e.g. Tomcat's logs/), wh  ose changes we don't want flagged as needing checking into the patchqueue."
			echo "## Each patch in our patchqueue appends paths or regexes it considers 'runtime' here."
			echo "syntax: rootglob"
			echo ".hgignore"
			echo ".gitignore"
			echo ".jj"
			echo ".git"
			echo ".devbox"
			echo ".idea"
			echo "app/.gitignore"
			echo "app/.jj"
			echo "app/.git"
			echo "app/.devbox"
			echo "app/.idea"
		} > .hgignore

		hg -q commit -X app/.git --addremove -m "Clean deployment" >&2
		mv "$tmp" "$cache"
		cp "$dir.inputhash" "$cache.inputhash"
	else
		[[ -z $(hg -q --cwd "$cache" status) ]] || {
			errmsg "Contents has changed from under mercurial ('hg status' in $cache failed). Please 'cd' here and run 'hg status'"
			return 1
		}
		_log "Using cached mercurialized app"
	fi
	_log "This is our mercurialized copy of $dir"
	echo "$cache"
}

ver() { echo "${ATL_VER}"; }

fetcher_cachedir() {
	echo "$(cachedir --global)/cache"
}

_appfetcher_fn=fetcher_"$ATL_PRODUCT"_definitions
if [[ $(type -t "$_appfetcher_fn") == function ]]; then
	"$_appfetcher_fn"
	# Not sure if this is needed:
	export -f url
	export -f validate
	export -f customize_app
	log "Yay, defined appfetcher functions $_appfetcher_fn. url is $(url), ver is $(ver)"
else
	fail "Don't know how to fetch app '$ATL_PRODUCT' (missing '$_appfetcher_fn' function)"
fi

# Override the $ATL_MANAGE/lib/appfetcher/fetch version of this function.
# fetcherhash() returns a string (hash) that will change whenever the fetcher code (here, appfetcher.sh and lib/appfetcher/fetch) changes. This means that changes in the fetching algorithm (e.g. different chmod rules) invalidate previous cache entries
# Nov/24: it is too confusing having caching fail drastically every time this file is edited.
#fetcherhash() { sha1sum "$ATL_MANAGE/lib/appfetcher.sh" "$ATL_MANAGE/lib/appfetcher/fetch" | sha1sum | awk '{print $1}'; }
fetcherhash() { echo 1; }
