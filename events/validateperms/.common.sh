# shellcheck source=/opt/atl_manage/events/.run.sh shell=bash
# Needed as often the *.cfg won't expand to anything

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"/../.run.sh

# vim: set ft=sh:
