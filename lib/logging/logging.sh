# shellcheck shell=bash

## Bash library definings log and error functions:
##
## log()	Standard log message, printed with inline stacktrace
## LOG()	log(), but emphasised
## warn()	Like log() but in red
## debug()	log() but only prints if ATL_DEBUG=true
## error()	Like warn(), but prints a stacktrace and exits the script.
## quit()	Like error() but with no stacktrace.
##
## Also sets an ERR trap handler that prints a nice error() should any command fail. The message includes relevant variable values at time of failure.

#if [[ $(type -t log) = function ]]; then return 0; fi   # Avoid sourcing this file more than once.

# Colour definitions

#echo "logging.sh sourced from ${BASH_SOURCE[1]:-} <- ${BASH_SOURCE[2]:-} <- ${BASH_SOURCE[3]:-} <- ${BASH_SOURCE[4]:-}"
export DEFAULT='\u001B[0m'
export HI='\u001B[1m'
export LO='\u001B[2m'
export RED='\u001B[31m'
export BLUE='\u001B[34m'
export GREEN='\u001B[32m'
export YELLOW='\u001B[33m'
export BGYELLOW='\u001B[33m'
export MAGENTA='\u001b[35m'
export RESET='\e[0m'

# Role colours
# FIXME: figure out the code for gray, rather than magenta here.
export DISABLED="${HI}${MAGENTA}"

LOG() {
  echo -e "${BLUE}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${RESET}"
  echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${RESET}"
  log "$@"
  echo -e "${BLUE}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${RESET}"
  echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${RESET}"
}
export -f LOG

log() {
  ## Comment out the tty-checking, as $onelinestack always contains ANSI codes so we must use -e until that is fixed
  #if [[ -t 1 ]]; then
  #	# We print $* instead of $1 so that we can print ${foo[@]} correctly
  if [[ ! -v quiet || ! $quiet ]]; then
    onelinestack
    # FIXME: onelinestack disables 'set -x' globally, which is annoying for the caller. We could call onelinestack in a subshell to fix this
    echo >&2 -e "$onelinestack ${*}${RESET}"
  fi
  #else
  #	echo >&2 -e "$onelinestack >>>> $1"
  #fi
}
export -f log

warn() {
  onelinestack
  #if [[ -t 1 ]]; then
  echo >&2 -e "$onelinestack ${HI}${RED}!!!${RESET} ${HI}${*}${RESET}" >&2
  #else
  #	echo >&2 -e "$onelinestack *** ${1}" >&2
  #fi
}
export -f warn

# http://wiki.bash-hackers.org/scripting/debuggingtips
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

errmsg() {
  echo >&2 -e "${HI}${RED}!!!${HI}${*}${RESET}				(CWD: $PWD)"
}
export -f errmsg

error() {
  set +x # First turn off +x in case the caller left it on. The caller doesnt want to see the gory details of this function
  # ATL_OVERRIDE=<key> makes this error non-fatal. This capability was never used, so commented out
  #local errkey
  #errkey=$(echo "$*" | md5sum | head -c5)
  errmsg "$*"
  if [[ $- != *e* ]]; then
	  #echo "-e is not set. This isn't going to work"
	  exit $CONTROLLED_DEMOLITION
  else
	  # Let errhandler() print the stacktrace.
	  return "$CONTROLLED_DEMOLITION"
  fi
}
export -f error

fail() { error "$@"; }
export -f fail

debug() {
  if [[ -v ATL_DEBUG && $ATL_DEBUG = true ]]; then
    log "$@"
  else
    :
  fi
}
export -f debug

quit() {
  export nostacktrace=1
  error "$@"
}

export -f quit

# Alternative 'stacktrace' implementation from https://unix.stackexchange.com/questions/19323/what-is-the-caller-command
die() {
  local frame=0
  while caller $frame; do
    ((frame++))
  done
  echo "$*"
  exit 1
}
export -f die

# Set a 'onelinestack' variable with the function name callstack, excluding boring bits, and replacing 'main' with the filename
onelinestack() {
  set +x # First turn off +x in case the caller left it on. The caller doesnt want to see the gory details of this function
  onelinestack=
  local topstack
  ((topstack = ${#BASH_SOURCE[@]} - 1))
  local i
  local funcname
  for ((i = topstack; i >= 0; i--)); do
    # Use 'case' instead of bash's [[ .. =~ .. ]] construct, because the latter resets ${BASH_REMATCH[@]} which the caller may depend on
    case "${FUNCNAME[$i]}" in
    # Skip the top-most parts of the stacktrace to do with logging
    onelinestack | log | fail | warn | error | errhandler) continue ;;
    assert_*) continue ;;
    main)
      if [[ -v main_printed ]]; then continue; fi
      funcname="${BASH_SOURCE[$i]}:${BASH_LINENO[1]}"
      # This takes half the time of $(basename ...)
      funcname=${funcname##*/}
      # Bash uses 'main' as a virtual function name for commands in the root of the script. We don't want to print it once
      local main_printed=true
      ;;
    *)
      funcname="${FUNCNAME[$i]}"
      ;;
    esac
    if [[ $i != $((${#BASH_SOURCE[@]} - 1)) ]]; then onelinestack+=" → "; fi
    onelinestack+="${LO}${funcname}${RESET}"
  done
}
export -f onelinestack

printstacktrace() {
  [[ ! -v nostacktrace ]] || return 0
  set +x # First turn off +x in case the caller left it on. The caller doesnt want to see the gory details of this function
  for ((i = 0; i < ${#BASH_SOURCE[@]}; i++)); do
    # Skip the stacktrace lines from this 'printstacktrace' function, or the 'fail' function, or the 'errhandler' ERR trap
    if [[ ${FUNCNAME[$i]} =~ ^(printstacktrace|fail|error|errhandler)$ || ${FUNCNAME[$i]} =~ ^assert_ ]]; then continue; fi
    echo -e "\t${LO}${BASH_SOURCE[$i]}:${BASH_LINENO[$((i - 1))]} ${FUNCNAME[$i]}${RESET}" >&2
  done
}
export -f printstacktrace

# Our 'error' function exits with this special exitcode, allowing our 'errhandler' ERR trap handler to distinguish explicit from accidental failures
((CONTROLLED_DEMOLITION = 4))
export CONTROLLED_DEMOLITION

ctrlchandler() {
  echo "Aborted (ctrl-c)"
  printstacktrace
  exit 0
}
export -f ctrlchandler

# Returns true if the caller is executing directly within a shell, and not in a subprocess.
issourced() {
  # If called from a script is executed normally in a subprocess, ${FUNCNAME[-1]} will be 'main'
  # If called from a script sourced from the user's shell, ${FUNCNAME[-1]} will be 'source'
  # If called from a function defined in the user's shell, ${FUNCNAME[-1]} will be the name of the function
  # Therefore our check is for ${FUNCNAME[-1]} != main
  # echo >&2 "issourced: FUNCNAME[-1]=${FUNCNAME[-1]}. FUNCNAME[@]=${FUNCNAME[*]}"
  [[ ${FUNCNAME[-1]} != "main" ]]
}

called_from_prompt_command() {
  # I don't understand why, but when PROMPT_COMMAND is set to atl_bash_prompt in lib/profile.sh, and then atl_bash_prompt sources lib/profile.sh, in turn sourcing lib/logging.sh, then FUNCNAME[-1] is equal to 'atl_bash_prompt', not 'source' as I would expect. Hence this check to prevent the error handler being set in the caller every time the shell auto-reloads an edited profile
  [[ ${PROMPT_COMMAND:-} == *"${FUNCNAME[-1]}"* ]]
}

# Make the 'errhandler' script trigger on nonzero exit codes (ERR) and interrupts (INT)
if ! called_from_prompt_command; then
  trap "errhandler ${BASH_SOURCE[1]}" ERR INT
  # When things go wrong and we ctrl-c, it is often useful to get a stacktrace to see what the scripts were doing
  #trap 'ctrlchandler' INT
fi

# Functions should inherit this ERR handler. https://superuser.com/questions/257587/error-propagation-not-working-in-bash
set -o errtrace

# ERR trap handler, triggered when any function or subprocess returns nonzero. This includes autocomplete (pressing tab)
errhandler() {
  ## DO NOT PUT ANYTHING ABOVE THE EXITCODE CAPTURE. Do not even break the 'local exitcode' declaration out into a separate line. We need to get the values of $? and $BASH_COMMAND before any further command
  local exitcode=$?
  local _BASH_COMMAND="$BASH_COMMAND"

  #log "errhandler($*). exitcode $exitcode. Functions: ${FUNCNAME[*]}"

  set +x # First turn off +x in case the caller left it on. The caller doesn't want to see the gory details of this function

  if ((exitcode == CONTROLLED_DEMOLITION)); then
    # Two ways we end up here:
    # 1) error() was called in a function, triggering 'return $CONTROLLED_DEMOLITION'
    # 2) error() was called in a subprocess, and now we, its parent, notice the $CONTROLLED_DEMOLITION exit code.
    #
    # In case 1) we could have error() print the stacktrace, but in case 2 we want both stacktraces of the subprocess (which error() could have provided) *and* the stacktrace of the subprocess caller, us -- and there is no other opportunity to print the caller's stacktrace except here in the err handler. So to handle case 2, error() never prints the stacktrace - it is always done here.
    printstacktrace

    # If our caller is a regular function defined in the user's bash session, just return() to end the function. The caller will have to 'return 1' as we can't do it for them.
    if issourced; then
      #echo >&2 "Say goodbye to your shell. Sorry, but the function stacktrace '${FUNCNAME[*]}' invoked error(), and we need to halt processing immediately, and cannot do it any other way"
      #echo >&2 "Say goodbye to your shell. Sorry, but the function stacktrace '${FUNCNAME[*]}' invoked error(), and we need to halt processing immediately, and cannot do it any other way" > /tmp/atlmanage_lasterr
      errmsg "${CONTROLLED_DEMOLITION}"
    else
	  echo >&2 "Exiting with code $CONTROLLED_DEMOLITION"
      exit "${CONTROLLED_DEMOLITION}"
    fi
  else
    # Accidental failure (not fail() or error()) from a failed subprocess or function. Print a nicely formatted message and stacktrace.
    # Locate the $variable names in _BASH_COMMAND, and print their values to aid debugging. Use 'column -t' to format them, with \t as the separator as used in printf
    [[ $- == *e* ]] || return # Only print debugging if Bash's -e (-errexit) flag is set. When the flag is not set it is quite normal for commands to 'fail' returning nonzero.
    local args
    args="$(
      cmd="$_BASH_COMMAND"
      # shellcheck disable=SC2016    # The '' is actually legitimate here.
      while [[ $cmd =~ '${'?([a-zA-Z0-9_]+)'}'? ]]; do # We quote the ${ and } with 's 1) to avoid backslashes, 2) to avoid confusing vim's syntax regex
        var="${BASH_REMATCH[1]}"
        [[ -v $var ]] && printf "%s=%q\n" "$var" "${!var}"
        # shellcheck disable=SC2295
        cmd="${cmd##*${BASH_REMATCH[1]}}"
      done | column -s$'\t' -t
    )"
    errmsg "		Command failed ($exitcode): $_BASH_COMMAND\n$args"
    printstacktrace
  fi
}
export -f errhandler

# vim: set ft=sh:
