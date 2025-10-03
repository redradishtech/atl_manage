#!/bin/bash
if [[ $ATL_PRODUCT = jira ]]; then
	atl_logstats index 'map(select(.indextotalsnapshot=="snapshot")) '
fi
