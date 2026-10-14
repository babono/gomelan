#!/usr/bin/env bash
set -euo pipefail

swift package resolve --package-path BuildTools

# .claude/ is gitignored, so the Claude Code format+check hook is installed here instead of
# committed. Idempotent: skipped if any PostToolUse command already runs check.sh.
settings=.claude/settings.json
mkdir -p .claude
[ -f "$settings" ] || echo '{}' > "$settings"
if ! jq -e '[.hooks.PostToolUse[]?.hooks[]?.command] | any(contains("scripts/check.sh"))' "$settings" >/dev/null; then
  jq '.hooks.PostToolUse += [{
    matcher: "Bash",
    hooks: [{
      type: "command",
      command: "grep -q '"'"'xcodegen generate'"'"' || exit 0; cd \"$CLAUDE_PROJECT_DIR\" && scripts/format.sh >&2 && scripts/check.sh >&2 || exit 2",
      timeout: 600
    }]
  }]' "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
fi
