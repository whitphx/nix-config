{ pkgs, ... }:
{
  home.packages = with pkgs; [
    coreutils
  ];

  programs.zsh.shellAliases.intelzsh = "arch -x86_64 zsh";

  programs.git.settings.credential.helper = [ "osxkeychain" ];

  # Source Homebrew for HOMEBREW_PREFIX / MANPATH / INFOPATH, then push
  # /opt/homebrew/{bin,sbin} to the back of $path so Nix-managed
  # binaries win lookups (`brew shellenv` prepends them by default).
  programs.zsh.profileExtra = ''
    eval "$(/opt/homebrew/bin/brew shellenv)"
    path=("''${(@)path:#/opt/homebrew/(bin|sbin)}" /opt/homebrew/bin /opt/homebrew/sbin)
  '';
}
