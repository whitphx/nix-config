{ lib, pkgs, ... }:
{
  home.packages = with pkgs; [
    coreutils
    git-credential-manager
  ];

  # iTerm2: vendor the whole prefs plist and let iTerm2 load it via
  # its "Load preferences from a custom folder" feature. The symlink
  # target lives in the read-only Nix store, so iTerm2 can't write
  # changes back — UI edits are lost on quit. Edit the file in this
  # repo and re-switch to update.
  home.file."Library/Application Support/iterm2-prefs/com.googlecode.iterm2.plist".source =
    ./files/iterm2/com.googlecode.iterm2.plist;

  # Apple Terminal.app: no equivalent custom-folder feature, so import
  # the `ayu` profile dict via plutil and set it as the default. Idempotent
  # across re-runs (remove then re-insert). `killall cfprefsd` flushes the
  # preferences daemon's cache so the new profile shows up without a logout.
  home.activation.importTerminalProfile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PROFILE="${./files/terminal/ayu.terminal}"
    PLIST="$HOME/Library/Preferences/com.apple.Terminal.plist"

    if [ ! -f "$PLIST" ]; then
      /usr/bin/defaults write com.apple.Terminal ProfileCurrentVersion -float 2.06
    fi

    /usr/bin/plutil -insert "Window Settings" -dict "$PLIST" 2>/dev/null || true
    /usr/bin/plutil -remove  "Window Settings.ayu" "$PLIST" 2>/dev/null || true
    /usr/bin/plutil -insert  "Window Settings.ayu" -xml "$(cat "$PROFILE")" "$PLIST"

    /usr/bin/defaults write com.apple.Terminal "Default Window Settings" -string "ayu"
    /usr/bin/defaults write com.apple.Terminal "Startup Window Settings" -string "ayu"

    /usr/bin/killall cfprefsd 2>/dev/null || true
  '';

  programs.zsh.shellAliases.intelzsh = "arch -x86_64 zsh";

  programs.git.settings.credential = {
    # Empty string resets the helper chain so nixpkgs' git system
    # gitconfig (which sets `helper = osxkeychain` on darwin) doesn't
    # win lookups before manager gets a turn.
    helper = [ "" "manager" ];
    "https://github.com" = {
      provider = "github";
      username = "whitphx";
    };
  };

  # Source Homebrew for HOMEBREW_PREFIX / MANPATH / INFOPATH, then push
  # /opt/homebrew/{bin,sbin} to the back of $path so Nix-managed
  # binaries win lookups (`brew shellenv` prepends them by default).
  # Existence-checked so the shell still boots on hosts where Homebrew
  # isn't installed (e.g. a fresh macOS).
  programs.zsh.profileExtra = ''
    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
      path=("''${(@)path:#/opt/homebrew/(bin|sbin)}" /opt/homebrew/bin /opt/homebrew/sbin)
    fi
  '';
}
