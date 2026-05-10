{ pkgs, ... }:
{
  home.packages = with pkgs; [
    coreutils
    git-credential-manager
  ];

  programs.zsh.shellAliases.intelzsh = "arch -x86_64 zsh";

  programs.git.settings.credential = {
    helper = [ "manager" ];
    "https://github.com" = {
      provider = "github";
      username = "whitphx";
    };
  };

  # Source Homebrew for HOMEBREW_PREFIX / MANPATH / INFOPATH, then push
  # /opt/homebrew/{bin,sbin} to the back of $path so Nix-managed
  # binaries win lookups (`brew shellenv` prepends them by default).
  programs.zsh.profileExtra = ''
    eval "$(/opt/homebrew/bin/brew shellenv)"
    path=("''${(@)path:#/opt/homebrew/(bin|sbin)}" /opt/homebrew/bin /opt/homebrew/sbin)
  '';
}
