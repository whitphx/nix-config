#!/usr/bin/env bash
# Nix resolves the `private` submodule from its remote whenever this
# working tree is clean, so a commit that bumps the pointer to a revision
# that only exists locally breaks every evaluation on every host:
#
#   error: Cannot find Git revision '<rev>' in ref 'refs/heads/main'
#
# The failure surfaces at `home-manager switch`, far from the commit that
# caused it, so check at commit and push time instead.
set -u

repo_root=$(git rev-parse --show-toplevel) || exit 0
cd "$repo_root" || exit 0

rev=$(git rev-parse HEAD:private 2>/dev/null) || exit 0
[ -d private/.git ] || [ -f private/.git ] || exit 0

# A stale remote-tracking ref would fail a revision that is in fact
# pushed, so refresh it first. Offline, fall back to whatever is known.
git -C private fetch --quiet origin 2>/dev/null

if git -C private merge-base --is-ancestor "$rev" origin/main 2>/dev/null; then
  exit 0
fi

cat >&2 <<MSG
private submodule revision $rev is not on origin/main.

  Nix fetches the submodule from its remote, so this revision has to be
  pushed before anything can evaluate this commit:

      git -C private push

MSG
exit 1
