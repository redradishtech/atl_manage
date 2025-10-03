#shellcheck shell=bash
# Given a directory, source any files containing nonexecutable bash source.
# Bash source files are identified by having line 1 start with '# shellcheck'
# Executable files any files not containing the '# shellcheck' marker are ignored.
# This script must be sourced, not executed, so that functions are defined in the caller shell.

#t0=$(date +%s%N)    # for profiling - see t1 at the end
if [[ -n "$1" ]]; then
  for f in "$1"/[a-z]*; do # We make the speed-uppnening assumption that executables are lowercase, variables are uppercase
    # We assume sourceable scripts are non-executable files ending in .sh (if a symlink, the referent is tested to allow for frontender scripts)
    if [[ -f "$f" &&
      ! -x "$f" &&
      $(realpath -m "$f") =~ \.sh$ ]]; then
      #echo >&2 "Sourcing $f"
      #shellcheck disable=SC1090
      . "$f"
    fi
  done
else
  echo >&2 "Usage: source loadfuncs.sh DIR"
  echo >&2 "where DIR is a directory containing *.sh files to source"
fi
#t1=$(date +%s%N)
#waittime=$(((t1 - t0)/1000000))
#echo $waittime
