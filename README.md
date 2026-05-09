# nix-config

Multi-platform Nix + Home Manager configuration for macOS (nix-darwin + Home Manager) and Linux (Home Manager standalone).

## Repository layout

- `flake.nix` — flake entry point. Discovers hosts dynamically from `private/hosts/`, so no host names appear in this public repository.
- `lib/mkHost.nix` — helpers that wire host metadata + modules into Home Manager / nix-darwin configurations.
- `home/{common,linux,darwin}/` — Home Manager modules grouped by platform. Public defaults live here.
- `private/` — Git submodule pointing to a separate private repository. Holds per-host configurations and encrypted secrets. Not part of this public repo.

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

### Bootstrapping a new machine

1. Clone with submodules: `git clone --recurse-submodules <url>`.
2. Configure `rbw`: `rbw config set email <bitwarden-email>`, then `rbw login`.
3. Set up the host's `age` identity:
   - First-time setup: convert `~/.ssh/id_ed25519` into an `age` identity via [`ssh-to-age`](https://github.com/Mic92/ssh-to-age).
   - Recovery: fetch the saved recovery `age` private key from Bitwarden and place it where `agenix` expects it.
4. Run `home-manager switch --flake .#<user>@<host>`.

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
