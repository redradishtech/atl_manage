#!/bin/bash

MINUTES_BEFORE_EVENT='10'
ymd="$(date -d "$MINUTES_BEFORE_EVENT minutes ago" +%Y%m%d)"
hm="$(date -d "$MINUTES_BEFORE_EVENT minutes ago" +%H:%M)"
cat <<-EOF > atop
#!/bin/bash -eu
atop -r $ymd -b $hm
EOF
chmod +x atop

cmd=(lnav)
ymdhms_start="$(date -d "$MINUTES_BEFORE_EVENT minutes ago" +'%Y-%m-%d %H:%M:%S')"
cmd+=(-c ":hide-lines-before $ymdhms_start")
ymdhms_event="$(date +'%Y-%m-%dT%H:%M:%S')"
cmd+=(-c ":goto 100%")
cmd+=(-c ":echo Logs begin $MINUTES_BEFORE_EVENT minutes before slowdown was logged at $ymdhms_event")
# The @Q '${cmd[@]@Q}' is bash 4.4+ black magic to print the quotes. See https://stackoverflow.com/questions/12985178/bash-quoted-array-expansion
cat <<-EOF > lnav
#!/bin/bash -eu
dir="\$(dirname "\${BASH_SOURCE[0]}")"
${cmd[@]@Q} "\$dir"/logs
EOF
chmod +x lnav
