#!/bin/bash -eu

. ../tagutils.bash

succeed() { 
	echo ✓
	return 0
	echo >&2 "Input: $(declare -p _tags)
	Goal: $goal
	Sequence: $expected
	✓
	"
}
fail() {
	echo >&2 "Input: $(declare -p _tags)
	Goal: $goal
	Expected: $expected
	Actual: $output
	✗
	"
}

test_precondition_ordering_and_postcondition() {
	declare -A _tags=([sudo]="pre:*" [devbox]="pre:* pre:sudo" [foo]=" pre:bar" [cleanup]=" post:*")
	goal=backup
	expected="devbox sudo $goal cleanup"
	output="$(function_with_tag_dependencies _tags "$goal" | xargs)"

	[[ $output = "$expected" ]] && succeed || fail

	goal=foo
	expected="devbox sudo $goal cleanup"
	output="$(function_with_tag_dependencies _tags "$goal" | xargs)"
	[[ $output = "$expected" ]] && succeed || fail

	goal=bar
	expected="devbox sudo foo $goal cleanup"
	output="$(function_with_tag_dependencies _tags "$goal" | xargs)"
	[[ $output = "$expected" ]] && succeed || fail

	goal=sudo
	expected="devbox $goal cleanup"
	output="$(function_with_tag_dependencies _tags "$goal" | xargs)"
	[[ $output = "$expected" ]] && succeed || fail

	goal=devbox
	expected="$goal cleanup"
	output="$(function_with_tag_dependencies _tags "$goal" | xargs)"
	[[ $output = "$expected" ]] && succeed || fail
}

test_double_precondition() {
	# both pre: functions must be present
	declare -A _tags=([sudo]="pre:*" [devbox]="pre:*" )
	goal=random
	# Order is undefined
	expected="(sudo devbox |devbox sudo )$goal"
	output="$(function_with_tag_dependencies _tags "$goal" | xargs)"
	[[ $output =~ $expected ]] && succeed || fail
}

test_explicitly_named_precondition() {
	declare -A _tags=([foo]="pre:bar")
	goal=bar
	expected="foo $goal"
	output="$(function_with_tag_dependencies _tags "$goal" | xargs)"
	[[ $output = $expected ]] && succeed || fail

	goal=foo
	expected="$goal"
	output="$(function_with_tag_dependencies _tags "$goal" | xargs)"
	[[ $output = $expected ]] && succeed || fail
}

test_notags() {
	declare -A _tags=()
	goal=random
	expected="$goal"
	output="$(function_with_tag_dependencies _tags "$goal" | xargs)"
	[[ $output = $expected ]] && succeed || fail
}

if (( $# > 0 )); then
	for fn in "$@"; do
		"$fn"
	done
else
	for fn in $(compgen -A function test_); do
		"$fn"
	done
fi
