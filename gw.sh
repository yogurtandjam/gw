# gw — git worktree switcher shell integration
# Source this file from your .zshrc or .bashrc:
#   source ~/code/gw/gw.sh

gw() {
  case "$1" in
    help|--help|-h)
      echo "gw — git worktree switcher"
      echo ""
      echo "Usage:"
      echo "  gw                        Interactive picker for current repo's worktrees"
      echo "  gw <pattern>              Jump to matching worktree (fuzzy match)"
      echo "  gw <pattern> <cmd>        Jump and run a command"
      echo "  gw add <branch>           New worktree from existing remote branch"
      echo "  gw create <branch>        New worktree + new branch off main"
      echo "  gw cleanup                Multi-select worktrees to remove"
      echo "  gw help                   Show this help"
      echo ""
      echo "Examples:"
      echo "  gw                        Open picker"
      echo "  gw anton                  cd into worktree matching 'anton'"
      echo "  gw anton claude           cd into it and launch claude"
      echo "  gw add fix/balance-bug    Checkout remote branch into new worktree"
      echo "  gw create feat/new-thing  Create new branch off main in new worktree"
      echo "  gw cleanup                Select and remove stale worktrees"
      echo ""
      echo "Config: ~/.config/gw/config"
      echo "  default_repo=~/code/funkit   Fallback repo when not inside one"
      return 0
      ;;

    cleanup|delete)
      _gw_cleanup
      return $?
      ;;

    add)
      shift
      _gw_add "$@"
      return $?
      ;;

    create)
      shift
      _gw_create "$@"
      return $?
      ;;

    *)
      _gw_switch "$@"
      return $?
      ;;
  esac
}

# ── Helpers ──────────────────────────────────────────────────────────────────

_gw_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

_gw_worktree_path() {
  # Given a branch name, produce the sibling worktree directory path.
  # e.g. branch "anton/checkout-fix" in repo "funkit" -> ../funkit-anton-checkout-fix
  local repo_root="$1"
  local branch="$2"
  local repo_name="${repo_root##*/}"
  local sanitized="${branch//\//-}"
  echo "${repo_root%/*}/${repo_name}-${sanitized}"
}

_gw_main_branch() {
  local repo="$1"
  # Check for main, then master
  if git -C "$repo" rev-parse --verify refs/heads/main &>/dev/null; then
    echo "main"
  elif git -C "$repo" rev-parse --verify refs/heads/master &>/dev/null; then
    echo "master"
  else
    echo "main"
  fi
}

_gw_main_worktree() {
  # Find the main worktree (the non-linked one with an actual .git directory)
  local repo="$1"
  git -C "$repo" worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //'
}

_gw_copy_env() {
  # Copy all .env* files from main worktree to new worktree, preserving paths
  local main_wt="$1"
  local new_wt="$2"

  if [[ -z "$main_wt" || -z "$new_wt" ]]; then
    return
  fi

  local count=0
  while IFS= read -r -d '' env_file; do
    local rel="${env_file#$main_wt/}"
    local dest="${new_wt}/${rel}"
    local dest_dir="${dest%/*}"
    [[ -d "$dest_dir" ]] || mkdir -p "$dest_dir"
    cp "$env_file" "$dest"
    ((count++))
  done < <(find "$main_wt" -name '.env*' -not -path '*node_modules*' -not -path '*/.git/*' -print0 2>/dev/null)

  if [[ $count -gt 0 ]]; then
    echo "  Copied ${count} .env file(s) from main worktree"
  fi
}

# ── Commands ─────────────────────────────────────────────────────────────────

_gw_switch() {
  local filter=""
  local -a cmd=()

  if [[ $# -ge 1 ]]; then
    filter="$1"; shift
    cmd=("$@")
  fi

  local target
  target=$(gw-select "$filter")
  local rc=$?

  if [[ $rc -ne 0 || -z "$target" ]]; then
    return 1
  fi

  cd "$target" || return 1

  if [[ ${#cmd} -gt 0 ]]; then
    echo "-> $(pwd) && ${cmd[*]}"
    "${cmd[@]}"
  else
    echo "-> $(pwd)"
  fi
}

_gw_cleanup() {
  local paths
  paths=$(gw-select --multi)
  local rc=$?

  if [[ $rc -ne 0 || -z "$paths" ]]; then
    echo "Nothing selected."
    return 1
  fi

  local -a dirs=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && dirs+=("$line")
  done <<< "$paths"

  # Find the main repo root (from first selected worktree)
  local main_repo
  main_repo=$(git -C "${dirs[1]}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  main_repo="${main_repo%/.git}"

  echo ""
  echo "Will remove ${#dirs[@]} worktree(s):"
  echo ""
  for d in "${dirs[@]}"; do
    local name="${d##*/}"
    local branch
    branch=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
    echo "  ${name}  (branch: ${branch})"
  done
  echo ""

  echo -n "Confirm remove? [y/N] "
  read -r confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Cancelled."
    return 1
  fi

  local failed=0
  for d in "${dirs[@]}"; do
    local name="${d##*/}"
    if [[ -n "$main_repo" ]] && git -C "$main_repo" worktree remove --force "$d" 2>/dev/null; then
      echo "  Removed worktree: ${name}"
    else
      rm -rf "$d" && echo "  Deleted: ${name}" || { echo "  FAILED: ${name}"; ((failed++)); }
    fi
  done

  if [[ $failed -eq 0 ]]; then
    echo ""
    echo "Done. Removed ${#dirs[@]} worktree(s)."
  else
    echo ""
    echo "Done with ${failed} error(s)."
    return 1
  fi
}

_gw_add() {
  if [[ -z "$1" ]]; then
    echo "Usage: gw add <branch>"
    echo "  Creates a worktree from an existing remote branch."
    return 1
  fi

  local branch="$1"
  local repo_root
  repo_root=$(_gw_repo_root)
  if [[ -z "$repo_root" ]]; then
    echo "Not in a git repo."
    return 1
  fi

  local wt_path
  wt_path=$(_gw_worktree_path "$repo_root" "$branch")

  if [[ -d "$wt_path" ]]; then
    echo "Directory already exists: ${wt_path##*/}"
    echo -n "cd into it? [Y/n] "
    read -r confirm
    if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
      return 1
    fi
    cd "$wt_path" || return 1
    echo "-> $(pwd)"
    return 0
  fi

  echo "Fetching latest..."
  git -C "$repo_root" fetch --prune || return 1

  # Check if the branch exists on remote
  local remote_ref
  remote_ref=$(git -C "$repo_root" branch -r --list "origin/${branch}" 2>/dev/null | head -1 | xargs)
  if [[ -z "$remote_ref" ]]; then
    echo "Branch '${branch}' not found on remote."
    echo ""
    echo "Did you mean one of these?"
    git -C "$repo_root" branch -r --list "*${branch}*" 2>/dev/null | head -5 | sed 's/^ */  /'
    return 1
  fi

  echo "Creating worktree at ${wt_path##*/}..."
  git -C "$repo_root" worktree add --track -b "$branch" "$wt_path" "origin/${branch}" 2>/dev/null \
    || git -C "$repo_root" worktree add "$wt_path" "$branch" \
    || return 1

  _gw_copy_env "$(_gw_main_worktree "$repo_root")" "$wt_path"

  cd "$wt_path" || return 1
  echo "-> $(pwd) (branch: $branch)"
}

_gw_create() {
  if [[ -z "$1" ]]; then
    echo "Usage: gw create <branch>"
    echo "  Creates a new branch off main in a new worktree."
    return 1
  fi

  local branch="$1"
  local repo_root
  repo_root=$(_gw_repo_root)
  if [[ -z "$repo_root" ]]; then
    echo "Not in a git repo."
    return 1
  fi

  local wt_path
  wt_path=$(_gw_worktree_path "$repo_root" "$branch")

  if [[ -d "$wt_path" ]]; then
    echo "Directory already exists: ${wt_path##*/}"
    echo -n "cd into it? [Y/n] "
    read -r confirm
    if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
      return 1
    fi
    cd "$wt_path" || return 1
    echo "-> $(pwd)"
    return 0
  fi

  local main_branch
  main_branch=$(_gw_main_branch "$repo_root")

  echo "Fetching latest ${main_branch}..."
  git -C "$repo_root" fetch origin "${main_branch}" || return 1

  echo "Creating worktree at ${wt_path##*/} (new branch: ${branch} off ${main_branch})..."
  git -C "$repo_root" worktree add -b "$branch" "$wt_path" "origin/${main_branch}" || return 1

  _gw_copy_env "$(_gw_main_worktree "$repo_root")" "$wt_path"

  cd "$wt_path" || return 1
  echo "-> $(pwd) (branch: $branch, based on: ${main_branch})"
}
