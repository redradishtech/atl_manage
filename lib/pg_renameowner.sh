#!/bin/bash -eu
## Given pg_dump input, renames table and function owners to the given name
if [ $# -ne 1 ]; then
	echo >&2 "Usage: $0 <pgusername>"
	echo >&2 "Eg: $0 jira   # Makes tables owned by pg user 'jira'"
	exit 1
fi
newuser="$1"
if [[ $newuser =~ - ]]; then
	# Usernames containing hyphens must be quoted
	newuser="\"$newuser\""
fi

perl -pe "s/(^-- (Data for )?Name: .*; Owner: )[^;\n]+$/\1$newuser/g;
s/(^ALTER (?:TABLE|FUNCTION|SCHEMA|AGGREGATE|SEQUENCE|LARGE OBJECT) .* OWNER TO ).*?(?=[;\n])/\1$newuser\2/g;
s/(^(?:REVOKE|GRANT) ALL ON (?:TABLE|SCHEMA) .* (?:FROM|TO) \"?).*?(\"?;)/\1$newuser\2/g"
# Also handle function owners, which is done on lines like:
# ALTER FUNCTION public.nextid(tablename character varying) OWNER TO postgres;
#perl -pe "s/^(-- Name: .*; Owner: ).*?([;\n])/$1Owner: $newuser\1/gm;"
