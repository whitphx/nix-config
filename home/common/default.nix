{ config, lib, pkgs, llm-agents, ... }:
let
  # The shared half of the shell setup, with the one per-site path in it
  # filled from config (see model-cache.nix).
  commonShell = pkgs.writeText "shell-common.sh" (builtins.replaceStrings
    [ "@modelCacheDir@" ]
    [ config.myEnv.modelCacheDir ]
    (builtins.readFile ./shell/common.sh));
in
{
  imports = [ ./model-cache.nix ];

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
      "**/.claude/*.local.*"
    ];
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    completionInit = ''
      autoload -Uz compinit
      zmodload zsh/datetime
      zmodload zsh/stat

      typeset -A _zcompdump_stat
      local _zcompdump="''${ZDOTDIR:-$HOME}/.zcompdump"
      # Periodic full initialization discovers newly installed completions and
      # reruns compaudit instead of trusting the cached definitions forever.
      if [[ ! -s "$_zcompdump" ]] \
         || ! zstat -H _zcompdump_stat +mtime "$_zcompdump" 2>/dev/null \
         || (( EPOCHSECONDS - _zcompdump_stat[mtime] > 86400 )); then
        compinit -d "$_zcompdump"
      else
        # The dump already records the completion definitions, so avoid
        # rescanning every completion file until the next refresh.
        compinit -C -d "$_zcompdump"
      fi
      unset _zcompdump _zcompdump_stat
    '';
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

    initContent = ''
      # Treat `/` as a word boundary so M-Bksp / M-f / M-b stop at each
      # path component instead of swallowing the whole path. Bash's
      # readline already breaks words there.
      WORDCHARS=''${WORDCHARS//\//}

      source ${commonShell}

      # `gw` worktree manager (see shell/gw.sh for the implementation).
      source ${./shell/gw.sh}

      autoload -Uz add-zsh-hook
      add-zsh-hook precmd _restore-term-state
    '';
  };

  # Zsh is the shell we live in, but some hosts hand us a bash login
  # shell and some tools spawn one, so bash gets the same environment.
  # The portable half lives in shell/common.sh, sourced by both.
  programs.bash = {
    enable = true;

    historySize = 50000;
    historyFileSize = 50000;
    historyControl = [ "ignoredups" "ignorespace" "erasedups" ];

    initExtra = ''
      # Timestamps in the history file, as zsh's extended history keeps.
      HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S "

      source ${commonShell}

      # `gw` worktree manager (see shell/gw.sh for the implementation).
      source ${./shell/gw.sh}

      # `history -a` then `history -n` are the two halves of zsh's shared
      # history: flush what this shell just ran, then read what the other
      # shells appended. The other PROMPT_COMMAND hooks in this file
      # preserve an existing value, so this survives wherever it lands
      # relative to them.
      PROMPT_COMMAND="_restore-term-state; history -a; history -n''${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
    '';
  };

  programs.starship = {
    enable = true;
    settings = {
      scan_timeout = 10;
      # `$all` probes every contextual module on each redraw. Keep the prompt
      # limited to the shell, environment, and repository state used here.
      format = lib.concatStrings [
        "$username"
        "$hostname"
        "$directory"
        "$git_branch"
        "$git_status"
        "$nix_shell"
        "$conda"
        "$direnv"
        "$mise"
        "$gcloud"
        "$time"
        "$cmd_duration"
        "$line_break"
        "$character"
      ];
      # A custom clock command would fork `date` for every prompt redraw.
      time = {
        disabled = false;
        time_format = "%Y-%m-%d %H:%M:%S";
        format = "[$time](bold yellow) ";
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
      bind-key C command-prompt -p "New session name:" "new-session -s '%%'"

      set -g focus-events on
      set-option -g renumber-windows on
      setw -g pane-base-index 1

      # Closing the last window of a session normally detaches the
      # client; with `exec tmux` in shell init that exits the terminal.
      # Switch to the most recently active surviving session instead;
      # only fall back to detach when no other sessions exist.
      set -g detach-on-destroy off

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
      setw -g window-status-current-style fg=white,bold,bg=colour170
      set -g pane-border-style fg=colour111,bg=colour236
      set -g pane-active-border-style fg=colour227,bg=colour240
      set -g message-style fg=white,bg=black,bold

      set -g status-left-length 80
      set -g status-left "#[fg=yellow]W-#I #[fg=cyan]P-#P #[fg=green]#{=40:pane_title}"
      set -g @online_icon "🛜"
      set -g @offline_icon "💔"
      set -g status-right '#{prefix_highlight}#[fg=colour59, bg=colour234]#[fg=brightwhite, bg=colour59] #{battery_icon} #{battery_percentage} #{online_status}#[fg=colour234, bg=colour59]#[fg=colour59, bg=colour234]#[fg=brightwhite, bg=colour59] %Y-%m-%d(%a) %H:%M '
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
      # Shared prefix-swap + status/border restyle live in the neutral
      # ../tmux-ssh-overrides.conf (also used by the host tmux on
      # nix-user-chroot hosts). Only status-right is host-tmux-specific;
      # this one uses the nix plugin widgets.
      if-shell '[ -n "$SSH_CONNECTION" ] || [ -n "$SSH_TTY" ]' {
      ${builtins.readFile ../tmux-ssh-overrides.conf}
        set -g status-right "#{prefix_highlight} #{battery_icon} #{battery_percentage} #{online_status} %Y-%m-%d(%a) %H:%M "
      }

      # battery / online-status / prefix-highlight rewrite the active
      # `status-right` at load time to substitute `#{battery_icon}` etc.
      # with `#(/path/to/script.sh)`. HM's `programs.tmux.plugins` emits
      # their `run-shell` lines BEFORE this `extraConfig`, so when they
      # fired the status-right we set above didn't exist yet. Re-run
      # them here so the substitution actually takes effect.
      run-shell ${pkgs.tmuxPlugins.battery}/share/tmux-plugins/battery/battery.tmux
      run-shell ${pkgs.tmuxPlugins.online-status}/share/tmux-plugins/online-status/online_status.tmux
      run-shell ${pkgs.tmuxPlugins.prefix-highlight}/share/tmux-plugins/prefix-highlight/prefix_highlight.tmux
    '' + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''

      # macOS-only paste binding. On Linux there is no portable
      # equivalent of pbpaste, so we rely on the terminal's own paste
      # (Cmd-V / Ctrl-Shift-V), which goes through OSC 52.
      bind C-y run "pbpaste | tmux load-buffer - && tmux paste-buffer"
    '' + ''

      # Load-completed sentinel. zsh init probes this and re-sources
      # the conf when it's missing — catches any halted load (boot-
      # race, an earlier line erroring out, etc.) without depending
      # on a specific option as the canary.
      set -g @loaded "1"
    '';
  };
  programs.fzf.enable = true;
  programs.eza.enable = true;
  programs.zoxide.enable = true;
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  programs.mise = {
    enable = true;
    globalConfig = {
      tools = {
        node = "22";
        pnpm = "10";
      };
      settings = {
        # Read legacy version files (.nvmrc, .terraform-version, …) the
        # way nvm/tfenv/asdf did, so existing repos don't need a
        # .mise.toml.
        idiomatic_version_file_enable_tools = [ "node" ];
        # Install missing tools transparently the first time a shell
        # sees them required, instead of failing loudly and waiting for
        # a manual `mise install`.
        not_found_auto_install = true;
      };
    };
  };

  # Pre-install whatever the global mise config declares at activation
  # time, so `darwin-rebuild switch` leaves node/pnpm/etc. on disk
  # without waiting for the next interactive shell. `mise install` with
  # no args reads the rendered config and is idempotent across re-runs.
  home.activation.miseInstall = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -x "${pkgs.mise}/bin/mise" ]; then
      "${pkgs.mise}/bin/mise" install --yes || true
    fi
  '';

  # Keep CLI output consistent with upstream documentation regardless of the
  # desktop language. LC_ALL also covers date and time formatting used by ps.
  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };

  # micromamba does not auto-create its root prefix when missing, so
  # the first `micromamba env create` errors out on a fresh machine.
  # Pre-create it once at activation time.
  home.activation.createMambaRootPrefix = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.local/share/mamba"
  '';

  # Suppress the "(envname)" PS1 prefix that micromamba activate
  # injects. Starship's [conda] module already surfaces the active
  # env in the prompt, so the prefix is just visual noise.
  home.file.".mambarc".text = ''
    changeps1: false
  '';

  home.packages = with pkgs; [
    ghq
    gibo
    gitleaks
    jq
    ripgrep
    tree
    zsh-completions
    ffmpeg
    nkf
    pwgen
    wget
    rbw
    bitwarden-cli
    cloudflared
    ngrok

    uv
    micromamba
    ni

    actionlint
    pinact
    chezmoi
    cmake
    emacs
    gh
    lefthook
    miniserve
    protobuf

    hackgen-font
    hackgen-nf-font

    # Ships the `hf` / `huggingface-cli` commands; nixpkgs has no
    # standalone CLI attribute for them.
    python3Packages.huggingface-hub

    (llm-agents.claude-code.override { disableTelemetry = false; })
    llm-agents.codex
  ];
}
