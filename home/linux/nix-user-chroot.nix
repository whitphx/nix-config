# Rootless Nix via nix-user-chroot.
#
# On shared hosts where root is unavailable, /nix cannot be created at
# the filesystem root the usual way. nix-user-chroot works around this
# with a Linux user namespace that bind-mounts a per-user directory onto
# /nix for the current process tree — a rootless Nix that exists only
# inside processes launched through it. `chroot-zsh` is that entry point:
# it enters the chroot and becomes a login zsh.
#
# This module owns the *shell-level glue* only (the chroot-zsh wrapper
# and a $SHELL fixup). It is imported for every Linux host but does
# nothing unless `myEnv.nixUserChroot.enable = true`, so hosts that run
# Nix normally (e.g. a nix-daemon box) are unaffected.
#
# NOT owned here: the nix-user-chroot *binary* itself. It must run
# *before* /nix exists, so it cannot live in — or dynamically link
# against — /nix/store; it stays a manual bootstrap at
# ~/.local/bin/nix-user-chroot. Nor the "tmux outside the chroot"
# pattern, which is currently intertwined with per-host tmux styling and
# lives in the host module until a second chroot host justifies lifting
# it here too.
{ config, lib, pkgs, ... }:
let
  cfg = config.myEnv.nixUserChroot;
  chrootZshPath = "${config.home.homeDirectory}/.local/bin/chroot-zsh";

  # Forward "$@" so chroot-zsh serves both roles it is invoked in:
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
    exec "${config.home.homeDirectory}/.local/bin/nix-user-chroot" "${cfg.nixDir}" bash -lc 'exec zsh -l "$@"' bash "$@"
  '';
in
{
  options.myEnv.nixUserChroot = {
    enable = lib.mkEnableOption "rootless Nix entry via nix-user-chroot (chroot-zsh $SHELL wrapper + reset)";

    nixDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.nix";
      description = "Directory bind-mounted onto /nix inside the user chroot.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.activation.installChrootZsh = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      install -m 755 -D ${pkgs.writeText "chroot-zsh" chrootZsh} \
        "${chrootZshPath}"
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
