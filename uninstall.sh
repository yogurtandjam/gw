#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="${HOME}/.local/bin"

echo "gw uninstaller"
echo "=============="

if [[ -L "${BIN_DIR}/gw-select" ]]; then
  rm "${BIN_DIR}/gw-select"
  echo "  Removed ${BIN_DIR}/gw-select"
fi

for rc in "${HOME}/.zshrc" "${HOME}/.bashrc"; do
  if [[ -f "$rc" ]] && grep -qF "gw.sh" "$rc"; then
    sed -i.bak '/# gw — git worktree switcher/d;/gw\.sh/d' "$rc"
    rm -f "${rc}.bak"
    echo "  Cleaned gw lines from ${rc}"
  fi
done

echo ""
echo "Done. Config left at ~/.config/gw/ (delete manually if desired)."
echo "Restart your shell to complete."
