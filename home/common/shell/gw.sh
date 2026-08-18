# Git worktree manager with fzf.
#
# Ported from a fish function inspired by:
#   https://github.com/hiroppy/dotfiles/blob/master/config/fish/functions/wt.fish
# Article: https://hiroppy.me/blog/posts/git-worktree-fish
#
# Subcommands:
#   gw                      Switch worktree (or add one if none exist)
#   gw switch               Switch worktree
#   gw add [branch]         Create worktree for branch (selector if omitted)
#   gw remove [branch|dir]  Remove worktree (selector if omitted)
#
# Worktrees live in ~/worktrees/<host>/<owner>/<repo>/ rather than under
# .git/, because some tools (e.g. the Vite dev server) refuse to read
# files inside `.git`.
#
# Sourced by both zsh and bash, so it sticks to syntax both accept: line
# generators feed `while read` loops over process substitution instead of
# zsh's `${(@f)}` splitting, and the two places where the shells genuinely
# differ (line-edited input, glob-from-a-variable) go through the shims
# below.

# Prompt for a value using the shell's own line editor, so the usual
# editing keys work while typing. Takes the prompt and the name of the
# variable to fill, which the caller declares.
__gw_read_edited() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    vared -p "$1" "$2"
  else
    read -e -r -p "$1" "$2"
  fi
}

# Emit files matching <dir>/<pattern>. Uses `find` rather than a glob
# because a pattern held in a variable expands in bash but not in zsh,
# and an unmatched glob is an error in zsh but a literal in bash.
__gw_glob() {
  local dir=$1 pattern=$2 name
  case "$pattern" in
    */*) dir="$dir/${pattern%/*}"; name=${pattern##*/} ;;
    *)   name=$pattern ;;
  esac
  find "$dir" -maxdepth 1 -type f -name "$name" 2>/dev/null
}

__gw_get_worktrees_dir() {
  local remote_url host owner_repo repo_root repo_name
  remote_url=$(git remote get-url origin 2>/dev/null)

  if [ -n "$remote_url" ]; then
    host=""
    owner_repo=""
    # Supported remote URL shapes:
    #   git@host:owner/repo(.git)?
    #   {https,ssh}://[user@]host/owner/repo(.git)?
    case "$remote_url" in
      git@*:*)
        host=$(echo "$remote_url" | sed -E 's|^git@([^:]+):.*|\1|')
        owner_repo=$(echo "$remote_url" | sed -E 's|^git@[^:]+:||; s|\.git$||')
        ;;
      *://*)
        host=$(echo "$remote_url" | sed -E 's|^[^/]+://([^@]+@)?([^/]+)/.*|\2|')
        owner_repo=$(echo "$remote_url" | sed -E 's|^[^/]+://([^@]+@)?[^/]+/||; s|\.git$||')
        ;;
    esac

    if [ -n "$host" ] && [ -n "$owner_repo" ]; then
      echo "$HOME/worktrees/$host/$owner_repo"
      return
    fi
  fi

  repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  repo_name=$(basename "$repo_root")
  echo "$HOME/worktrees/_local/$repo_name"
}

__gw_worktree_paths() {
  # Emits one absolute path per line, in `git worktree list` order
  # (main worktree first).
  git worktree list --porcelain | grep '^worktree ' | sed 's/^worktree //'
}

__gw_has_worktrees() {
  [ "$(__gw_worktree_paths | wc -l)" -gt 1 ]
}

__gw_preview_worktree() {
  # Preview script for fzf worktree pickers. Reads the selected line on
  # stdin via {} and renders branch, file changes, and recent commits.
  cat <<'SH'
sh -c '
    item="$1"
    if echo "$item" | grep -q "+ Add new worktree"; then
        echo "┌──────────────────────────────────────────────────┐"
        echo "│ ✨ Add NEW worktree"
        echo "└──────────────────────────────────────────────────┘"
        echo ""
        echo "Select this option to choose a branch and create a new worktree."
        exit 0
    fi
    worktree_path=$(echo "$item" | cut -f1)
    branch=$(echo "$item" | sed "s/.*\[//" | sed "s/\]//")

    echo "┌──────────────────────────────────────────────────┐"
    echo "│ 🌳 Branch: $branch"
    echo "└──────────────────────────────────────────────────┘"
    echo ""
    echo "📁 Path: $worktree_path"
    echo ""
    echo "📝 Changed files:"
    echo "───────────────────────────────────────────────────"
    changes=$(git -C "$worktree_path" status --porcelain 2>/dev/null)
    if [ -z "$changes" ]; then
        echo "  ✨ Working tree clean"
    else
        echo "$changes" | head -10 | while read line; do
            file_status=$(echo "$line" | cut -c1-2)
            file_name=$(echo "$line" | cut -c4-)
            case "$file_status" in
                "M "*) echo "  🔧 Modified: $file_name";;
                "A "*) echo "  ➕ Added: $file_name";;
                "D "*) echo "  ➖ Deleted: $file_name";;
                "??"*) echo "  ❓ Untracked: $file_name";;
                *) echo "  📄 $line";;
            esac
        done
    fi
    echo ""
    echo "📜 Recent commits:"
    echo "───────────────────────────────────────────────────"
    git -C "$worktree_path" log --oneline --color=always -10 2>/dev/null | sed "s/^/  /"
' _ {}
SH
}

__gw_preview_branch() {
  cat <<'SH'
sh -c '
    item="$1"
    if echo "$item" | grep -q "^+ Create new branch"; then
        echo "┌──────────────────────────────────────────────────┐"
        echo "│ ✨ Create NEW branch"
        echo "└──────────────────────────────────────────────────┘"
        echo ""
        echo "Select this option to enter a new branch name."
        echo "The new branch will be created from the current HEAD."
    else
        branch=$(echo "$item" | sed "s|^origin/||")
        echo "┌──────────────────────────────────────────────────┐"
        echo "│ 🌳 Branch: $branch"
        echo "└──────────────────────────────────────────────────┘"
        echo ""
        echo "📜 Recent commits:"
        echo "───────────────────────────────────────────────────"
        git log --oneline --color=always -10 "$branch" 2>/dev/null \
            || git log --oneline --color=always -10 "origin/$branch" 2>/dev/null \
            | sed "s/^/  /"
    fi
' _ {}
SH
}

__gw_switch_interactive() {
  local worktrees_dir=$1

  local main_worktree current_worktree
  main_worktree=$(__gw_worktree_paths | head -1)
  current_worktree=$(pwd -P)

  # Marker line for "+ Add new worktree…". Leading TAB keeps the
  # tab-delimited shape so `--with-nth=2` still renders correctly.
  local add_worktree_marker=$'\t+ Add new worktree...'

  local fzf_input=()
  local wt_path branch relative_path current_marker
  while IFS= read -r wt_path; do
    branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ "$wt_path" = "$main_worktree" ]; then
      relative_path="."
    else
      relative_path=${wt_path#"$main_worktree"/}
    fi
    if [ "$wt_path" = "$current_worktree" ]; then
      current_marker="* "
    else
      current_marker="  "
    fi
    fzf_input+=( "${wt_path}"$'\t'"${current_marker}${relative_path} [${branch}]" )
  done < <(__gw_worktree_paths)

  if [ ${#fzf_input[@]} -eq 0 ]; then
    echo "No worktrees to switch to"
    return 1
  fi

  local preview_script
  preview_script=$(__gw_preview_worktree)

  local selected
  selected=$(printf '%s\n' "$add_worktree_marker" "${fzf_input[@]}" | fzf \
    --preview="$preview_script" \
    --preview-window="right:60%:wrap" \
    --header="Git Worktrees | Enter: switch" \
    --border \
    --height=80% \
    --layout=reverse \
    --delimiter=$'\t' \
    --with-nth=2)

  if [ -n "$selected" ]; then
    if [ "$selected" = "$add_worktree_marker" ]; then
      __gw_select_branch_and_create "$worktrees_dir"
    else
      local target_path=${selected%%$'\t'*}
      cd "$target_path"
      echo "Switched to: $target_path"
    fi
  fi
}

__gw_create_worktree() {
  local branch_name=$1
  local worktrees_dir=$2

  if [ -z "$branch_name" ]; then
    echo "Error: Branch name required"
    return 1
  fi

  [ -d "$worktrees_dir" ] || mkdir -p "$worktrees_dir"

  # Branch names can contain `/`; flatten to `-` for the on-disk dir.
  local dir_name=${branch_name//\//-}
  local worktree_path="$worktrees_dir/$dir_name"

  if [ -d "$worktree_path" ]; then
    echo "Worktree already exists at: $worktree_path"
    cd "$worktree_path"
    return 0
  fi

  if git show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null; then
    git worktree add "$worktree_path" "$branch_name"
  elif git show-ref --verify --quiet "refs/remotes/origin/$branch_name" 2>/dev/null; then
    git worktree add "$worktree_path" -b "$branch_name" "origin/$branch_name"
  else
    echo "Branch '$branch_name' does not exist. Creating new branch from HEAD."
    git worktree add -b "$branch_name" "$worktree_path"
  fi

  local rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "Failed to create worktree"
    return 1
  fi

  echo "Created worktree at: $worktree_path"

  # Seed the new worktree with developer-local files that git doesn't
  # track but every checkout still needs (env files, Claude per-repo
  # local settings, etc.).
  local copy_patterns=(
    ".env"
    ".claude/*.local.*"
  )

  local main_worktree
  main_worktree=$(__gw_worktree_paths | head -1)

  local pattern file relative_path target_dir
  for pattern in "${copy_patterns[@]}"; do
    while IFS= read -r file; do
      relative_path=${file#"$main_worktree"/}
      target_dir=$(dirname "$worktree_path/$relative_path")
      mkdir -p "$target_dir"
      cp "$file" "$worktree_path/$relative_path"
      echo "Copied $relative_path"
    done < <(__gw_glob "$main_worktree" "$pattern")
  done

  if [ -f "$worktree_path/.gitmodules" ]; then
    local init_submodules
    printf '%s' "Initialize submodules? [Y/n] "
    read -r init_submodules
    if [ "$init_submodules" != "n" ] && [ "$init_submodules" != "N" ]; then
      echo "Initializing submodules..."
      git -C "$worktree_path" submodule update --init --recursive
    fi
  fi

  cd "$worktree_path"
}

__gw_select_branch_and_create() {
  local worktrees_dir=$1
  local initial_query=$2

  local new_branch_marker="+ Create new branch..."

  # Union of local branches and remote-tracking branches (with the
  # remote prefix stripped). `lstrip=3` drops `refs/remotes/<remote>/`,
  # so `refs/remotes/origin/HEAD` collapses to `HEAD` and is filtered
  # out — using `branch -a` here instead would leak `origin` as a
  # phantom branch, since git renders that symref as a bare remote name.
  local branches=()
  local branch
  while IFS= read -r branch; do
    branches+=( "$branch" )
  done < <( {
      git for-each-ref --format='%(refname:short)' refs/heads
      git for-each-ref --format='%(refname:lstrip=3)' refs/remotes
    } | grep -v '^HEAD$' | sort -u )

  local preview_script
  preview_script=$(__gw_preview_branch)

  local fzf_args=(
    --preview="$preview_script"
    --preview-window="right:60%:wrap"
    --header="Select existing branch or create new"
    --border
    --height=80%
    --layout=reverse
  )
  [ -n "$initial_query" ] && fzf_args+=( --query="$initial_query" )

  local selection
  selection=$(printf '%s\n' "$new_branch_marker" "${branches[@]}" | fzf "${fzf_args[@]}")

  if [ -z "$selection" ]; then
    return
  fi

  if [ "$selection" = "$new_branch_marker" ]; then
    local new_branch_name=""
    __gw_read_edited "Enter new branch name: " new_branch_name
    if [ -z "$new_branch_name" ]; then
      echo "Cancelled: no branch name entered"
      return 1
    fi
    __gw_create_worktree "$new_branch_name" "$worktrees_dir"
  else
    __gw_create_worktree "$selection" "$worktrees_dir"
  fi
}

__gw_confirm_and_remove() {
  local worktree_path=$1
  local branch changes
  branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null)
  changes=$(git -C "$worktree_path" status --porcelain 2>/dev/null)

  echo "Target worktree:"
  echo "  Path:   $worktree_path"
  echo "  Branch: ${branch:-<detached>}"

  if [ -n "$changes" ]; then
    printf '\033[1;33m⚠️  Warning: Worktree has uncommitted changes — they will be lost:\033[0m\n'
    echo "$changes" | head -10
    if [ "$(echo "$changes" | wc -l)" -gt 10 ]; then
      echo "  ... and more"
    fi
  fi

  local confirm
  printf '%s' "Remove this worktree? [y/N] "
  read -r confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Cancelled"
    return
  fi

  echo "Removing worktree at: $worktree_path"
  git worktree remove --force "$worktree_path" || return

  echo "Worktree removed successfully"

  if [ -n "$branch" ] && [ "$branch" != "HEAD" ]; then
    local delete_branch
    printf '%s' "Also delete branch '$branch'? [y/N] "
    read -r delete_branch
    if [ "$delete_branch" = "y" ] || [ "$delete_branch" = "Y" ]; then
      if git branch -D "$branch" 2>/dev/null; then
        echo "Branch '$branch' deleted"
      else
        echo "Failed to delete branch '$branch'"
      fi
    fi
  fi
}

__gw_remove_interactive() {
  local worktrees_dir=$1

  local main_worktree current_worktree
  main_worktree=$(__gw_worktree_paths | head -1)
  current_worktree=$(pwd -P)

  local fzf_input=()
  local wt_path branch relative_path
  while IFS= read -r wt_path; do
    [ "$wt_path" = "$main_worktree" ] && continue
    [ "$wt_path" = "$current_worktree" ] && continue
    branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null)
    relative_path=${wt_path#"$main_worktree"/}
    fzf_input+=( "${wt_path}"$'\t'"${relative_path} [${branch}]" )
  done < <(__gw_worktree_paths)

  if [ ${#fzf_input[@]} -eq 0 ]; then
    echo "No worktrees to remove"
    return 1
  fi

  local preview_script
  preview_script=$(__gw_preview_worktree)

  local selected
  selected=$(printf '%s\n' "${fzf_input[@]}" | fzf \
    --preview="$preview_script" \
    --preview-window="right:60%:wrap" \
    --header="Select worktree to REMOVE (Enter to confirm)" \
    --border \
    --height=80% \
    --layout=reverse \
    --delimiter=$'\t' \
    --with-nth=2)

  if [ -n "$selected" ]; then
    local worktree_path=${selected%%$'\t'*}
    __gw_confirm_and_remove "$worktree_path"
  fi
}

gw() {
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "Error: Not in a git repository"
    return 1
  fi

  local worktrees_dir
  worktrees_dir=$(__gw_get_worktrees_dir)

  local cmd=$1

  case "$cmd" in
    remove)
      local target=$2
      if [ -z "$target" ]; then
        __gw_remove_interactive "$worktrees_dir"
        return
      fi

      # Resolve $target against, in order:
      #   1. A branch name that matches an existing worktree.
      #   2. A directory name under $worktrees_dir.
      #   3. A direct path to a worktree.
      local worktree_path=""
      local worktree_info
      worktree_info=$(git worktree list | grep "\[$target\]")
      if [ -n "$worktree_info" ]; then
        worktree_path=$(echo "$worktree_info" | awk '{print $1}')
      fi
      if [ -z "$worktree_path" ] && [ -d "$worktrees_dir/$target" ]; then
        worktree_path="$worktrees_dir/$target"
      fi
      if [ -z "$worktree_path" ] && [ -d "$target" ]; then
        worktree_path="$target"
      fi

      if [ -z "$worktree_path" ]; then
        echo "No worktree found for: $target"
        echo "Try 'gw remove' without arguments to select interactively."
        return 1
      fi

      __gw_confirm_and_remove "$worktree_path"
      ;;

    add)
      local branch_name=$2
      if [ -z "$branch_name" ]; then
        __gw_select_branch_and_create "$worktrees_dir"
      else
        __gw_create_worktree "$branch_name" "$worktrees_dir"
      fi
      ;;

    switch)
      __gw_switch_interactive "$worktrees_dir"
      ;;

    "")
      if ! __gw_has_worktrees; then
        echo "No worktrees found. Select a branch to create one:"
        __gw_select_branch_and_create "$worktrees_dir"
      else
        __gw_switch_interactive "$worktrees_dir"
      fi
      ;;

    *)
      echo "Unknown command: $cmd"
      echo "Usage:"
      echo "  gw                      - Switch worktree (or add if none exist)"
      echo "  gw switch               - Switch worktree"
      echo "  gw add [branch]         - Create worktree for branch"
      echo "  gw remove [branch|dir]  - Remove worktree"
      return 1
      ;;
  esac
}
