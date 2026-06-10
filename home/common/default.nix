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

    initContent = ''
      # Treat `/` as a word boundary so M-Bksp / M-f / M-b stop at each
      # path component instead of swallowing the whole path.
      WORDCHARS=''${WORDCHARS//\//}

      # $TMUX leaks when a GUI app is launched via `open -a` from a
      # tmux-bound shell — the var propagates to the app, then to
      # every child shell it spawns, even though those shells have no
      # real tmux ancestor. Without this guard the auto-attach block
      # below sees $TMUX set and skips, leaving a bare shell. Walk
      # parent PIDs; if no tmux ancestor is found, the value is stale.
      if [[ -n "$TMUX" ]]; then
        local _pid=$PPID _in_tmux=0
        while [[ "$_pid" -gt 1 ]]; do
          case "$(ps -p "$_pid" -o comm= 2>/dev/null)" in
            *tmux*) _in_tmux=1; break ;;
          esac
          _pid=$(ps -p "$_pid" -o ppid= 2>/dev/null | tr -d ' ')
          [[ -z "$_pid" ]] && break
        done
        (( _in_tmux )) || unset TMUX TMUX_PANE
        unset _pid _in_tmux
      fi

      # Auto-attach (or create) a tmux session for new interactive
      # shells. `exec` replaces the shell so exiting tmux closes the
      # terminal. Escape hatch: `NO_AUTO_TMUX=1 zsh` skips the launch
      # for one-off shells that need to stay bare.
      # Skip inside VSCode's / Cursor's integrated terminal — its UI
      # already provides tab/split management and tmux's status bar
      # just steals vertical space there.
      if [[ -z "$TMUX" ]] && [[ -z "$NO_AUTO_TMUX" ]] && [[ "$TERM_PROGRAM" != "vscode" ]] && command -v tmux >/dev/null; then
        # Reconcile the running tmux server's loaded conf state
        # against what's on disk. Two failure modes covered:
        # - boot-race partial load: the conf parse halts before
        #   reaching its last line (@loaded != "1"). The conf sets
        #   @loaded on its last line as a parse-completion marker.
        # - stale conf after darwin-rebuild switch: the rendered
        #   conf has changed but the running server still holds
        #   the previous version's settings. ~/.config/tmux/tmux.conf
        #   is a symlink whose target changes to a new /nix/store
        #   path whenever the conf content changes; that target is
        #   the version identity. Stored in @conf-id by zsh below.
        # When no server is running, start it explicitly so @conf-id
        # can be set before any client attaches — that avoids a
        # spurious re-source on the next shell after a clean boot.
        local _expected=$(readlink ~/.config/tmux/tmux.conf 2>/dev/null)
        if tmux info >/dev/null 2>&1; then
          local _loaded=$(tmux show-options -gv @loaded 2>/dev/null)
          local _conf_id=$(tmux show-options -gv @conf-id 2>/dev/null)
          local _need=0
          [[ "$_loaded" != "1" ]] && _need=1
          [[ -n "$_expected" && "$_expected" != "$_conf_id" ]] && _need=1
          if (( _need )); then
            tmux source-file ~/.config/tmux/tmux.conf 2>/dev/null
            [[ -n "$_expected" ]] && tmux set-option -g @conf-id "$_expected" 2>/dev/null
          fi
          unset _loaded _conf_id _need
        else
          tmux start-server
          [[ -n "$_expected" ]] && tmux set-option -g @conf-id "$_expected" 2>/dev/null
        fi
        unset _expected
        exec tmux new-session -A -s main
      fi

      # Fuzzy-pick a ghq-managed repo and cd into it.
      gl() {
        local repo
        repo=$(ghq list --full-path | fzf --layout=reverse --preview "cat {}/README.*")
        [[ -n "$repo" ]] && cd "$repo"
      }

      # `gw` worktree manager (see zsh/gw.zsh for the implementation).
      source ${./zsh/gw.zsh}

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
      if-shell '[ -n "$SSH_CONNECTION" ] || [ -n "$SSH_TTY" ]' {
        set -g prefix C-u
        bind-key C-u send-prefix
        # Explicitly neutralise C-o so the default `prefix + C-o =
        # rotate-window` does not leak into the SSH override.
        bind-key C-o run-shell "true"

        set -g status-style fg=colour255,bg=colour52
        set -g status-left " 🌐 #h  W-#I P-#P #[fg=green]#{=40:pane_title}"
        set -g status-right "#{prefix_highlight} #{battery_icon} #{battery_percentage} #{online_status} %Y-%m-%d(%a) %H:%M "

        set -g pane-border-style fg=colour167,bg=colour52
        set -g pane-active-border-style fg=colour209,bg=colour88
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
    '' + lib.optionalString pkgs.stdenv.isDarwin ''

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

  # Keep program messages in English even though the rest of the
  # locale is ja_JP.UTF-8, so error output from sh / coreutils / git
  # is greppable and matches upstream docs.
  home.sessionVariables = {
    LC_MESSAGES = "C";
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

    (llm-agents.claude-code.override { disableTelemetry = false; })
    llm-agents.codex
  ];
}
