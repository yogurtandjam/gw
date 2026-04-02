# gw — git worktree switcher shell integration
# Source this file from your .zshrc or .bashrc:
#   source ~/code/gw/gw.sh

gw() {
  case "$1" in
    help|--help|-h)
      echo "gw — git worktree switcher"
      echo ""
      echo "Usage:"
      echo "  gw                  Interactive picker for current repo's worktrees"
      echo "  gw <pattern>        Jump to matching worktree (fuzzy match)"
      echo "  gw <pattern> <cmd>  Jump and run a command"
      echo "  gw cleanup          Multi-select worktrees to remove"
      echo "  gw delete           Alias for cleanup"
      echo "  gw help             Show this help"
      echo ""
      echo "Examples:"
      echo "  gw                  Open picker"
      echo "  gw anton            cd into worktree matching 'anton'"
      echo "  gw anton claude     cd into it and launch claude"
      echo "  gw cleanup          Select and remove stale worktrees"
      echo ""
      echo "Config: ~/.config/gw/config"
      echo "  default_repo=~/code/funkit   Fallback repo when not inside one"
      return 0
      ;;

    cleanup|delete)
      _gw_cleanup
      return $?
      ;;

    *)
      _gw_switch "$@"
      return $?
      ;;
  esac
}

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
