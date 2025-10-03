#!/bin/bash -eu
case "$ATL_WEBSERVER" in
	apache2)
		# We get duplicate IdleWorkers and BusyWorkers because Apache first prints the 'slot' total and then the sum. Usually they're the same.
		curl -s "http://$ATL_FQDN_INTERNAL/server-status?auto" | sort | uniq 2>&1
		# Old version:
		#curl -s http://"${ATL_SHORTNAME//_/-}".internal/server-status?auto | sort | uniq 2>&1
		;;
	nginx)
		echo "Nginx has no server-status equivalent"
		;;
esac
