# Login-shell setup shared by zsh and bash on macOS.
#
# Sourced by both shells, so no shell-specific syntax: the PATH surgery
# below goes through `tr`/`grep`/`paste` rather than a split-on-colon
# loop, because zsh doesn't word-split an unquoted $PATH the way bash
# does. Login-time only, so the forks cost nothing per prompt.

# Source Homebrew for HOMEBREW_PREFIX / MANPATH / INFOPATH, then push
# /opt/homebrew/{bin,sbin} to the back of $PATH so Nix-managed
# binaries win lookups (`brew shellenv` prepends them by default).
# Existence-checked so the shell still boots on hosts where Homebrew
# isn't installed (e.g. a fresh macOS).
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  PATH=$(printf '%s' "$PATH" \
    | tr ':' '\n' \
    | grep -v -x -e /opt/homebrew/bin -e /opt/homebrew/sbin \
    | paste -s -d: -)
  # `:+` so a PATH that filtered down to nothing cannot leave a
  # leading empty field, which every shell reads as the cwd.
  export PATH="${PATH:+$PATH:}/opt/homebrew/bin:/opt/homebrew/sbin"
fi

# macOS Tahoe (26) sometimes doesn't propagate $SSH_AUTH_SOCK into
# GUI-launched shells, even though launchd still has a socket bound.
# Recover it from launchctl's "inherited environment" so ssh-add /
# ssh / git can reach the agent without manual export.
if [ -z "${SSH_AUTH_SOCK:-}" ]; then
  _ssh_sock=$(/bin/launchctl print "gui/$(id -u)/com.openssh.ssh-agent" 2>/dev/null \
    | /usr/bin/awk '/^[[:space:]]*SSH_AUTH_SOCK/ {print $NF; exit}')
  [ -n "$_ssh_sock" ] && export SSH_AUTH_SOCK="$_ssh_sock"
  unset _ssh_sock
fi
