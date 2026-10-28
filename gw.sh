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
      echo "  gw add <branch>           New worktree from existing branch (remote, else local)"
      echo "  gw create <branch>        New worktree + new branch off main"
      echo "  gw stack <branch>         New worktree + new branch off the CURRENT branch"
      echo "  gw env                    Copy .env files from main worktree to current"
      echo "  gw cleanup                Multi-select worktrees to remove"
      echo "  gw help                   Show this help"
      echo ""
      echo "Examples:"
      echo "  gw                        Open picker"
      echo "  gw anton                  cd into worktree matching 'anton'"
      echo "  gw anton claude           cd into it and launch claude"
      echo "  gw add fix/balance-bug    Checkout an existing branch into a new worktree"
      echo "  gw create feat/new-thing  Create new branch off main in new worktree"
      echo "  gw stack feat/part-2      Stack a new branch off the current branch"
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

    env)
      _gw_sync_env
      return $?
      ;;

    create)
      shift
      _gw_create "$@"
      return $?
      ;;

    stack)
      shift
      _gw_stack "$@"
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
  # Always uses the *main* worktree's name as the prefix, regardless of cwd.
  local repo_root="$1"
  local branch="$2"
  local main_wt
  main_wt=$(_gw_main_worktree "$repo_root")
  local repo_name="${main_wt##*/}"
  local sanitized="${branch//\//-}"
  echo "${main_wt%/*}/${repo_name}-${sanitized}"
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
    # git can unregister the worktree yet leave the directory behind, so always sweep leftovers
    [[ -n "$main_repo" ]] && git -C "$main_repo" worktree remove --force "$d" 2>/dev/null
    [[ -e "$d" ]] && rm -rf "$d"
    if [[ -e "$d" ]]; then
      echo "  FAILED: ${name}"
      ((failed++))
    else
      echo "  Removed: ${name}"
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
    echo "  Creates a worktree from an existing branch (remote, else local)."
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

  # git refuses to check out a branch that's already live in another worktree (e.g.
  # the branch you're currently on). Detect that and offer to jump there instead.
  local existing_wt
  existing_wt=$(git -C "$repo_root" worktree list --porcelain 2>/dev/null \
    | awk -v b="refs/heads/${branch}" '/^worktree /{p=substr($0,10)} $0=="branch "b{print p}')
  if [[ -n "$existing_wt" ]]; then
    echo "Branch '${branch}' is already checked out at: ${existing_wt##*/}"
    echo -n "cd into it? [Y/n] "
    read -r confirm
    if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
      return 1
    fi
    cd "$existing_wt" || return 1
    echo "-> $(pwd) (branch: $branch)"
    return 0
  fi

  echo "Fetching latest..."
  git -C "$repo_root" fetch --prune || return 1

  # Prefer a remote branch (track it); fall back to an existing local branch.
  local remote_ref
  remote_ref=$(git -C "$repo_root" branch -r --list "origin/${branch}" 2>/dev/null | head -1 | xargs)
  if [[ -n "$remote_ref" ]]; then
    echo "Creating worktree at ${wt_path##*/} (tracking origin/${branch})..."
    git -C "$repo_root" worktree add --track -b "$branch" "$wt_path" "origin/${branch}" 2>/dev/null \
      || git -C "$repo_root" worktree add "$wt_path" "$branch" \
      || return 1
  elif git -C "$repo_root" rev-parse --verify --quiet "refs/heads/${branch}" >/dev/null; then
    echo "No remote branch; using local branch '${branch}'."
    echo "Creating worktree at ${wt_path##*/}..."
    git -C "$repo_root" worktree add "$wt_path" "$branch" || return 1
  else
    echo "Branch '${branch}' not found on remote or locally."
    echo ""
    echo "Did you mean one of these?"
    git -C "$repo_root" branch -a --list "*${branch}*" 2>/dev/null | head -5 | sed 's/^[*+ ] */  /'
    return 1
  fi

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
  _gw_new_branch_worktree "$1" main
}

_gw_stack() {
  if [[ -z "$1" ]]; then
    echo "Usage: gw stack <branch>"
    echo "  Creates a new branch off the CURRENT branch in a new worktree (for PR stacks)."
    return 1
  fi
  _gw_new_branch_worktree "$1" current
}

# Shared worker for `create` (mode=main) and `stack` (mode=current).
_gw_new_branch_worktree() {
  local branch="$1"
  local mode="$2"   # "main": fetch + branch off origin/main; "current": branch off local HEAD

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

  local base_branch start_point
  if [[ "$mode" == "current" ]]; then
    # Stack off the LOCAL tip of the current branch — including unpushed commits, which
    # is the whole point of stacking (the parent PR may not be merged or pushed yet).
    # No fetch: we want local state, and origin/<parent> may not even exist.
    base_branch=$(git -C "$repo_root" symbolic-ref --short HEAD 2>/dev/null)
    if [[ -z "$base_branch" ]]; then
      echo "Detached HEAD — can't determine the current branch to stack on."
      return 1
    fi
    start_point="$base_branch"
  else
    base_branch=$(_gw_main_branch "$repo_root")
    echo "Fetching latest ${base_branch}..."
    git -C "$repo_root" fetch origin "${base_branch}" || return 1
    start_point="origin/${base_branch}"
  fi

  echo "Creating worktree at ${wt_path##*/} (new branch: ${branch} off ${base_branch})..."
  # --no-track: branch off the start-point without inheriting it as upstream. Otherwise
  # git's default for a remote/branch start-point leaves the new branch tracking it, so
  # `git pull` pulls the wrong branch and `git push` is ambiguous. With no upstream, the
  # first `git push -u` (or `gpush`) sets the correct origin/<branch>.
  git -C "$repo_root" worktree add --no-track -b "$branch" "$wt_path" "$start_point" || return 1

  _gw_copy_env "$(_gw_main_worktree "$repo_root")" "$wt_path"

  cd "$wt_path" || return 1
  echo "-> $(pwd) (branch: $branch, based on: ${base_branch})"
}

_gw_sync_env() {
  local repo_root
  repo_root=$(_gw_repo_root)
  if [[ -z "$repo_root" ]]; then
    echo "Not in a git repo."
    return 1
  fi

  local main_wt
  main_wt=$(_gw_main_worktree "$repo_root")
  if [[ -z "$main_wt" ]]; then
    echo "Could not find main worktree."
    return 1
  fi

  if [[ "$main_wt" == "$repo_root" ]]; then
    echo "Already in the main worktree — nothing to sync."
    return 1
  fi

  _gw_copy_env "$main_wt" "$repo_root"
}
