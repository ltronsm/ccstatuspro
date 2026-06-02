#!/bin/bash
# ccstatuspro installer — wires the statusline into Claude Code.
#
# Usage:
#   bash install.sh            # merge into ~/.claude/settings.json
#   bash install.sh --print    # show the config block without writing
#
# Safe to re-run: merges into existing settings rather than replacing.

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_path="$repo_dir/bin/ccstatuspro"
settings="$HOME/.claude/settings.json"

if [ ! -x "$bin_path" ]; then
    echo "error: $bin_path is not executable. Run: chmod +x bin/ccstatuspro" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required. Install via: brew install jq" >&2
    exit 1
fi

block=$(cat <<EOF
{
  "statusLine": {
    "type": "command",
    "command": "bash $bin_path",
    "refreshInterval": 1,
    "padding": 0
  }
}
EOF
)

if [ "${1:-}" = "--print" ]; then
    printf '%s\n' "$block"
    exit 0
fi

mkdir -p "$(dirname "$settings")"
if [ -f "$settings" ]; then
    # Merge: new statusLine overrides old, everything else preserved.
    tmp=$(mktemp)
    jq --argjson new "$block" '. * $new' "$settings" > "$tmp"
    mv "$tmp" "$settings"
    echo "merged statusLine config into $settings"
else
    printf '%s\n' "$block" > "$settings"
    echo "wrote $settings"
fi

echo "done. open Claude Code (or restart) to pick up the new statusline."
