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
  # herdr rewrites this file itself when a setting changes in its UI or
  # when onboarding finishes. Home Manager hands it a read-only
  # /nix/store symlink, so those writes fail with a transient "failed to
  # save" notice and nothing sticks. Settings belong here instead.
  xdg.configFile."herdr/config.toml".text = ''
    onboarding = false

    [keys]
    prefix = "${prefix}"

    # Emacs's C-x 0, alongside tmux's `prefix x`. The splits are left on
    # herdr's own v and minus: C-x 2 and C-x 3 would take two of the
    # 1..9 tab switches with them, and the digits earn their keep there.
    # 0 sits outside that range, so it costs nothing.
    close_pane = [ "prefix+0", "prefix+x" ]

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
    focus_pane_left = "prefix+left"
    focus_pane_down = "prefix+down"
    focus_pane_up = "prefix+up"
    focus_pane_right = "prefix+right"
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
