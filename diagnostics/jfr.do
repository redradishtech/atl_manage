#!/bin/bash

atl_flightrecording dump 1 "diagnostic"
file="$(basename "$(echo "$ATL_APPDIR/flightrecordings/"*"-diagnostic.jfr")")"
cp "$ATL_APPDIR/flightrecordings/$file" .
gzip "$file"
