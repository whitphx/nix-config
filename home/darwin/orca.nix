{ ... }:
{
  # Orca binds single chords and has no prefix concept, so the tmux and
  # Emacs shape carries over as "Cmd where the prefix used to be": the
  # second key of each chord is the one the muscle memory holds. Ctrl is
  # the one modifier to stay off. Orca's terminal shortcut policy is
  # orca-first, so it consumes a terminal-scoped binding before the pane
  # sees it, and a Ctrl chord would be taken away from the shell, from
  # Emacs, and from the agents running inside.
  #
  # Each list repeats Orca's own default alongside the added chord,
  # because an override replaces an action's defaults outright rather
  # than adding to them.
  #
  # Orca writes this file itself when shortcuts change in its settings
  # UI. Home Manager makes it a read-only store symlink, so those writes
  # fail and the bindings belong here instead.
  home.file.".orca/keybindings.json".text = builtins.toJSON {
    version = 1;
    keybindings = {
      # The literal | and _ of the mnemonic. Shift is what keeps these
      # clear of Mod+Minus, which is Orca's zoom out: sharing that key
      # would leave zoom working in one direction only whenever a pane
      # has focus.
      "terminal.splitRight" = [ "Mod+Shift+Backslash" "Mod+D" ];
      "terminal.splitDown" = [ "Mod+Shift+Minus" "Mod+Shift+D" ];
      # C-x o, and tmux's `prefix o`.
      "terminal.focusNextPane" = [ "Mod+O" "Mod+BracketRight" ];
      # tmux's `prefix ;`, which toggles to the last pane. Orca cycles
      # backwards instead, so the two agree only while a tab holds two
      # panes.
      "terminal.focusPreviousPane" = [ "Mod+Semicolon" "Mod+BracketLeft" ];
      # tmux's `prefix z`.
      "terminal.expandPane" = [ "Mod+Z" "Mod+Shift+Enter" ];

      # tmux's `prefix n` and `prefix p`. Alt joins the chord because
      # plain Mod+N and Mod+P belong to creating a workspace and to the
      # file finder, and shadowing the file finder costs more than the
      # pair is worth.
      "tab.nextTerminal" = [ "Mod+Alt+N" "Ctrl+PageDown" ];
      "tab.previousTerminal" = [ "Mod+Alt+P" "Ctrl+PageUp" ];
    };
  };
}
