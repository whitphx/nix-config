# Rootless Nix via nix-user-chroot — the full "shared box reached over
# SSH" bundle for hosts where root is unavailable.
#
# On such hosts /nix cannot be created at the filesystem root the usual
# way. nix-user-chroot works around it with a Linux user namespace that
# bind-mounts a per-user directory onto /nix for the current process
# tree — a rootless Nix that exists only inside processes launched
# through it. `chroot-zsh` is the entry point: it enters the chroot and
# becomes a login zsh.
#
# Enabling `myEnv.nixUserChroot.enable` turns on one coherent bundle:
#   1. the chroot-zsh entry wrapper,
#   2. an in-pane $SHELL reset (so in-chroot callers don't re-enter it),
#   3. the host's /usr/bin/tmux (NOT nix's tmux) driving those panes.
#
# Why the host's tmux, and why this cannot just be common's tmux behind
# an `$SSH_CONNECTION` guard (the crux):
#   - A nix tmux *server* would run inside the chroot, and its bind
#     mounts decay as SSH sessions disconnect/reconnect, eventually
#     wedging the server. So the server runs as the host's /usr/bin/tmux
#     *outside* the chroot, and each pane spawns chroot-zsh to enter a
#     fresh, disposable chroot — decay is scoped to one pane.
#   - That choice is a build-time host-type fact, not a runtime one: an
#     `if-shell $SSH_CONNECTION` branch inside one already-chosen config
#     can neither pick a different tmux binary nor conjure /nix for a
#     server that has none. (And SSH-ness is the wrong predicate anyway —
#     a non-chroot host reached over SSH still wants the full nix tmux.)
#   - Consequences that shape the tmux config below: the server has no
#     /nix mounted, so it can load NONE of common's `${pkgs.tmuxPlugins.*}`
#     store-path plugins → a plugin-free status bar; and it is the host's
#     older tmux (e.g. Ubuntu 22.04's 3.2), so 3.3+ features like
#     `allow-passthrough` are omitted.
#
# NOT owned here: the nix-user-chroot *binary* itself — it must run
# *before* /nix exists, so it cannot live in or dynamically link against
# /nix/store; it stays a manual bootstrap at ~/.local/bin/nix-user-chroot.
{ config, lib, pkgs, ... }:
let
  cfg = config.myEnv.nixUserChroot;
  homeDir = config.home.homeDirectory;
  chrootZshPath = "${homeDir}/.local/bin/chroot-zsh";

  # chroot-zsh: enter the chroot, then become a login zsh. Forward "$@"
  # so it serves both roles it is invoked in:
  #   - interactive login shell — tmux spawns it as default-shell /
  #     default-command with no args;
  #   - `$SHELL -c "cmd"` for non-interactive callers (Claude Code's Bash
  #     tool and its shell-snapshot bootstrap, scripts, git hooks).
  # A hardcoded `exec zsh -l` would drop the `-c "cmd"`, launch a bare
  # interactive zsh that never runs the command nor exits, and hang the
  # caller. (The profileExtra reset below means most `$SHELL -c` traffic
  # never reaches this wrapper — but the forward keeps it correct if it
  # does, e.g. before .zprofile has run, or from a non-tmux entry point.)
  chrootZsh = ''
    #!/bin/bash
    exec "${homeDir}/.local/bin/nix-user-chroot" "${cfg.nixDir}" bash -lc 'exec zsh -l "$@"' bash "$@"
  '';

  # Pin -f to our own config so /etc/tmux.conf cannot bleed in on a
  # shared host. Installed at ~/.local/bin/tmux, ahead of /usr/bin in
  # PATH, so plain `tmux` resolves here and runs the host binary with
  # our config.
  tmuxWrapper = ''
    #!/bin/bash
    exec /usr/bin/tmux -f "$HOME/.config/tmux/tmux.conf" "$@"
  '';

  # Config for the host's /usr/bin/tmux — see the file header for why it
  # is the host binary, plugin-free, and written for pre-3.3 tmux.
  tmuxConf = ''
    unbind C-b
    set -g prefix C-o
    bind-key C-o send-prefix

    set -g base-index 1
    setw -g pane-base-index 1
    set -sg escape-time 0
    setw -g mouse on
    set -g default-terminal "tmux-256color"
    set -g history-limit 50000
    set -g focus-events on
    set-option -g renumber-windows on

    # Every pane enters a fresh, disposable chroot via chroot-zsh, which
    # this module installs. tmux also exports this path as $SHELL in the
    # pane; profileExtra (below) resets it to the real zsh at login so
    # in-pane `$SHELL -c` callers don't nest another chroot.
    set -g default-shell ${chrootZshPath}
    set -g default-command ${chrootZshPath}

    bind r source-file ~/.config/tmux/tmux.conf \; display "Reloaded!"
    bind-key c new-window -a
    bind 3 split-window -h -c "#{pane_current_path}"
    bind 2 split-window -v -c "#{pane_current_path}"
    bind-key -n C-S-Left  swap-window -t -1\; select-window -t -1
    bind-key -n C-S-Right swap-window -t +1\; select-window -t +1

    set -as terminal-features ",*:RGB"
    set -as terminal-features ",tmux-256color:sync"
    # `allow-passthrough on` is omitted because Ubuntu 22.04's
    # /usr/bin/tmux is 3.2 and does not recognise it. We only need
    # passthrough for nested tmux scenarios; this host runs a single
    # level of tmux, and `set -s set-clipboard on` below is enough to
    # surface OSC 52 to the outer terminal.

    # OSC 52 clipboard: the outer terminal forwards copies to the
    # client's system clipboard.
    set -s set-clipboard on
    set -as terminal-features ",*:clipboard"

    setw -g status-style fg=colour255,bg=colour234
    setw -g window-status-style fg=cyan,bg=default,dim
    setw -g window-status-current-style fg=white,bright,bg=colour170
    set -g pane-border-style fg=colour111,bg=colour236
    set -g pane-active-border-style fg=colour227,bg=colour240
    set -g message-style fg=white,bg=black,bright

    set -g status-left-length 80
    set -g status-left "#[fg=yellow]W-#I #[fg=cyan]P-#P"
    set -g status-right "#{?client_prefix,#[bg=colour226 fg=black] PREFIX #[default],} %Y-%m-%d(%a) %H:%M "
    set -g status-interval 10
    set -g status-justify centre
    setw -g monitor-activity on
    set -g visual-activity off
    set -g status-position top

    bind-key -T copy-mode             C-w               send-keys -X copy-selection-and-cancel \; display "Copied"
    bind-key -T copy-mode             MouseDragEnd1Pane send-keys -X copy-selection-and-cancel \; display "Copied"

    # SSH override placed last so it beats the unconditional defaults
    # above. The bash that starts this tmux is itself an SSH session,
    # so $SSH_CONNECTION is set and this branch fires. The prefix-swap +
    # status/border restyle come from the neutral ../tmux-ssh-overrides.conf
    # shared with common's nix tmux; only the two lines below are specific
    # to this host tmux (a plugin-free status-right, and an extra
    # pane-rotate binding).
    if-shell '[ -n "$SSH_CONNECTION" ] || [ -n "$SSH_TTY" ]' {
    ${builtins.readFile ../tmux-ssh-overrides.conf}
      # Mirror the default `prefix + o` pane-rotate onto `prefix + u` so
      # the "tap the prefix letter twice" muscle memory keeps working
      # after the prefix moves from C-o to C-u.
      bind-key u select-pane -t :.+
      # Plugin-free status-right (host tmux server can't load nix plugins).
      set -g status-right "#{?client_prefix,#[bg=colour226 fg=black] PREFIX #[default],} %Y-%m-%d(%a) %H:%M "
    }
  '';
in
{
  options.myEnv.nixUserChroot = {
    enable = lib.mkEnableOption "rootless Nix bundle: chroot-zsh $SHELL + reset + host tmux";

    nixDir = lib.mkOption {
      type = lib.types.str;
      default = "${homeDir}/.nix";
      description = "Directory bind-mounted onto /nix inside the user chroot.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Use the host's /usr/bin/tmux (installed via the wrapper below), not
    # nix's — see the file header for why.
    programs.tmux.enable = lib.mkForce false;

    home.activation.installChrootZsh = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      install -m 755 -D ${pkgs.writeText "chroot-zsh" chrootZsh} \
        "${chrootZshPath}"
    '';

    home.activation.installTmuxConf = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      install -m 644 -D ${pkgs.writeText "tmux.conf" tmuxConf} \
        "${homeDir}/.config/tmux/tmux.conf"
    '';

    home.activation.installTmuxWrapper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      install -m 755 -D ${pkgs.writeText "tmux" tmuxWrapper} \
        "${homeDir}/.local/bin/tmux"
    '';

    # A tmux pane already runs *inside* the chroot (/nix is mounted, the
    # real zsh is directly runnable), yet tmux exports chroot-zsh as
    # $SHELL in the pane. Re-entering via chroot-zsh from there is
    # redundant — a `$SHELL -c "cmd"` caller would spin up a nested
    # nix-user-chroot per command. Reset $SHELL to the real zsh once at
    # login; children inherit it and run commands directly. New panes
    # still enter a fresh chroot, because tmux spawns them from the
    # default-shell/-command server options, not from this per-pane
    # $SHELL. Self-guarded on the wrapper path, so it is a no-op wherever
    # $SHELL is already a normal shell.
    programs.zsh.profileExtra = ''
      if [[ "$SHELL" == "${chrootZshPath}" ]]; then
        export SHELL="${pkgs.zsh}/bin/zsh"
      fi
    '';
  };
}
