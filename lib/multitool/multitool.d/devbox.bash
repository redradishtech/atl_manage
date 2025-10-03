# [Plugin]
# Name = Devbox
# Description = Runs script in a mostly-isolated Devbox environment.
#
# [Help:Devbox]
# Pure = Whether to run a mostly isolated Devbox environment, keeping only HOME, USER, DISPLAY. PATH contains Devbox paths to Devbox binaries, then /usr/bin. Defaults to true
#
# [Devbox]
# Pure=true

# @pre:*
_launch_in_devbox_shell() {
	if [[ ! -v DEVBOX_SHELL_ENABLED ]]; then
		#__log "Outside devbox. Args: $*"
		which nix >/dev/null || echo >&2 "We are about to invoke devbox, but the 'nix' command is not in PATH. 'nix' is normally found in /nix/var/nix/profiles/default/bin, added to your path by sourcing  /etc/profile.d/nix.sh. Are you in 'sudo -E'?"
		if [[ -v SUDO_COMMAND ]]; then
			echo >&2 "Error: We launched devbox UNDER SUDO. Devbox should come before sudo, so that "
		else
			: #__log >&2 "Good, devbox running before sudo"
		fi
		_devbox_init
		set -x
		exec devbox run -q --pure -- "$_script__path" "$_invokedfunc" "$@"
	else
		: #__log "Inside devbox. Args $*"
	fi
}

_devbox_init() {
		devbox init
		[[ -f .gitignore ]] && grep -q .devbox .gitignore || echo -e ".devbox/\ndevbox.lock" >> .gitignore
}
