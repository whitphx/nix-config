{ lib, pkgs, ... }:
let
  # Mirrors the tmux prefix: C-o normally, C-u on the hosts we only ever
  # reach over SSH, so an inner session doesn't swallow the prefix of an
  # outer one on the machine we came from. ../tmux-ssh-overrides.conf
  # carries the full rationale; tmux picks between the two at runtime,
  # which a TOML file cannot do.
  prefix = if pkgs.stdenv.hostPlatform.isDarwin then "ctrl+o" else "ctrl+u";
in
{
  # Keybindings mirror the tmux config in ./default.nix as closely as
  # herdr's action set allows, so the muscle memory carries over.
  # Actions left out keep herdr's own default, which already agrees with
  # tmux on c, n, p, x, z, [, ? and the 1..9 tab switches.
  #
  # Where an action also has an Emacs counterpart, the Emacs chord is
  # added next to the tmux one rather than replacing it. The layer stops
  # at the pane border: copy mode's own motion and selection keys are
  # hard-coded vi-style in herdr and the [keys] table has no entry for
  # them, so C-p, C-space and friends cannot be bound there.
  #
  # herdr rewrites this file itself when a setting changes in its UI or
  # when onboarding finishes. Home Manager hands it a read-only
  # /nix/store symlink, so those writes fail with a transient "failed to
  # save" notice and nothing sticks. Settings belong here instead.
  xdg.configFile."herdr/config.toml".text = ''
    onboarding = false

    [keys]
    prefix = "${prefix}"

    # Emacs's C-x 0, alongside tmux's `prefix x`. 0 sits outside the
    # 1..9 tab switches, so taking it costs nothing.
    close_pane = [ "prefix+0", "prefix+x" ]

    # The \ and - mnemonic from ./default.nix, next to herdr's own v
    # and minus. Each split also takes the shifted key, because herdr
    # reads | as a chord distinct from shift+backslash and binds them
    # separately; covering both means a held shift never misses.
    split_vertical = [ "prefix+v", "prefix+backslash", "prefix+|" ]
    split_horizontal = [ "prefix+minus", "prefix+shift+minus" ]

    new_workspace = "prefix+shift+c"
    move_tab_previous = "ctrl+shift+left"
    move_tab_next = "ctrl+shift+right"

    # tmux reloads its conf on `prefix + r`. herdr ships resize mode
    # there, so the two swap places; tmux has no resize mode to displace.
    reload_config = "prefix+r"
    resize_mode = "prefix+shift+r"

    # Stock tmux bindings that herdr spells differently by default.
    detach = "prefix+d"
    rename_tab = "prefix+comma"
    rename_workspace = "prefix+$"
    close_tab = "prefix+ampersand"
    last_pane = "prefix+semicolon"
    # tmux's arrows, plus Emacs's C-b/C-n/C-p/C-f. The bare letters are
    # already spoken for: herdr moves between tabs on n and p and
    # toggles the sidebar on b, so the Emacs half keeps its control
    # modifier even behind the prefix.
    focus_pane_left = [ "prefix+left", "prefix+ctrl+b" ]
    focus_pane_down = [ "prefix+down", "prefix+ctrl+n" ]
    focus_pane_up = [ "prefix+up", "prefix+ctrl+p" ]
    focus_pane_right = [ "prefix+right", "prefix+ctrl+f" ]

    # Navigate mode, which herdr opens on `prefix w`. Its keys take no
    # prefix in front of them, so the Emacs chords sit on bare control
    # and herdr's own h/j/k/l stay.
    #
    # C-p and C-n move the workspace list rather than pane focus: the
    # list is the surface where Emacs means "previous line" by them.
    # One chord cannot do both — herdr keeps the workspace binding and
    # disables the pane one — so pane up and down stay on k and j here.
    # Outside navigate mode the prefix keeps the two apart, and
    # `prefix C-p` / `prefix C-n` still move pane focus.
    navigate_workspace_up = [ "up", "ctrl+p" ]
    navigate_workspace_down = [ "down", "ctrl+n" ]
    navigate_pane_left = [ "h", "ctrl+b" ]
    navigate_pane_down = "j"
    navigate_pane_up = "k"
    navigate_pane_right = [ "l", "ctrl+f" ]
    resize_pane_left = "prefix+ctrl+left"
    resize_pane_down = "prefix+ctrl+down"
    resize_pane_up = "prefix+ctrl+up"
    resize_pane_right = "prefix+ctrl+right"

    # Both tmux's `prefix o` and Emacs's C-x o move to the next pane,
    # which displaces herdr's jump to the pane a notification came from.
    cycle_pane_next = "prefix+o"
    open_notification_target = "prefix+shift+o"

    [ui]
    # tmux's `bind c` opens a window straight away and `bind C` prompts
    # for a name. herdr defaults to the opposite of both.
    prompt_new_tab_name = false
    prompt_new_workspace_name = true
  '' + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''

    # tmux pastes the macOS clipboard into the pane on `prefix + C-y`.
    # herdr has no paste action, but a custom command is handed the
    # focused pane's id and herdr's own binary, which is enough to do
    # the same thing. Linux has no portable pbpaste, so there it stays
    # the terminal's own paste going through OSC 52, as in tmux.
    [[keys.command]]
    key = "prefix+ctrl+y"
    type = "shell"
    command = "\"$HERDR_BIN_PATH\" pane send-text \"$HERDR_ACTIVE_PANE_ID\" \"$(pbpaste)\""
  '' + ''

    [theme]
    # Both values are herdr's own defaults today, spelled out so an
    # upstream change doesn't move the theme out from under us.
    # auto_switch off is what naming a theme by hand means: ignore
    # whether the host terminal is in light or dark mode.
    name = "catppuccin"
    auto_switch = false
  '';
}
