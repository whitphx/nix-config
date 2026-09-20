# Interactive shell setup shared by zsh and bash.
#
# Zsh is the shell we live in; bash is kept ready for the cases that
# reach for it (hosts whose login shell we can't change, tools that
# hardcode it). Everything that doesn't need shell-specific syntax
# lives here so the two stay in step, and each rc file keeps only what
# its own shell alone can express — completion setup, line-editor
# tweaks, prompt-hook registration.
#
# Sourced by both shells, so: no zsh-only syntax, no bash-only syntax.
# Blocks that need `local` are wrapped in a function and called, since
# neither shell allows `local` at file scope.

if [ -n "${ZSH_VERSION:-}" ]; then
  __shell_name=zsh
else
  __shell_name=bash
fi

# GUI terminals can inherit Home Manager's sourced marker alongside the
# desktop locale, causing its session-variable script to skip these.
# Container images generally carry no locales at all, and asking for one
# that is absent makes every child warn on startup, so fall back to the
# C variant glibc has built in.
if locale -a 2>/dev/null | grep -qiE '^en_US\.(utf-?8)$'; then
  export LANG="en_US.UTF-8"
  export LC_ALL="en_US.UTF-8"
else
  export LANG="C.UTF-8"
  export LC_ALL="C.UTF-8"
fi

# $TMUX leaks when a GUI app is launched via `open -a` from a
# tmux-bound shell — the var propagates to the app, then to
# every child shell it spawns, even though those shells have no
# real tmux ancestor. `fix-term` below would then aim its
# send-keys at a pane belonging to a session that isn't ours and
# clear it. Walk parent PIDs; if no tmux ancestor is found, the
# value is stale.
__shell_drop_stale_tmux() {
  [ -n "${TMUX:-}" ] || return 0

  local pid=$PPID in_tmux=0
  while [ "$pid" -gt 1 ]; do
    case "$(ps -p "$pid" -o comm= 2>/dev/null)" in
      *tmux*) in_tmux=1; break ;;
    esac
    pid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ')
    [ -z "$pid" ] && break
  done

  [ "$in_tmux" = 1 ] || unset TMUX TMUX_PANE
}
__shell_drop_stale_tmux
unset -f __shell_drop_stale_tmux

# A TUI killed mid-session never gets to restore the terminal
# state it changed, so that state persists here: mouse tracking
# turns clicks into escape garbage, bracketed paste wraps pastes
# in markers, a stuck line-drawing charset renders ordinary text
# as box characters. A nested tmux reached over ssh is the usual
# trigger. None of it should ever be in effect while sitting at a
# shell prompt, so restoring before each prompt is idempotent,
# costs no fork, and repairs whatever the previous command broke
# without needing a wrapper per offending command. Both shells
# re-enable bracketed paste when their line editor starts, which
# is after this runs, so this doesn't fight them.
_restore-term-state() {
  if [ -t 1 ]; then
    # mouse tracking (normal/button/any), SGR mouse encoding,
    # focus reporting, bracketed paste, G0 charset, attributes
    printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1004l\e[?2004l\e(B\e[m'
  fi
}

# Escape hatch for damage the sequences above don't cover. Stays
# manual because inside tmux `send-keys -R` clears the visible
# pane (scrollback survives) — run automatically it would wipe
# the error output of whatever just failed.
fix-term() {
  [ -n "${TMUX:-}" ] && tmux send-keys -R -t "$TMUX_PANE" 2>/dev/null
  _restore-term-state
}

# Fuzzy-pick a ghq-managed repo and cd into it.
gl() {
  local repo
  repo=$(ghq list --full-path | fzf --layout=reverse --preview "cat {}/README.*")
  [ -n "$repo" ] && cd "$repo"
}

# Aikido Safe Chain wraps npm/yarn/pnpm to block known-malicious
# packages. Its init script is laid down by safe-chain's own
# installer (outside of this Nix config); source it if present.
# Newer installers write one POSIX script for every shell, older
# ones a per-shell `init-<shell>.<shell>`.
__shell_source_safe_chain() {
  local script
  for script in \
    "$HOME/.safe-chain/scripts/init-posix.sh" \
    "$HOME/.safe-chain/scripts/init-$__shell_name.$__shell_name"; do
    if [ -f "$script" ]; then
      . "$script"
      return 0
    fi
  done
}
__shell_source_safe_chain
unset -f __shell_source_safe_chain

# micromamba: drop-in for `conda activate` style env management.
if command -v micromamba >/dev/null 2>&1; then
  export MAMBA_EXE="$(command -v micromamba)"
  export MAMBA_ROOT_PREFIX="$HOME/.local/share/mamba"
  # Nix wraps micromamba as `.mamba-wrapped`; mamba 2.6 rejects that
  # basename when generating its shell function.
  _mamba_hook="$(
    micromamba shell hook --shell "$__shell_name" \
      | sed "s#\"/nix/store/[^\"]*/bin/\.mamba-wrapped\"#\"$MAMBA_EXE\"#g"
  )"
  eval "$_mamba_hook"
  unset _mamba_hook
fi

# A single model checkpoint runs to tens of GB, which an NFS home
# cannot absorb, so a host can point this at a volume with room (see
# myEnv.modelCacheDir). Which volume matters more than how fast it is:
# where $HOME is shared, a cache only some hosts can see is one that
# silently re-downloads on the others.
model_cache="@modelCacheDir@"
# Test the parent, since the volume can be mounted before anything has
# written a cache into it.
if [ -n "$model_cache" ] && [ -d "${model_cache%/*}" ]; then
  export HF_HOME="$model_cache"
fi
unset model_cache

# The token defaults to $HF_HOME/token, which ties it to whichever
# volume the block above picked, and a credential that vanishes when a
# host does not mount that volume surfaces as an auth failure rather
# than a missing mount. Pin it to the home volume, which every host has.
# Where HF_HOME is left alone this is the path it would resolve to
# anyway.
export HF_TOKEN_PATH="$HOME/.cache/huggingface/token"

unset __shell_name
