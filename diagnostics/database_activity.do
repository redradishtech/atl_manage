#!/bin/bash

if [[ $ATL_DATABASE_TYPE =~ postgresql ]]; then
	atl_psql --super -c "select * from pg_stat_activity where state!='idle' and query !~ 'pg_stat_activity';"
fi
