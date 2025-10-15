#!/bin/bash

# Chrome and Firefox hardcode *.internal to ::1 or 127.0.0.1, which makes debugging hard, so use .internal instead. 
INTERNAL_HOSTNAME_OLD=${ATL_SHORTNAME/_/-}.localhost
INTERNAL_HOSTNAME=${ATL_SHORTNAME/_/-}.internal

validateperms() {
	getent group www-data >/dev/null || error "Unexpectedly missing www-data group (common to apache2 and nginx)"
	if [[ -d $ATL_APPDIR/local ]]; then

		validate_user_can_read_all www-data "$ATL_APPDIR/local"
	fi
	if [[ $ATL_PRODUCT = jira ]]; then
		# If any patches added extra icons, this ensures the appropriate www-data permissions were set in a .hgpatchscript/ file

		#log "Ensuring JIRA images are readable by Apache, which serves them directly"
		#setfacl -R -m user:www-data:rX "$ATL_APPDIR/atlassian-jira/images"
		validate_user_can_read_all www-data "$ATL_APPDIR/atlassian-jira/images"
	fi
	log "✓"
}

install_webserver_listener() {
	if [[ $ATL_WEBSERVER = apache2 ]]; then
		# Are we listening on all interfaces port 80, or do we explicitly mention $INTERNAL_HOSTNAME?
		apachectl configtest # Ensure everything is fine with Apache before tinkering
		# Remove this line after Dec/2024 when all ports.conf files should be upgraded.
		perl -i -pe "s/^Listen $INTERNAL_HOSTNAME_OLD:80$/Listen $INTERNAL_HOSTNAME:80/" /etc/apache2/ports.conf
		if ! grep -E -i -q "(^Listen 80|^Listen \*:80|$INTERNAL_HOSTNAME)" /etc/apache2/ports.conf; then
			log "Tweaking Apache's ports.conf to make Apache listen on $INTERNAL_HOSTNAME:80"
			apachetmp=$(mktemp)
			cp -a /etc/apache2/ports.conf "$apachetmp"
			echo "Listen $INTERNAL_HOSTNAME:80" >>/etc/apache2/ports.conf
			apachectl configtest ||
				{
					cp -a "$apachetmp" /etc/apache2/ports.conf
					apachectl configtest || error "While attempting to patch /etc/apache2/ports.conf, we created a backup at $apachetmp. Our mod failed, and we restored $apachetmp to /etc/apache2/ports.conf, but 'apachectl configtest' is still broken! Please fix manually"
					error "Abort! Abort! Our attempt at adding 'Listen $INTERNAL_HOSTNAME:80 to /etc/apache2/ports.conf failed, and has been rolled back. Please manually ensure that $INTERNAL_HOSTNAME:80 is being listened on."
				}
		fi
	elif [[ $ATL_WEBSERVER = nginx ]]; then
		webserver_test
		if [[ ! -v ATL_WEBSERVER_NGINX_CONFIGURED ]]; then
			error "FIXME: Please manually configure nginx to listen on $INTERNAL_HOSTNAME:80 (in addition to the defaults), or set ATL_WEBSERVER_NGINX_CONFIGURED if this has been done"
		fi
		webserver_test
	fi
}

# Create /etc/apache2/sites-available/{appdomain}.conf or /etc/nginx/sites-available/{appdomain}.conf, if one doesn't
# already exist.
install_webserver_config() {
	local webserver="$1"
	local webserver_file
	webserver_file="$ATL_APPDIR_BASE/current/$webserver/$webserver.conf"
	webserver_symlink="/etc/$webserver/sites-available/$ATL_APPDOMAIN.conf"
	webserver_symlink_referent="$(readlink "$webserver_symlink")" || :

	if [[ ! -f $webserver_file ]]; then
		error "No $webserver config file found: $webserver_file. Normally this is created by applying the patchqueue. Has atl_patchqueue been run?"
	elif [[ -f $webserver_symlink && ! -L $webserver_symlink ]]; then
		error "Expected to find symlink, but regular file present: $webserver_symlink"
	fi
	if [[ $(basename "$(readlink -f "$ATL_APPDIR_BASE"/current)") = "$ATL_VER" ]]; then
		# We don't want atl_install to mess with current/, but at the same time, if ATL_NEWVER=$ATL_VER then our newly created apache file should be used.
		# So we check where current/ currently points, and if at $ATL_VER, go ahead with the webserver symlink
		if [[ -L $webserver_symlink && $webserver_symlink_referent != "$webserver_file" ]]; then
			warn "Symlink $webserver_symlink points to $webserver_symlink_referent, NOT $webserver_file as this app would like. This can happen e.g. if 'app' and 'app-dev' are installed on the same server, used by different tenants. The first installed (hopefully 'app') wins. Not altering anything."
			return
		else
			ln -sf "$webserver_file" "$webserver_symlink"
		fi

		local dest
		dest=/etc/nginx/sites-enabled/"${ATL_APPDOMAIN}".conf
		if [[ ! -e $dest ]]; then
			log "Enabling $webserver vhost: $ATL_APPDOMAIN"
			ln -sf ../sites-available/"$ATL_APPDOMAIN".conf	"$dest"
			webserver_test || warn "We just symlinked in $dest and now $webserver is failing. Fix before restarting $webserver"
		else
			# At this point, ../sites-available/$ATL_APPDOMAIN.conf is guaranteed to point to what we want.
			local referent
			referent="$(readlink "$dest")"
			if [[ "$referent" != "../sites-available/$ATL_APPDOMAIN.conf" ]]; then
				# This should never happen. Why would the sites-enabled symlink not point to sites-available?
				error "$dest does not point to ../sites-available/$ATL_APPDOMAIN.conf as expected"
			fi
		fi


	else
		# We're not installing to current/. Proceed with caution to avoid messing up production.
		if [[ -L $webserver_symlink ]]; then
			# A sites-available/ config file exists. Is it valid?
			if [[ -f $webserver_symlink_referent ]]; then
				warn "$webserver_symlink already exists, pointing to $webserver_symlink_referent. Not modifying"
				return
			else
				warn "$webserver_symlink existed, but pointing to nonexistent file $webserver_symlink_referent. Recreating symlink to point to $webserver_file (which doesn't exist yet but will when $ATL_NEWVER becomes current)."
				ln -sf "$webserver_file" "$webserver_symlink"
			fi
		else
			if [[ -n $force ]]; then
				ln -sf "$webserver_file" "$webserver_symlink"
				warn "Symlinking $webserver_symlink -> $webserver_file, despite an earlier version being deployed (symlinked to current/). Please check that this hasn't broken Apache for the current production"
			else
				warn "How unusual, there is no $webserver_symlink file, despite an earlier version being deployed (symlinked to current/). Please check, and if okay, 'ln -s $webserver_file $webserver_symlink'"
			fi
		fi
		error "Our $ATL_APPDIR_BASE/current/ symlink does not point to \$ATL_VER ($ATL_VER). We expect it should, as we're in the POST install step. atl_install does not mess with current/ at all - that is the job for atl_upgrade. Please fix"
	fi
	# }}}

}

uninstall_webserver_config() {
	local webserver="$1"
	webserver_file=$webserver/${ATL_SHORTNAME}.conf
	webserver_symlink="/etc/$webserver/sites-available/$ATL_APPDOMAIN.conf"
	if [[ -f $webserver_symlink ]]; then rm "$webserver_symlink"; fi
}

rotatelogs() {
	local webserver="$1"
	# We put logs in subdirectories of /var/log/apache2/, which aren't rotated unless we do this
	perl -i -pe 's,^/var/log/'"$webserver"'/\*.log \{$,/var/log/'"$webserver"'/*.log /var/log/'"$webserver"'/*/*.log {,g' /etc/logrotate.d/"$webserver"
}

create_logdir() {
	local webserver="$1"
	# Create the log directory that our CustomLog and ErrorLog directives specify
	install -d -o root -g adm -m 755 /var/log/"$webserver"/"$ATL_APPDOMAIN"
}

install_webserver_selfsigned_ssl() (
	set -eu -p pipefail
	if [[ -n ${ATL_SSLCERTFILE:-} && ${ATL_SSLCERTFILE} != none ]]; then
		log "ATL_SSLCERTFILE provided; no need to generate self-signed"
		return
	fi
	# {{{ If we're installing the Apache template for the first time, install the self-signed certs too.
	certfile=/etc/ssl/local/$ATL_APPDOMAIN.crt
	keyfile=/etc/ssl/local/$ATL_APPDOMAIN.key
	log "Configuring self-signed cert: $certfile (specify ATL_SSLCERTFILE if you have a real one, or define it as blank for none)"
	install -d /etc/ssl/local
	if [[ ! -e $certfile ]]; then

		# Symlink if file doesn't exist or IS NOT a symlink
		log "Using temporary self-signed cert. Please replace cert $certfile with a real one"
		ln -s /etc/ssl/certs/ssl-cert-snakeoil.pem "$certfile"
	else
		log "\t$certfile exists; not modifying"
	fi
	if [[ ! -e $keyfile ]]; then
		ln -s /etc/ssl/private/ssl-cert-snakeoil.key "$keyfile"
	else
		log "\t$keyfile exists; not modifying"
	fi
	#}}}
)

uninstall_webserver_selfsigned_ssl() (
	set -eu -p pipefail
	# Note we don't check ATL_SSLCERTFILE as this 'uninstall' is pretty harmless (only removes symlinks) and we could have symlinks created before ATL_SSLCERTFILE was set
	certfile=/etc/ssl/local/$ATL_APPDOMAIN.crt
	keyfile=/etc/ssl/local/$ATL_APPDOMAIN.key
	# Only do non-destructive delete i.e. if the file is a symlink
	for file in $certfile $keyfile; do
		if [[ ! -e $file ]]; then continue; fi
		if [[ -L $file ]]; then
			log "Removing symlink $file (pointed to $(readlink -f "$file"))"
			rm "$file"
		elif [[ -n $force ]]; then
			log "Forcefully deleting $file"
			rm "$file"
		else
			warn "$file is not a symlink. Run with --force to delete"
		fi
	done
)

define_internal_interface() {
	## {{{ Define a *.internal internal hostname to bind :8009 to
	# Note that Apache 2.4.25+ refuses to allow hostnames containing '_', so we change them to '-'. http://apache-http-server.18135.x6.nabble.com/Underscores-in-hostnames-td5034985.html
	# Don't count commented-out lines
	if ! getent hosts "$INTERNAL_HOSTNAME" >/dev/null; then
		# Internal IP not yet defined

		if [[ -n ${ATL_INTERNALIP-} ]]; then
			# We have ATL_INTERNALIP explicitly set
			if grep -q "^${ATL_INTERNALIP}\s${INTERNAL_HOSTNAME}" /etc/hosts; then
				: # ATL_INTERNALIP hostname already defined
			elif grep -q "^${ATL_INTERNALIP}\s${INTERNAL_HOSTNAME_OLD}" /etc/hosts; then
				warn "Renaming $INTERNAL_HOSTNAME_OLD to $INTERNAL_HOSTNAME in /etc/hosts"
				perl -i -pe "s,^${ATL_INTERNALIP}\s${INTERNAL_HOSTNAME_OLD},${ATL_INTERNALIP}\t${INTERNAL_HOSTNAME} ${INTERNAL_HOSTNAME_OLD}," /etc/hosts
			elif grep -q "^${ATL_INTERNALIP}\s" /etc/hosts; then
				# ATL_INTERNALIP is mapped, but not to our hostname
				error "ATL_INTERNALIP for $ATL_SHORTNAME is explicitly defined as $ATL_INTERNALIP, but that is already mapped to something other than '${INTERNAL_HOSTNAME}' in /etc/hosts"
			else
				# ATL_INTERNALIP not mapped yet; add it
				echo -e "$ATL_INTERNALIP\t${INTERNAL_HOSTNAME}" >>/etc/hosts
			fi
		else
			# ATL_INTERNALIP not explicitly set; infer a default
			counter=100
			ATL_INTERNALIP="127.0.0.$counter"
			while grep -q "^$ATL_INTERNALIP\s" /etc/hosts; do
				((counter += 1))
				ATL_INTERNALIP="127.0.0.$counter"
			done
			log "Using internal IP: $ATL_INTERNALIP	${INTERNAL_HOSTNAME}"
			echo -e "$ATL_INTERNALIP\t${INTERNAL_HOSTNAME}" >>/etc/hosts
		fi
	fi
	if [[ $INTERNAL_HOSTNAME_OLD != "$INTERNAL_HOSTNAME" ]] && grep -q "[[:blank:]]${INTERNAL_HOSTNAME_OLD}" /etc/hosts; then
		warn "Warning: The old '.localhost' form of internal hostname, '$INTERNAL_HOSTNAME_OLD',  is still in /etc/hosts. It should be removed once '${INTERNAL_HOSTNAME}' is used everywhere"
	fi
	# }}}
}

undefine_internal_interface() {
	perl -i -pe "s/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\t${INTERNAL_HOSTNAME}$//" /etc/hosts
	if grep -q "\s${INTERNAL_HOSTNAME}" /etc/hosts; then
		warn "There is still a definition for ${INTERNAL_HOSTNAME} in /etc/hosts, but in an unexpected format. Please delete manually. The line is:\n$(grep "\s${INTERNAL_HOSTNAME}" /etc/hosts)"
	fi
	log "Removed $INTERNAL_HOSTNAME definition in /etc/hosts"
}

# vim: set ft=sh:
