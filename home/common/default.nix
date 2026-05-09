{ lib, pkgs, ... }:
{
  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    lfs.enable = true;
    settings.user = {
      name = lib.mkDefault "Yuichiro Tachibana (Tsuchiya)";
      email = lib.mkDefault "t.yic.yt@gmail.com";
    };
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history = {
      size = 50000;
      save = 50000;
      share = true;
      ignoreDups = true;
      ignoreSpace = true;
      expireDuplicatesFirst = true;
      extended = true;
    };
    shellAliases = { };
    shellGlobalAliases = { };
    plugins = [
      {
        name = "fzf-tab";
        src = pkgs.zsh-fzf-tab;
        file = "share/fzf-tab/fzf-tab.plugin.zsh";
      }
    ];
  };

  programs.starship.enable = true;

  programs.tmux.enable = true;
  programs.fzf.enable = true;
  programs.eza.enable = true;
  programs.zoxide.enable = true;
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
