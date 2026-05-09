{ lib, pkgs, ... }:
{
  programs.git = {
    enable = true;
    lfs.enable = true;
    settings.user = {
      name = lib.mkDefault "Yuichiro Tachibana (Tsuchiya)";
      email = lib.mkDefault "t.yic.yt@gmail.com";
    };
  };

  programs.zsh.enable = true;
  programs.tmux.enable = true;
  programs.fzf.enable = true;
  programs.eza.enable = true;
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  home.packages = with pkgs; [
    ghq
    gibo
    gitleaks
    jq
    zsh-completions
    ffmpeg
    nkf
    pwgen
    wget
    rbw
  ];
}
