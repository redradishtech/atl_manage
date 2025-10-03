#!/bin/bash -eu
case "$ATL_WEBSERVER" in
	apache2)
		curl -s "http://$ATL_FQDN_INTERNAL/server-status" 2>&1
		;;
	nginx)
		echo "Nginx has no server-status equivalent"
		;;
esac
