{ pkgs, ... }:
{
  home.packages = with pkgs; [
    coreutils
  ];

  programs.zsh.shellAliases.intelzsh = "arch -x86_64 zsh";

  programs.git.settings.credential.helper = [ "osxkeychain" ];
}
