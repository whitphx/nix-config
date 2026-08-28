#!/bin/bash
# Entry point into the rootless chroot: enter it, then become a login
# zsh. Forwards "$@" so it serves both roles it is invoked in:
#   - interactive login shell — tmux spawns it as default-shell /
#     default-command with no args;
#   - `$SHELL -c "cmd"` for non-interactive callers (Claude Code's Bash
#     tool and its shell-snapshot bootstrap, scripts, git hooks).
# A hardcoded `exec zsh -l` would drop the `-c "cmd"`, launch a bare
# interactive zsh that never runs the command nor exits, and hang the
# caller.
#
# Every path through here has to end in a usable shell. tmux runs this
# as default-shell, so a wrapper that exits takes the pane with it and
# prints nothing the user ever sees: panes simply fail to open. That is
# how a store living on a volume one host did not mount presented
# itself. So check what can be checked, say what broke, and fall back to
# a plain system shell instead of exiting.

nix_dir="@nixDir@"
chroot_bin="@chrootBin@"
args=("$@")

fallback() {
  # Bash, not zsh: outside the chroot the only rc that resolves is the
  # hand-written ~/.bashrc, since Home Manager's dotfiles are symlinks
  # into a store this shell cannot reach. That rc is also what puts
  # ~/.local/bin on PATH, which is the first thing needed to repair
  # whatever went wrong.
  local shell=/bin/bash
  [ -x "$shell" ] || shell=/bin/sh

  if [ -t 2 ]; then
    {
      echo "chroot-zsh: cannot enter the Nix chroot, so this is a plain $shell."
      echo "  store:  $nix_dir"
      echo "  reason: $1"
      [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/          /'
      echo "  effect: nothing installed through Nix is on PATH here."
    } >&2
  else
    echo "chroot-zsh: $1; running $shell without the Nix environment (store: $nix_dir)." >&2
  fi

  export CHROOT_ZSH_FALLBACK=1
  exec "$shell" -l "${args[@]}"
}

[ -x "$chroot_bin" ] \
  || fallback "no nix-user-chroot binary at $chroot_bin"

# The common failure, and the one worth naming precisely: the store is
# fine, this host just cannot see the volume it sits on.
[ -d "$nix_dir/store" ] \
  || fallback "no store there from ${HOSTNAME:-this host}, which probably does not mount that volume"

# Everything else — a kernel or AppArmor policy refusing the user
# namespace, a half-written store — only surfaces on a real attempt.
# Costs about 10ms, against a pane that would otherwise die silently.
if ! probe=$("$chroot_bin" "$nix_dir" /bin/true 2>&1); then
  fallback "nix-user-chroot could not enter it" "$probe"
fi

exec "$chroot_bin" "$nix_dir" bash -lc 'exec zsh -l "$@"' bash "${args[@]}"
