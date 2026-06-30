# nix-config

Multi-platform Nix + Home Manager configuration for **macOS** (nix-darwin + Home Manager) and **Linux** (Home Manager standalone, run inside a rootless chroot via [`nix-user-chroot`](https://github.com/nix-community/nix-user-chroot) for hosts where you don't have root).

## Repository layout

- `flake.nix` — flake entry point. Discovers hosts dynamically from `private/hosts/`, so no host names appear in this public repository.
- `lib/mkHost.nix` — helpers that wire host metadata + modules into Home Manager / nix-darwin configurations.
- `home/{common,linux,darwin}/` — Home Manager modules grouped by platform. Public defaults live here.
- `system/darwin/` — nix-darwin system-level modules (Dock, Finder, keyboard remap, Control Center toggles, etc.). macOS only.
- `private/` — Git submodule pointing to a separate private repository. Holds per-host configurations and encrypted secrets. Not part of this public repo.

## Bootstrapping

Two flavors of fresh install: macOS via nix-darwin, Linux via Home Manager standalone. Both share the secret-store setup, which is described separately under [Secret management](#secret-management).

### macOS

1. **Install the Xcode Command Line Tools** (provides `git`, `clang`, etc. needed by Nix builds):

    ```bash
    xcode-select --install
    ```

2. **Install Determinate Nix** — follow the upstream [installation instructions](https://github.com/DeterminateSystems/nix-installer#install-nix). Open a new shell when it's done so `/nix/var/nix/profiles/default/bin` is on PATH.

3. **Clone with submodules**:

    ```bash
    git clone --recurse-submodules git@github.com:whitphx/nix-config.git
    cd nix-config
    ```

4. **Define a host** under `private/hosts/<host-nickname>/`. The directory name is what you'll pass to `--flake .#<nickname>`:

    `default.nix`:

    ```nix
    {
      kind = "darwin";
      system = "aarch64-darwin";  # or x86_64-darwin on Intel
      username = "<your-mac-user>";
      homeDirectory = "/Users/<your-mac-user>";
    }
    ```

    `home.nix` (start empty; layer host-specific overrides later):

    ```nix
    { ... }: { }
    ```

    Commit + push these new files in the `private/` submodule, then stage the bump in the parent repo. Nix's flake evaluation fetches the submodule from its remote (not the working tree alone), so the new host directory must be reachable on origin before the first switch:

    ```bash
    git -C private checkout main && git -C private add hosts/<host-nickname>
    git -C private commit -m "Add <host-nickname> host"
    git -C private push
    git add private  # stage the new submodule pointer; commit when convenient
    ```

5. **(Optional)** Set up secret stores per [Secret management](#secret-management) below. If your host's `home.nix` is empty, you can defer this until the first secret lands.

6. **Load your SSH key into the agent** before the first activation. Nix evaluates the flake with `self.submodules = true`, so even under `sudo` it fetches `private/` from GitHub over SSH; if the key isn't already in the running agent — only on disk — the `sudo`'d fetch fails even when plain `git pull` as you works fine.

    ```bash
    ssh-add ~/.ssh/id_ed25519
    # Or, to persist the key across shells via macOS Keychain:
    # ssh-add --apple-use-keychain ~/.ssh/id_ed25519
    ```

7. **First activation** (`darwin-rebuild` doesn't exist on PATH yet — it ships *via* the activation):

    ```bash
    sudo nix run nix-darwin -- switch --flake .#<host-nickname>
    ```

    Open a new shell afterward so the activated PATH (Nix profile, HM-managed binaries, `darwin-rebuild`) is picked up.

8. **Subsequent rebuilds**:

    ```bash
    sudo darwin-rebuild switch --flake .#<host-nickname>
    ```

### Linux (rootless via `nix-user-chroot`)

These steps target a host where you don't have root and so can't install Nix the normal way. [`nix-user-chroot`](https://github.com/nix-community/nix-user-chroot) uses user namespaces to bind-mount a user-owned directory as `/nix`, letting Nix run with no system-level changes.

1. **Install `nix-user-chroot` and Nix inside it** — follow upstream's [installation instructions](https://github.com/nix-community/nix-user-chroot#installation). Use single-user mode when installing Nix; the daemon variant needs real root.

2. **Enter the chroot** — required for every step below and for any future Nix-related work on this host:

    ```bash
    nix-user-chroot ~/.nix bash
    ```

    Consider aliasing.

3. **Enable flakes** in `~/.config/nix/nix.conf` (inside the chroot):

    ```
    experimental-features = nix-command flakes
    ```

4. **Clone with submodules** (inside the chroot):

    ```bash
    git clone --recurse-submodules git@github.com:whitphx/nix-config.git
    cd nix-config
    ```

5. **Define a host** under `private/hosts/<host-nickname>/`.

    `default.nix`:

    ```nix
    {
      kind = "linux";
      system = "x86_64-linux";  # or aarch64-linux
      username = "<your-user>";
      homeDirectory = "<your-home-dir>";  # e.g. /home/you
    }
    ```

    `home.nix`: `{ ... }: { }`

    Commit + push the submodule and bump the pointer in the parent — same flow as macOS step 4.

6. **(Optional)** Secret-store setup per [Secret management](#secret-management).

7. **First activation**:

    ```bash
    nix run home-manager/master -- switch --flake .#<your-user>@<host-nickname>
    ```

8. **Subsequent rebuilds**:

    ```bash
    home-manager switch --flake .#<your-user>@<host-nickname>
    ```

    Remember: each new login shell starts outside the chroot — re-enter with `nix-user-chroot ~/.nix bash` (or your alias) before running `home-manager`.

## Chezmoi-managed dotfiles

Home Manager installs `chezmoi`, but does not clone or apply the dotfiles repository during activation. Keep that step explicit so rebuilds do not depend on GitHub auth, Bitwarden template expansion, or live `$HOME` mutations.

On a fresh machine, after the first Nix activation has put `chezmoi` on PATH:

```bash
chezmoi init --apply git@github.com:whitphx/dotfiles.git
```

This initializes Chezmoi's default source directory at `~/.local/share/chezmoi`. If the repository is already cloned there, `chezmoi cd`, `chezmoi diff`, and `chezmoi apply` will use it automatically.

Ownership rule:

- Nix owns stable machine policy: packages, shells, tmux/starship, Git defaults, macOS defaults, fonts, and other activation-time system state.
- Chezmoi owns live-edited personal files and package-manager credential templates: `.claude/`, `.codex/`, `.github/hooks/`, `.npmrc`, pip/uv/pnpm registry config, and small scripts that are edited in place.

## Secret management

This repository is public, but the configurations it produces depend on values that must not be. Secret material is split across three layers, each with a distinct role:

| Layer | Where | What it holds |
|---|---|---|
| Public | this repository | Cross-platform modules, public defaults, repository structure. **Never** contains secrets. |
| Private submodule | `private/` (separate private repo) | Per-host configurations and `agenix`-encrypted secret files. |
| Bitwarden | external password manager | Recovery `age` identity (for bootstrapping a fresh machine or recovering a lost host key) and ad-hoc runtime secrets that don't need to materialize at activation time. |

### Tools

- **[`agenix`](https://github.com/ryantm/agenix)** — encrypts secrets in the private submodule with `age`, decrypts them at Home Manager activation time. Used for secrets that must materialize as files (e.g., `~/.npmrc`, `~/.ssh/config` snippets).
- **[`rbw`](https://github.com/doy/rbw)** — Rust client for Bitwarden, faster and friendlier than the official `bw` CLI. Used by shell scripts and `.envrc` to fetch secrets at runtime.
- **[`direnv`](https://direnv.net/) + [`nix-direnv`](https://github.com/nix-community/nix-direnv)** — loads project-specific tooling (via `use flake`) and secrets when entering a directory.

### Setup on a fresh host

Run once per machine, before any `home.nix` that references encrypted/runtime secrets is activated:

1. **Configure `rbw`**:

    ```bash
    rbw config set email <bitwarden-email>
    rbw login
    ```

2. **Set up the host's `age` identity** (only if your `home.nix` uses agenix-encrypted files):
    - **First-time setup**: convert `~/.ssh/id_ed25519` into an age identity with [`ssh-to-age`](https://github.com/Mic92/ssh-to-age).
    - **Recovery**: fetch the saved recovery age private key from Bitwarden and place it where agenix expects it.

### `.envrc` policy

`.envrc` files **must not contain raw secret values**. They should only reference Bitwarden or `agenix`:

```bash
# .envrc — safe to commit
use flake

# Runtime secrets pulled from Bitwarden at shell entry
export GITHUB_TOKEN=$(rbw get github-token-personal)
export AWS_ACCESS_KEY_ID=$(rbw get -f username aws-dev)
export AWS_SECRET_ACCESS_KEY=$(rbw get aws-dev)

# Or source an agenix-decrypted env file
dotenv $HOME/.config/agenix/myproject.env
```

This keeps `.envrc` safe to commit alongside project source while still picking up the secrets it needs.

## Per-host overrides

Public defaults in `home/common/default.nix` are written with `lib.mkDefault`, so any per-host module under `private/hosts/<name>/home.nix` can override them with a plain assignment. For example, the public default for git identity:

```nix
# home/common/default.nix
programs.git.settings.user.name  = lib.mkDefault "...";
programs.git.settings.user.email = lib.mkDefault "...";
```

can be overridden on a work machine by:

```nix
# private/hosts/<name>/home.nix
programs.git.settings.user.name  = "...";
programs.git.settings.user.email = "work@example.com";
```
