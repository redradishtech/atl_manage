#!/bin/bash -eu
case "$ATL_WEBSERVER" in
	apache2)
		www-browser -dump http://localhost/server-info 2>&1
		;;
	nginx)
		echo "Nginx has no server-status equivalent"
		;;
esac
