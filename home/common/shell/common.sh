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
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# $TMUX leaks when a GUI app is launched via `open -a` from a
# tmux-bound shell — the var propagates to the app, then to
# every child shell it spawns, even though those shells have no
# real tmux ancestor. Without this guard the auto-attach block
# below sees $TMUX set and skips, leaving a bare shell. Walk
# parent PIDs; if no tmux ancestor is found, the value is stale.
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

# Auto-attach (or create) a tmux session for new interactive
# shells. `exec` replaces the shell so exiting tmux closes the
# terminal. Escape hatch: `NO_AUTO_TMUX=1 bash` skips the launch
# for one-off shells that need to stay bare.
# Skip inside VSCode's / Cursor's integrated terminal — its UI
# already provides tab/split management and tmux's status bar
# just steals vertical space there.
# The interactive / tty / $CLAUDECODE guards keep the `exec` from
# hijacking shells that merely *source* this rc to harvest the
# environment (Claude Code's Bash tool, git hooks, scp): they run
# non-interactively or without a tty on stdout, so tmux would
# replace the process and hang forever, wedging the command.
__shell_auto_tmux() {
  case $- in
    *i*) ;;
    *) return 0 ;;
  esac
  [ -t 1 ] || return 0
  [ -z "${CLAUDECODE:-}" ] || return 0
  [ -z "${TMUX:-}" ] || return 0
  [ -z "${NO_AUTO_TMUX:-}" ] || return 0
  [ "${TERM_PROGRAM:-}" != "vscode" ] || return 0
  command -v tmux >/dev/null || return 0

  # Reconcile the running tmux server's loaded conf state
  # against what's on disk. Two failure modes covered:
  # - boot-race partial load: the conf parse halts before
  #   reaching its last line (@loaded != "1"). The conf sets
  #   @loaded on its last line as a parse-completion marker.
  # - stale conf after darwin-rebuild switch: the rendered
  #   conf has changed but the running server still holds
  #   the previous version's settings. ~/.config/tmux/tmux.conf
  #   is a symlink whose target changes to a new /nix/store
  #   path whenever the conf content changes; that target is
  #   the version identity. Stored in @conf-id here.
  # When no server is running, start it explicitly so @conf-id
  # can be set before any client attaches — that avoids a
  # spurious re-source on the next shell after a clean boot.
  local expected loaded conf_id need
  expected=$(readlink ~/.config/tmux/tmux.conf 2>/dev/null)
  if tmux info >/dev/null 2>&1; then
    loaded=$(tmux show-options -gv @loaded 2>/dev/null)
    conf_id=$(tmux show-options -gv @conf-id 2>/dev/null)
    need=0
    [ "$loaded" != "1" ] && need=1
    [ -n "$expected" ] && [ "$expected" != "$conf_id" ] && need=1
    if [ "$need" = 1 ]; then
      tmux source-file ~/.config/tmux/tmux.conf 2>/dev/null
      [ -n "$expected" ] && tmux set-option -g @conf-id "$expected" 2>/dev/null
    fi
  else
    tmux start-server
    [ -n "$expected" ] && tmux set-option -g @conf-id "$expected" 2>/dev/null
  fi

  exec tmux new-session -A -s main
}
__shell_auto_tmux
unset -f __shell_auto_tmux

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

# A single model checkpoint runs to tens of GB, which the NFS home
# cannot absorb. umihebi is reached over InfiniBand and measures
# ~660 MB/s against ~105 MB/s for the ethernet-backed volumes, which
# is what checkpoint load time rides on. Hosts without it mounted keep
# the default ~/.cache/huggingface.
if [ -d "/data/umihebi0/users/$USER" ]; then
  export HF_HOME="/data/umihebi0/users/$USER/huggingface"
fi

# The token defaults to $HF_HOME/token, which ties it to whichever
# volume the block above picked, and a credential that vanishes when a
# host does not mount that volume surfaces as an auth failure rather
# than a missing mount. Pin it to the home volume, which every host has.
# Where HF_HOME is left alone this is the path it would resolve to
# anyway.
export HF_TOKEN_PATH="$HOME/.cache/huggingface/token"

unset __shell_name
