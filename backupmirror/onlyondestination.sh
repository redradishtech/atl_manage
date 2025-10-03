isdestination || fail "$(uname -n) is not currently configured as destination (ATL_BACKUPMIRROR_DESTINATION unset). Aborting"
hassource || fail "$(uname -n) has no configured source (ATL_BACKUPMIRROR_SOURCE_HOST unset). Aborting"
