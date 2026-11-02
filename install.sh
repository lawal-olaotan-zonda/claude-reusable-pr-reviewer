#!/usr/bin/env bash
# Installs claude-diff-review for the current user:
#   - copies prompts to ~/.claude/prompts/
#   - symlinks the script into ~/bin (or ~/.local/bin if that's on PATH)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_DEST="$HOME/.claude/prompts"

if [[ ":$PATH:" == *":$HOME/bin:"* ]]; then
  BIN_DEST="$HOME/bin"
elif [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
  BIN_DEST="$HOME/.local/bin"
else
  BIN_DEST="$HOME/bin"
  echo "Note: $BIN_DEST is not on your PATH. Add this to your shell rc:"
  echo "  export PATH=\"\$HOME/bin:\$PATH\""
fi

mkdir -p "$PROMPT_DEST" "$BIN_DEST"

for f in "$HERE"/prompts/*.md; do
  name="$(basename "$f")"
  if [[ -f "$PROMPT_DEST/$name" ]]; then
    echo "Keeping your existing $PROMPT_DEST/$name (new version at $f)"
  else
    cp "$f" "$PROMPT_DEST/$name"
    echo "Installed prompt: $PROMPT_DEST/$name"
  fi
done

chmod +x "$HERE/bin/claude-diff-review.sh"
ln -sf "$HERE/bin/claude-diff-review.sh" "$BIN_DEST/claude-diff-review"
echo "Linked: $BIN_DEST/claude-diff-review -> $HERE/bin/claude-diff-review.sh"

if ! command -v claude >/dev/null 2>&1; then
  echo
  echo "Claude Code CLI not found. Install it with:"
  echo "  npm install -g @anthropic-ai/claude-code"
  echo "then run 'claude' once to log in."
fi

echo
echo "Done. Try it inside any git repo:  claude-diff-review --stat"
