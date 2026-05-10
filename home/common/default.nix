{ lib, pkgs, ... }:
{
  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    lfs.enable = true;

    settings = {
      user = {
        name = lib.mkDefault "Yuichiro Tachibana (Tsuchiya)";
        email = lib.mkDefault "t.yic.yt@gmail.com";
      };

      core.editor = "vi";

      init = {
        templatedir = "~/.git_template";
        defaultBranch = "main";
      };

      push = {
        default = "simple";
        autoSetupRemote = true;
      };

      ghq.root = [ "~/go/src" "~/ghq" ];

      credential = {
        "https://dev.azure.com".useHttpPath = true;
        "https://huggingface.co".provider = "generic";
      };

      sendemail = {
        smtpServer = "smtp.gmail.com";
        smtpServerPort = 587;
        smtpEncryption = "tls";
        smtpUser = "t.yic.yt@gmail.com";
      };

      alias = {
        st = "status";
        co = "checkout";
        br = "branch";
        # 'sw' is harder to type than 'si', so this aliases switch to 'si'.
        si = "switch";
        rs = "restore";
        re = "reset";
        rb = "rebase";
        cm = "commit";
        lg = "log --graph --branches --pretty=format:'%C(yellow)%h%C(cyan)%d%Creset %s %C(green)- %an, %cr%Creset'";
        ll = ''log --pretty=format:"%C(yellow)%h%Cred%d\\ %Creset%s%Cblue\\ [%cn]" --decorate --numstat'';
        # Adapted from http://qiita.com/awakia/items/f14dc6310e469964a8f7
        showpr = ''!f() { git log --merges --oneline --reverse --ancestry-path $1...master | grep 'Merge pull request #' | head -n 1; }; f'';
        del-merged-branches = ''!f() { git checkout $1; git branch --merged | egrep -v '^\\*|master|develop|release*' | xargs git branch -d; }; f'';
      };
    };

    ignores = [
      "*~"
      ".DS_Store"
      ".envrc"
      "**/.claude/settings.local.json"
    ];
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

    initExtra = ''
      # Fuzzy-pick a ghq-managed repo and cd into it.
      gl() {
        local repo
        repo=$(ghq list --full-path | fzf --layout=reverse --preview "cat {}/README.*")
        [[ -n "$repo" ]] && cd "$repo"
      }

      # Aikido Safe Chain wraps npm/yarn/pnpm to block known-malicious
      # packages. Its init script is laid down by safe-chain's own
      # installer (outside of this Nix config); source it if present.
      [[ -f ~/.safe-chain/scripts/init-zsh.zsh ]] && source ~/.safe-chain/scripts/init-zsh.zsh

      # micromamba: drop-in for `conda activate` style env management.
      if command -v micromamba >/dev/null 2>&1; then
        export MAMBA_EXE="$(command -v micromamba)"
        export MAMBA_ROOT_PREFIX="$HOME/.local/share/mamba"
        eval "$(micromamba shell hook --shell zsh)"
      fi
    '';
  };

  programs.starship = {
    enable = true;
    settings = {
      custom.datetime = {
        command = ''date +"%Y-%m-%d %H:%M:%S"'';
        when = "true";
        format = "[$output](bold yellow) ";
      };
    };
  };

  programs.tmux = {
    enable = true;

    prefix = lib.mkDefault "C-o";
    baseIndex = 1;
    escapeTime = 0;
    mouse = true;
    terminal = "tmux-256color";

    plugins = with pkgs.tmuxPlugins; [
      sensible
      battery
      online-status
      prefix-highlight
      resurrect
      {
        plugin = continuum;
        extraConfig = "set -g @continuum-restore 'on'";
      }
    ];

    extraConfig = ''
      bind-key c new-window -a

      set -g focus-events on
      set-option -g renumber-windows on
      setw -g pane-base-index 1

      bind r source-file ~/.config/tmux/tmux.conf \; display "Reloaded!"

      bind 3 split-window -h -c "#{pane_current_path}"
      bind 2 split-window -v -c "#{pane_current_path}"

      bind-key -n C-S-Left  swap-window -t -1\; select-window -t -1
      bind-key -n C-S-Right swap-window -t +1\; select-window -t +1

      # True color (RGB) — depends on the outer terminal supporting it
      set -as terminal-features ",*:RGB"

      # Synchronized output to suppress flicker / tearing
      set -as terminal-features ",tmux-256color:sync"

      # Let inner programs forward their own escape sequences (e.g. OSC 52 from a nested shell)
      set -g allow-passthrough on

      # OSC 52 clipboard: tmux forwards copies to the outer terminal,
      # which lands them in the system clipboard. Works through SSH so
      # nested-tmux copy still reaches the local Mac clipboard.
      set -s set-clipboard on
      set -as terminal-features ",*:clipboard"

      set -g default-shell ${pkgs.zsh}/bin/zsh

      setw -g status-style fg=colour255,bg=colour234
      setw -g window-status-style fg=cyan,bg=default,dim
      setw -g window-status-current-style fg=white,bright,bg=colour170
      set -g pane-border-style fg=colour111,bg=colour236
      set -g pane-active-border-style fg=colour227,bg=colour240
      set -g message-style fg=white,bg=black,bright

      set -g status-left-length 40
      set -g status-left "#[fg=yellow]W-#I #[fg=cyan]P-#P"
      set -g @online_icon "🛜"
      set -g @offline_icon "💔"
      set -g status-right '#{prefix_highlight}#[fg=colour59, bg=colour234]#[fg=brightwhite, bg=colour59] #{battery_icon} #{battery_percentage} #{online_status}#[fg=colour234, bg=colour59] #[fg=colour59, bg=colour234]#[fg=brightwhite, bg=colour59] %Y-%m-%d(%a) %H:%M '
      set -g status-interval 10
      set -g status-justify centre
      setw -g monitor-activity on
      set -g visual-activity off
      set -g status-position top

      bind-key -T copy-mode             C-w               send-keys -X copy-selection-and-cancel \; display "Copied"
      bind-key -T copy-mode             MouseDragEnd1Pane send-keys -X copy-selection-and-cancel \; display "Copied"

      # SSH overrides — kept at the end of extraConfig so the
      # conditional values win over the unconditional defaults above.
      # When tmux is started from an SSH session, swap the prefix and
      # restyle the status bar so this session doesn't collide with —
      # or look identical to — an outer tmux on the originating
      # machine.
      if-shell '[ -n "$SSH_CONNECTION" ] || [ -n "$SSH_TTY" ]' {
        set -g prefix C-q
        unbind C-o
        bind-key C-q send-prefix

        set -g status-style fg=colour255,bg=colour52
        set -g status-left " 🌐 #h  W-#I P-#P "
        set -g status-right "#{prefix_highlight} #{battery_icon} #{battery_percentage} #{online_status} %Y-%m-%d(%a) %H:%M "

        set -g pane-border-style fg=colour167,bg=colour52
        set -g pane-active-border-style fg=colour209,bg=colour88
      }
    '' + lib.optionalString pkgs.stdenv.isDarwin ''

      # macOS-only paste binding. On Linux there is no portable
      # equivalent of pbpaste, so we rely on the terminal's own paste
      # (Cmd-V / Ctrl-Shift-V), which goes through OSC 52.
      bind C-y run "pbpaste | tmux load-buffer - && tmux paste-buffer"
    '';
  };
  programs.fzf.enable = true;
  programs.eza.enable = true;
  programs.zoxide.enable = true;
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  programs.mise.enable = true;

  # micromamba does not auto-create its root prefix when missing, so
  # the first `micromamba env create` errors out on a fresh machine.
  # Pre-create it once at activation time.
  home.activation.createMambaRootPrefix = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.local/share/mamba"
  '';

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

    uv
    micromamba

    (llm-agents.claude-code.override { disableTelemetry = false; })
    llm-agents.codex
  ];
}
