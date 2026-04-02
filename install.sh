#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"

echo "gw installer"
echo "============"

mkdir -p "$BIN_DIR"

ln -sf "${SCRIPT_DIR}/bin/gw-select" "${BIN_DIR}/gw-select"
chmod +x "${SCRIPT_DIR}/bin/gw-select"
echo "  Linked gw-select -> ${BIN_DIR}/gw-select"

# Default config
CONFIG_DIR="${HOME}/.config/gw"
CONFIG_FILE="${CONFIG_DIR}/config"
if [[ ! -f "$CONFIG_FILE" ]]; then
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<'EOF'
# gw configuration
# default_repo: fallback repo when you're not inside a git worktree
# default_repo=~/code/your-repo
EOF
  echo "  Created config at ${CONFIG_FILE}"
  echo "  Edit it to set your default_repo"
else
  echo "  Config already exists at ${CONFIG_FILE} (skipped)"
fi

# Shell integration
SHELL_RC=""
if [[ -f "${HOME}/.zshrc" ]]; then
  SHELL_RC="${HOME}/.zshrc"
elif [[ -f "${HOME}/.bashrc" ]]; then
  SHELL_RC="${HOME}/.bashrc"
fi

SOURCE_LINE="source \"${SCRIPT_DIR}/gw.sh\""

if [[ -n "$SHELL_RC" ]]; then
  if grep -qF "gw.sh" "$SHELL_RC" 2>/dev/null; then
    echo "  Shell integration already present in ${SHELL_RC}"
  else
    echo "" >> "$SHELL_RC"
    echo "# gw — git worktree switcher" >> "$SHELL_RC"
    echo "$SOURCE_LINE" >> "$SHELL_RC"
    echo "  Added shell integration to ${SHELL_RC}"
  fi
else
  echo "  Add this to your shell rc manually:"
  echo "    ${SOURCE_LINE}"
fi

if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
  echo ""
  echo "  WARNING: ${BIN_DIR} is not in your PATH."
  echo "  Add: export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "Done! Restart your shell or run: source ${SHELL_RC}"
