{ ... }:
{
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
  };

  system.defaults = {
    dock = {
      orientation = "left";
      autohide = true;
      mru-spaces = false;
    };

    finder = {
      AppleShowAllFiles = true;
      FXPreferredViewStyle = "clmv";
    };

    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      "com.apple.trackpad.scaling" = 2.0;
    };

    trackpad.Clicking = true;

    controlcenter = {
      BatteryShowPercentage = true;
      Bluetooth = true;
    };

    # macOS Sonoma+ ignores `com.apple.menuextra.clock.DateFormat` in
    # favor of these structured toggles; an explicit ISO-style format
    # string is no longer possible in the native menu bar clock.
    menuExtraClock = {
      Show24Hour = true;
      ShowAMPM = false;
      ShowDate = 1;  # 0 = when space allows, 1 = always, 2 = never
      ShowDayOfWeek = true;
      ShowSeconds = true;
    };

    # Settings without typed options in nix-darwin land here. Each
    # key/value pair maps to a `defaults write <domain> <key> <value>`.
    CustomUserPreferences = {
      "com.apple.desktopservices".DSDontWriteNetworkStores = true;

      # Force-click + haptic feedback (the trackpad domain ships in
      # both wired and Bluetooth variants; both need the override).
      "com.apple.AppleMultitouchTrackpad".ForceSuppressed = 0;
      "com.apple.driver.AppleBluetoothMultitouch.trackpad".ForceSuppressed = 0;

      # iTerm2: read prefs from the Nix-managed plist symlinked into
      # ~/Library/Application Support/iterm2-prefs/ by home-manager.
      # NoSync* suppresses iTerm2's "your prefs changed, save?" alert
      # on quit since the folder is read-only (Nix store).
      "com.googlecode.iterm2" = {
        LoadPrefsFromCustomFolder = true;
        PrefsCustomFolder = "~/Library/Application Support/iterm2-prefs";
        NoSyncNeverRemindPrefsChangesLostForFile = true;
        NoSyncNeverRemindPrefsChangesLostForFile_selection = 0;
      };
    };
  };
}
