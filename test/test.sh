#!/bin/bash -eu

source $ATL_MANAGE/lib/common.sh --no_profile_needed

mergebranches() 
{
	log mergebranches
	return 0

}

mergedbranch_already_validated_against_later_version()
{
	log mergedbranch_already_validated_against_later_version
}

validate_mergedbranch_applies()
{
	log validate_mergedbranch_applies
}

test_merges()
{
          if mergebranches "$@" && ! mergedbranch_already_validated_against_later_version "$2"; then
                  log "Changes were merged from branch '$1' to '$2', and we are not exempt from test-applying $2, so doing that now"
                  validate_mergedbranch_applies "$@"
          else
                  log "No need to validate"
          fi

}

verify_equals()
{
	out="$(echo "$1" | replace_tokens)"
	if [[ "$out" == "$2" ]]; then
		echo "$1 -> $2: ✓"
	else
		error "$1 evaluated to '$out', not '$2'"
	fi
}

verify_fail()
{
	if [[ $(echo $1 | replace_tokens 2>&1) =~ nonexistent ]]
	then
		echo "$1 failed to parse as expected"
	else
		error "$1 Failed ot fail"
	fi

}

test_replacetokens()
{
	export ATL_FOO=123
	verify_equals '%{ATL_FOO} %{ATL_FOO} %{ATL_FOO}' "${ATL_FOO} ${ATL_FOO} ${ATL_FOO}"
	verify_equals '%{ATL_FOO} %{ATL_FOO}' "${ATL_FOO} ${ATL_FOO}"
	verify_equals '%{ATL_FOO}%{ATL_FOO}' "${ATL_FOO}${ATL_FOO}"
	verify_equals '%{ATL_FOO}' "${ATL_FOO}"
	verify_equals '%{ATL_BOGUS:-bar}' "${ATL_BOGUS:-bar}"
	verify_equals '%{ATL_BOGUS:-%{ATL_FOO}}' "${ATL_BOGUS:-${ATL_FOO}}"
	verify_equals '%{ATL_FOO:+SUBS}' "${ATL_FOO:+SUBS}"
	verify_equals '%{ATL_FOO:+subs}' "${ATL_FOO:+subs}"
	verify_equals 'nothing' "nothing"
	verify_equals '%{ATL_FOO}' "${ATL_FOO}"
	verify_equals ' %{ATL_FOO}' " ${ATL_FOO}"
	#verify_equals '\%{ATL_FOO}' "%{ATL_FOO}"
	#verify_equals '%{ATL_FOO}\%{ATL_FOO}' "${ATL_FOO}\\${ATL_FOO}"
	verify_equals '%{ATL_FOO%3}' "${ATL_FOO%3}"
	verify_equals '%{ATL_FOO/3/4}' "${ATL_FOO/3/4}"
	verify_equals '%{ATL_FOO#1}' "${ATL_FOO#1}"
	verify_equals '%{ATL_FOO#1}' "${ATL_FOO#1}"
	verify_fail '%{nonexistent}'
	verify_equals '%{ATL_FOO:+Wants %{ATL_FOO}}' "${ATL_FOO:+Wants $ATL_FOO}"
	verify_equals '%{ATL_FOO:+Wants %{ATL_FOO}} %{ATL_FOO}' "${ATL_FOO:+Wants $ATL_FOO} ${ATL_FOO}"
	export ATL_SYSTEMD_REQUIRES=
	verify_equals '%{ATL_SYSTEMD_REQUIRES:+Wants=%{ATL_SYSTEMD_REQUIRES}}' ''
	export ATL_BASEURL='http://foobar'
	verify_equals '%{ATL_BASEURL##*://}' 'foobar'
	export ATL_MULTITENANT=true
	export ATL_FQDN=foo.example.com
	verify_equals '%{ATL_MULTITENANT:+$pool}.%{ATL_FQDN}'	'$pool.foo.example.com'   # Note that $pool is not evaluated. Often our template is generating bash code, where $pool is evaluated later.
}

test_versions()
{
	version_equal 1 1
	version_equal 1 1.0
	version_equal 1.0.0 1.0
	version_lessthan 1 2
	version_lessthan 1.2 2
	version_lessthan 1-3 2
	version_greaterthan 2 1
	! version_greaterthan 2.1 2.1
	version_greaterthan 1.2.3.4 1.2.3

}

test_replacetokens
#test_merges from to
#test_versions
