{ ... }:
{
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

    # Settings without typed options in nix-darwin land here. Each
    # key/value pair maps to a `defaults write <domain> <key> <value>`.
    CustomUserPreferences = {
      "com.apple.desktopservices".DSDontWriteNetworkStores = true;

      "com.apple.menuextra.clock".DateFormat = "yyyy-MM-dd (EEE)  H:mm:ss";

      # Force-click + haptic feedback (the trackpad domain ships in
      # both wired and Bluetooth variants; both need the override).
      "com.apple.AppleMultitouchTrackpad".ForceSuppressed = 0;
      "com.apple.driver.AppleBluetoothMultitouch.trackpad".ForceSuppressed = 0;
    };
  };
}
