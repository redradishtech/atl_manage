#!/bin/bash -eu
# Set the correct permissions for an app deployment.
#
# Currently post-install permissions are set .hgpatchscript/* scripts, which are added with each patch in the
# patchqueue, and applied on hg operations via $ATL_MANAGE/.hghooks/fixpermissions. This works, but it is annoying to
# have to edit the patchqueue for any alteration.

# globstar lets us match directories with **/
shopt -s globstar dotglob

fail() { echo >&2 "$*"; exit 1; }

main() {
	[[ $PWD = "$ATL_APPDIR" ]] || fail "Must be invoked in ATL_APPDIR"
	[[ $ATL_PRODUCT = jethro ]] || fail "Currently only defined for jethro"
}

shopt -s globstar dotglob

chown -R root:root .
# Establish baseline that GROUP can only read. But note we've not set the group ownership yet.
chmod -R u+rw,g+r,g-w,o= .	# Preserve +x on bin/* if set
#chmod -R -x app				# 
chmod ugo+x,g+s app/**/		# Note: the trailing / matches directories only. No -R as that would include files!

# The runtime user (running PHP) needs read access to the PHP files in app/
chgrp "$ATL_GROUP" .
chgrp -R "$ATL_GROUP" app

# Make our group ownership within app/ persistent with g+s, 'globstar' is needed for app/**/ to expand to app/ and all subdirectories. We don't need the -R flag because of this (and we don't want files g+s'd)
# Necessary because our patchqueue will modify files within app/* subdirectories (e.g. app/conf/server.xml, app/atlassian-jira/WEB-INF/classes/log4j.properties), and also outside (local/). 'hg qpush' technically recreates files, which without g+s would leave those files owned by root:root, not root:$ATL_GROUP.
#find app -type d -exec chmod g+s {} \;


chown "$ATL_USER:$ATL_GROUP" temp logs # temp/ is known as ATL_LOCKDIR
chmod ug+w temp logs

# Allow Jethro to write to sms.log
install -d -o "$ATL_USER" "$ATL_DATADIR/logs"


#### php-fpm

# The webserver tests for the existence of php files within app/*, before handing off to php-fpm, so www-data needs read access
setfacl -m u:www-data:rX app/**/
# Set u:www-data:rX as the default ACL too, to avoid confusion if e.g. an administrator hand-creates an app/*.php file.
setfacl -dm u:www-data:rX app/**/
# We don't need to grant any permissions to php/*.conf because php-fpm runs as root, before forking off non-root pools

# www-data serves static resources
setfacl -R -m u:www-data:rX app/resources app/favicon.ico app/robots.txt
# If regular PHP is broken, the www-data PHP will serve this file as a fallback
setfacl -m u:www-data:r app/error_phpfpm_not_listening.php

#### webserver-apache
setfacl -m u:www-data:rX  apache2
setfacl -m u:www-data:rX  ..
setfacl -m u:www-data:rX  .
# LetsEncrypt will create a transient file in .well-known, which must be accessible by www-data, so we set the default acl here
setfacl -R -d -m u:www-data:rX .well-known
# Set ACL on any existing static files and directories in .well-known/
setfacl -R -m u:www-data:rX .well-known

setfacl -R -d -m u:www-data:rX local/
setfacl -R -m u:www-data:rX local/

#### monitoring
# Nagios needs read access to monitoring/*.cfg config snippets, which are symlinked into its /etc directory.
# Grant this permission to /opt/atlassian/whatever/current (.) and /opt/atlassian/whatever (..), since as of Jan/2020 we lock down /opt/atlassian/whatever to not be group-readable.
setfacl -m u:nagios:rX . ..
setfacl -R -m u:nagios:rX monitoring
setfacl -R -m u:nagios:rX .env
# Some monitoring/*.healthcheck scripts run as $ATL_SERVICES_USER and need rX permission to the healthcheck scripts here.
setfacl -R -m g:"$ATL_SERVICES_GROUP":rX monitoring


#### letsencrypt
# The web server needs permission to serve files directly from 
chmod go-rw letsencrypt   # May contain credentials for renewing certs

#### systemd

# If the systemd .service file isn't world-readable we get repeated warnings in syslog: Configuration file /opt/atlassian/..../current/systemd/jira.service is marked world-inaccessible. This has no effect as configuration data is accessible via APIs without restrictions. Proceeding anyway.

shopt -s nullglob
files=(systemd/*.service)
if (( ${#files[@]} )); then
    chmod ugo+r systemd/*.service
fi

