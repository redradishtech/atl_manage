#!/bin/bash

# If a log file we're interested in preserving is over this many Mb (uncompressed), then only store the last this-many-Mb (compressed)
LOGFILE_TOOLARGE_MB=2
LOGFILE_TOOLARGE_BYTES=$((LOGFILE_TOOLARGE_MB * 1024 * 1024))

mkdir -p logs

logfiles=()
case "$ATL_PRODUCT_RUNTIME_TECHNOLOGY" in
	java*)
		# Hack: assume 'java' means Tomcat
		logfiles+=("$ATL_LOGDIR/catalina.out")
		;;
esac
case "$ATL_PRODUCT" in
	jira) logfiles+=("$ATL_DATALOGDIR/atlassian-jira.log") ;;
	confluence) logfiles+=("$ATL_DATALOGDIR/atlassian-confluence.log") ;;
	crowd) logfiles+=("$ATL_DATALOGDIR/atlassian-crowd.log") ;;
esac

case "$ATL_WEBSERVER" in
	apache2)
		logfiles+=(/var/log/apache2/$ATL_LONGNAME/{access,error}.log)
		;;
esac

for path in "${logfiles[@]}"; do
	filename="$(basename "$path")"
	if [[ -r $path ]]; then
		#echo >&2 "Saving $path to logs/$filename"
		tail -c$LOGFILE_TOOLARGE_BYTES "$path" > logs/"$filename"
	fi
done

exit

# This stuff is too slow and complicated

#shellcheck disable=SC2034
[[ -v ATL_LOGDIR &&  -d "$ATL_LOGDIR" ]] || { echo >&2 "No log directory ATL_LOGDIR (${ATL_LOGDIR:-})"; exit 1; }
lsof "${x[@]}" -a +D "$ATL_LOGDIR" -u "$ATL_USER" | tail -n+2 | while read -r _ pid user _ _ _ size _ path
do
	name="$(basename "$path")"
	LOGFILE_TOOLARGE_BYTES=$((LOGFILE_TOOLARGE_MB * 1024 * 1024))
	if (( size == 0 ))
	then
		# Copy it just so we know the file was zero-bytes
		cp "$path" logs/"$name"
	elif (( size > LOGFILE_TOOLARGE_BYTES )) && [[ ! -v ATL_LOG_DISABLE_LARGEFILE_TRUNCATION ]]
	then
		{ 
			echo "$name logfile was too large to capture entirely ($size bytes). Showing only the last ${LOGFILE_TOOLARGE_MB}Mb:"
			tail -c$LOGFILE_TOOLARGE_BYTES "$path"
		} | gzip > logs/"$name".gz
else
	< "$path" gzip > logs/"$name".gz
	fi
done
