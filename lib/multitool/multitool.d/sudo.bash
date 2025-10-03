# [Plugin]
# Name = Sudo
# Description = Runs under sudo

# @pre:*
_maybe_rerun_with_sudo() {
	# This works as follows:
	# multitool has examined all @pre and @post tags, and constructed a list of functions that need calling, stored in $_invokedfuncs[@]. One of the functions in $_invokedfuncs[@] is $_invokedfunc, the function tagged @main or requested specifically.
	#
	# Let's imagine _invokedfuncs is (_launch_in_devbox_shell __maybe_run_with_sudo sudofunc myfunc), and we've just been called:
	# If not EUID=0 already..
	#   check if any function in $_invokedfuncs actually needs sudo
	#     if so, we effectively abort and re-start multitool ('exec' overwrites the process) under sudo.
	#       the sudo'd multitool will again figure out $_invokedfuncs, and work through the functions
	#       	..when it gets to _maybe_rerun_with_sudo, this time $EUID will be 0
	#       		..so _maybe_rerun_with_sudo will be a no-op
	#       		..and remaining functions (sudofun, myfunc) will be run with EUID 0
	#
	# The problem with this algorithm is that perhaps 'myfunc' (in our example) doesn't need or want to run as root. But 'sudofunc' came before it, turned on sudo, and so everything after the first @sudo'd function runs under sudo.
	#
	# I don't know how to fix this yet.  The idea of preconstructing $_invokedfuncs[@] with 'sudo' in their is broken. What if we have: a b C D e F g, where C D and F need need sudo.
	#
	# Perhaps, in this function, while still non-root, we should FORK a 'sudo multitool.bash sudofunc'. Then when the forked process finishes, somehow indicate to our caller than 'sudofunc' is taken care of. The caller will proceed on with 'myfunc' as non-root.
	#
	# Probably sudo just can't be implemented as a plugin with '@pre:*'. Instead, our inner loop over $_invokedfuncs needs to test each function to see if it is @sudo'd, and if so, invoke it (and only it, i.e. _invokedfuncs = _invokedfunc) under sudo, then continue processing.

	if [[ $EUID != 0 ]]; then
		if __sudo_needed; then
			# The -E is to preserve the environment, notably DEVBOX_SHELL_ENABLED=1, without which devbox would try to run again
			set -x
			exec sudo -E "$_script__path" "$_invokedfunc" "$@"
		fi
	fi
}

# Do any of $_invokedfuncs need sudo?
__sudo_needed() {
	for f in "${_invokedfuncs[@]}"; do
		if [[ $_tag_sudo =~ "$f" ]]; then
			__log "$f is tagged @sudo. Becoming root.."
			return 0
		fi
	done
	echo "None of $_invokedfuncs needs sudo."
	return 1
}
