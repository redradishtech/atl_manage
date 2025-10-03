#!/bin/bash
redo-ifchange database_activity
if [[ $ATL_DATABASE_TYPE =~ postgresql ]]; then
	redo pg_config
fi
