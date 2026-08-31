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
#   3. the host's /usr/bin/tmux (NOT nix's tmux) driving those panes,
#   4. Home Manager's bash config switched off, because ~/.bashrc has to
#      stay readable from outside the chroot (see the option below),
#   5. `apptainer-zsh` and `srun-zsh`, the way into the same environment
#      on a batch scheduler's compute nodes, where this chroot cannot go
#      at all (shell/apptainer-zsh.sh has the why).
#
# These wrappers are installed into ~/.local/bin, and on a site where
# $HOME is one NFS export shared by every host, that is the whole
# distribution mechanism: activating on one host changes the shell every
# other host starts. It also means a store path chosen here has to be
# reachable from all of them, and that a broken wrapper breaks hosts this
# config was never activated on.
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

  # chroot-zsh: the shell every tmux pane on these hosts starts with.
  # Lives in shell/chroot-zsh.sh; see that file for what it forwards and
  # why it falls back instead of exiting.
  chrootZsh = builtins.replaceStrings
    [ "@nixDir@" "@chrootBin@" ]
    [ cfg.nixDir "${homeDir}/.local/bin/nix-user-chroot" ]
    (builtins.readFile ./shell/chroot-zsh.sh);

  # apptainer-zsh: the same job on a Slurm node, where AppArmor refuses
  # the user namespace chroot-zsh needs. See shell/apptainer-zsh.sh.
  apptainerZsh = builtins.replaceStrings
    [ "@nixDir@" "@caBundle@" ]
    [ cfg.nixDir "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" ]
    (builtins.readFile ./shell/apptainer-zsh.sh);

  # srun-zsh: the same job, spelled as one command. See shell/srun-zsh.sh.
  srunZsh = builtins.replaceStrings
    [ "@partition@" "@gpus@" ]
    [ cfg.slurm.partition cfg.slurm.gpus ]
    (builtins.readFile ./shell/srun-zsh.sh);

  # Pin -f to our own config so /etc/tmux.conf cannot bleed in on a
  # shared host. Installed at ~/.local/bin/tmux, ahead of /usr/bin in
  # PATH, so plain `tmux` resolves here and runs the host binary with
  # our config.
  tmuxWrapper = ''
    #!/bin/bash
    # Reachable on PATH from places the host binary is not, a container
    # bound to this home being the one that keeps happening, where the
    # bare exec failure names a line number instead of the problem.
    if [ ! -x /usr/bin/tmux ]; then
      echo "tmux: no /usr/bin/tmux here; this wrapper only drives the host tmux." >&2
      exit 127
    fi
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

    slurm = {
      partition = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          Default partition for `srun-zsh`. Empty leaves the flag off, so
          the caller has to pass `-p`.
        '';
      };

      gpus = lib.mkOption {
        type = lib.types.str;
        default = "1";
        example = "a100:2";
        description = ''
          Default value for `srun-zsh`'s `-G`, which takes Slurm's
          `[type:]count`. Empty leaves the flag off.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Use the host's /usr/bin/tmux (installed via the wrapper below), not
    # nix's — see the file header for why.
    programs.tmux.enable = lib.mkForce false;

    # Outside the chroot — which is where bash runs on these hosts, as the
    # SSH login shell — /nix does not exist, so a Home Manager ~/.bashrc
    # would be a symlink into an unreachable store path and bash would
    # silently source nothing. That file is also the bootstrap that puts
    # ~/.local/bin on PATH, which is the only way `chroot-zsh` is reachable
    # at all, so it stays hand-written here. Inside the chroot we are in
    # zsh.
    programs.bash.enable = lib.mkForce false;

    home.activation.installChrootZsh = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      install -m 755 -D ${pkgs.writeText "chroot-zsh" chrootZsh} \
        "${chrootZshPath}"
    '';

    home.activation.installApptainerZsh = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      install -m 755 -D ${pkgs.writeText "apptainer-zsh" apptainerZsh} \
        "${homeDir}/.local/bin/apptainer-zsh"
    '';

    home.activation.installSrunZsh = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      install -m 755 -D ${pkgs.writeText "srun-zsh" srunZsh} \
        "${homeDir}/.local/bin/srun-zsh"
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
