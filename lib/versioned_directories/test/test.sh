#!/bin/bash -eu

PATH=..:$PATH

shopt -s nullglob

[[ $(type -t error) ]] || error() {
	echo >&2 "$*"
	exit 1
}

[[ -f test.sh ]] || error "Must be run in the test/ directory"

set -x
rm -rf 1.0.0 2.0.0 3.0.0 next current previous old

switchver . check 1.0.0 && error "Expected an error"
mkdir 1.0.0
switchver . check 1.0.0 && error "Expected an error"
ln -s 1.0.0 current
switchver . check 1.0.0 || error "check 1.0.0 failed"
mkdir 2.0.0
switchver . upgrade 2.0.0 || error "upgrade 2.0.0 failed"
markers=(1.0.0/*.txt)
(( ${#markers[@]} == 1 )) && [[ ${markers[0]} = 1.0.0/UPGRADED_TO_2.0.0.txt ]] || error "Missing upgrade-to-2 marker file"

mkdir 3.0.0
switchver . upgrade 3.0.0 || error "upgrade 3.0.0 failed"
markers=(old/1.0.0/*.txt)
(( ${#markers[@]} == 1 )) && [[ ${markers[0]} = old/1.0.0/UPGRADED_TO_2.0.0.txt ]] || error "Missing upgrade-to-2 marker file"
markers=(2.0.0/*.txt)
(( ${#markers[@]} == 1 )) && [[ ${markers[0]} = 2.0.0/UPGRADED_TO_3.0.0.txt ]] || error "Missing upgrade-to-3 marker file"

switchver . downgrade || error "downgrade to 2.0.0 failed"
markers=(3.0.0/*.txt)
(( ${#markers[@]} == 1 )) && [[ ${markers[0]} = 3.0.0/DOWNGRADED_TO_2.0.0.txt ]] || error "Missing downgrade-to-2 marker file"
markers=(2.0.0/*.txt)
(( ${#markers[@]} == 0 )) || error "Unexpected marker file found in current/: ${markers[*]}"
markers=(1.0.0/*.txt)
(( ${#markers[@]} == 1 )) && [[ ${markers[0]} = 1.0.0/UPGRADED_TO_2.0.0.txt ]] || error "1.0.0: Missing upgrade-to-2 marker file"

switchver . downgrade || error "downgrade to 1.0.0 failed"
markers=(3.0.0/*.txt)
(( ${#markers[@]} == 1 )) && [[ ${markers[0]} = 3.0.0/DOWNGRADED_TO_2.0.0.txt ]] || error "Missing downgrade-to-2 marker file"
markers=(2.0.0/*.txt)
(( ${#markers[@]} == 1 )) && [[ ${markers[0]} = 2.0.0/DOWNGRADED_TO_1.0.0.txt ]] || error "Missing downgrade-to-1 marker file"
markers=(1.0.0/*.txt)
(( ${#markers[@]} == 0 )) || error "Unexpected marker file found in current/: ${markers[*]}"


switchver . downgrade && error "Expected an error"
[[ $(readlink current) = 1.0.0 ]] || error "Downgrades did not leave is in the same place"
markers=(1.0.0/*.txt)
(( ${#markers[@]} == 0 )) || error "Unexpected marker files in 1.0.0"
markers=(2.0.0/*.txt)
(( ${#markers[@]} == 1 )) && [[ ${markers[0]} = 2.0.0/DOWNGRADED_TO_1.0.0.txt ]] || error "Missing downgrade marker file"


# Now to see if we detect brokenness
switchver . check 1.0.0 || error "Everything should be good but wasn't"
touch 1.0.0/DOWNGRADED_TO_0.0.0.txt
switchver . check 1.0.0 && error "Invalid marker - should have failed"

echo "Success!"

