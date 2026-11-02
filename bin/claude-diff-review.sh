#!/usr/bin/env bash
set -euo pipefail

# Default: review UNSTAGED (working tree) changes
MODE="unstaged"   # staged | all | unstaged | branch
BASE_REF="${BASE_REF:-origin/develop}"

# Prompt selection (in priority order):
# 1. CLAUDE_REVIEW_PROMPT  - explicit path to a single prompt file (always wins)
# 2. CLAUDE_REVIEW_PROMPT_DIR - directory containing the default prompt files
# 3. ~/.claude/prompts     - if it exists
# 4. <repo>/prompts        - the prompts folder shipped next to this script (works straight from a clone)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"
BUNDLED_PROMPT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/prompts"

if [[ -n "${CLAUDE_REVIEW_PROMPT_DIR:-}" ]]; then
  PROMPT_DIR="$CLAUDE_REVIEW_PROMPT_DIR"
elif [[ -d "$HOME/.claude/prompts" ]]; then
  PROMPT_DIR="$HOME/.claude/prompts"
else
  PROMPT_DIR="$BUNDLED_PROMPT_DIR"
fi

DEFAULT_PRECOMMIT_PROMPT="$PROMPT_DIR/precommit-review.md"
DEFAULT_BRANCH_PROMPT="$PROMPT_DIR/branch-review-origin-develop.md"
PROMPT_FILE="${CLAUDE_REVIEW_PROMPT:-$DEFAULT_PRECOMMIT_PROMPT}"

SHOW_STAT="0"
PATCH_OUT=""
INCLUDE_UNTRACKED="0"
MAX_UNTRACKED_LINES="${MAX_UNTRACKED_LINES:-400}"

usage() {
  cat <<USAGE
Usage: claude-diff-review.sh [--staged|--unstaged|--all|--branch-review] [--base <ref>] [--stat] [--include-untracked] [--patch-out <path>]

Runs a reusable Claude (Claude Code CLI) review of git changes in the current repo.

Defaults:
  - Reviews UNSTAGED changes (git diff)

Options:
  --unstaged            Review unstaged changes (git diff) [default]
  --staged              Review staged changes (git diff --cached)
  --all                 Review staged + unstaged changes
  --branch-review       Review current branch vs base ref (git diff <base>...HEAD)
  --base REF            Base ref for --branch-review (default: origin/develop, or env BASE_REF)
  --include-untracked   Include contents of new untracked files (git ls-files --others --exclude-standard)
  --stat                Print changed files list before running Claude
  --patch-out PATH      Ask Claude to output ONLY a unified diff patch and write it to PATH
  -h, --help            Show help

Environment:
  CLAUDE_REVIEW_PROMPT      Path to a specific prompt file (overrides everything else)
  CLAUDE_REVIEW_PROMPT_DIR  Directory holding precommit-review.md and branch-review-origin-develop.md
                            (default: ~/.claude/prompts if present, else the prompts/ folder next to this script)
  MAX_UNTRACKED_LINES       Max lines per untracked file to include (default: 400)
  BASE_REF                  Base ref for --branch-review (default: origin/develop)

Current prompt dir: $PROMPT_DIR

Examples:
  claude-diff-review.sh
  claude-diff-review.sh --stat
  claude-diff-review.sh --include-untracked --stat
  claude-diff-review.sh --all --include-untracked
  claude-diff-review.sh --staged --patch-out /tmp/claude.patch
  claude-diff-review.sh --branch-review
  claude-diff-review.sh --branch-review --base origin/main
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --staged) MODE="staged"; shift ;;
    --unstaged) MODE="unstaged"; shift ;;
    --all) MODE="all"; shift ;;
    --branch-review) MODE="branch"; shift ;;
    --base)
      BASE_REF="${2:-}"
      if [[ -z "$BASE_REF" ]]; then
        echo "--base requires a ref"
        exit 2
      fi
      shift 2
      ;;
    --include-untracked) INCLUDE_UNTRACKED="1"; shift ;;
    --stat) SHOW_STAT="1"; shift ;;
    --patch-out)
      PATCH_OUT="${2:-}"
      if [[ -z "$PATCH_OUT" ]]; then
        echo "--patch-out requires a path"
        exit 2
      fi
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 2 ;;
  esac
done

if ! command -v claude >/dev/null 2>&1; then
  echo "The 'claude' CLI is not on your PATH."
  echo "Install Claude Code first: npm install -g @anthropic-ai/claude-code   (then run 'claude' once to log in)"
  exit 2
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not inside a git repo."
  exit 2
fi

if [[ -z "${CLAUDE_REVIEW_PROMPT:-}" && "$MODE" == "branch" ]]; then
    PROMPT_FILE="$DEFAULT_BRANCH_PROMPT"
fi

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "Prompt file not found: $PROMPT_FILE"
  echo "Either:"
  echo "  - copy the prompts/ folder from this repo to ~/.claude/prompts/, or"
  echo "  - set CLAUDE_REVIEW_PROMPT_DIR to the folder containing the prompt files, or"
  echo "  - set CLAUDE_REVIEW_PROMPT to a specific prompt file."
  exit 2
fi

TMPDIR="${TMPDIR:-/tmp}"
DIFF_FILE="$(mktemp "$TMPDIR/claude-diff-review.XXXXXX.diff")"
trap 'rm -f "$DIFF_FILE"' EXIT

# Build the base diff payload
case "$MODE" in
  staged)
    git diff --cached > "$DIFF_FILE"
    ;;
  unstaged)
    git diff > "$DIFF_FILE"
    ;;
  all)
    {
      echo "### STAGED DIFF (git diff --cached)"
      git diff --cached
      echo
      echo "### UNSTAGED DIFF (git diff)"
      git diff
    } > "$DIFF_FILE"
    ;;
  branch)
    {
      echo "### BRANCH DIFF (git diff ${BASE_REF}...HEAD)"
      if [[ "$BASE_REF" == origin/* ]]; then
        git fetch --quiet origin || true
      fi
      git diff "${BASE_REF}...HEAD"
    } > "$DIFF_FILE"
    ;;
  *)
    echo "Invalid MODE: $MODE"
    exit 2
    ;;
esac

# Append untracked file contents if requested
if [[ "$INCLUDE_UNTRACKED" == "1" ]]; then
  UNTRACKED_LIST="$(git ls-files --others --exclude-standard || true)"
  if [[ -n "$UNTRACKED_LIST" ]]; then
    {
      echo
      echo "### UNTRACKED FILES (new, not in git yet)"
      echo "# NOTE: showing up to ${MAX_UNTRACKED_LINES} lines per file"
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        echo
        echo "---- FILE: $f ----"
        if [[ -f "$f" ]]; then
          sed -n "1,${MAX_UNTRACKED_LINES}p" "$f"
        else
          echo "(not a regular file)"
        fi
      done <<< "$UNTRACKED_LIST"
    } >> "$DIFF_FILE"
  fi
fi

if [[ ! -s "$DIFF_FILE" ]]; then
  echo "No changes to review for mode: $MODE"
  exit 0
fi

if [[ "$SHOW_STAT" == "1" ]]; then
  echo "Changed files:"
  if [[ "$MODE" == "staged" ]]; then
    git diff --cached --name-status
  elif [[ "$MODE" == "unstaged" ]]; then
    git diff --name-status
  elif [[ "$MODE" == "branch" ]]; then
    git diff "${BASE_REF}...HEAD" --name-status
  else
    echo "STAGED:"
    git diff --cached --name-status
    echo "UNSTAGED:"
    git diff --name-status
  fi

  if [[ "$INCLUDE_UNTRACKED" == "1" ]]; then
    UNTRACKED_STAT="$(git ls-files --others --exclude-standard || true)"
    if [[ -n "$UNTRACKED_STAT" ]]; then
      echo "UNTRACKED:"
      printf "%s\n" "$UNTRACKED_STAT" | sed 's/^/?? /'
    fi
  fi

  echo
fi

ROOT_DIR="$(git rev-parse --show-toplevel)"
# Accept either capitalisation of the repo instructions file
CLAUDE_MD_PATH="${ROOT_DIR}/CLAUDE.md"
[[ -f "$CLAUDE_MD_PATH" ]] || CLAUDE_MD_PATH="${ROOT_DIR}/Claude.md"

EXTRA_INSTRUCTIONS=""
if [[ -n "$PATCH_OUT" ]]; then
  EXTRA_INSTRUCTIONS=$(
    cat <<'PATCHRULES'

IMPORTANT:
- Output ONLY a unified diff patch (git apply compatible).
- Do not include explanations, markdown, or code fences.
- If no changes are needed, output nothing.
PATCHRULES
  )
fi

INPUT="$(
  {
    cat "$PROMPT_FILE"
    echo "$EXTRA_INSTRUCTIONS"
    echo
    if [[ -f "$CLAUDE_MD_PATH" ]]; then
      echo "=== BEGIN CLAUDE.md ==="
      cat "$CLAUDE_MD_PATH"
      echo "=== END CLAUDE.md ==="
    else
      echo "=== NOTE: CLAUDE.md not found at repo root (${ROOT_DIR}) ==="
    fi
    echo
    echo "=== BEGIN GIT CHANGES ==="
    cat "$DIFF_FILE"
    echo
    echo "=== END GIT CHANGES ==="
  }
)"

if [[ -n "$PATCH_OUT" ]]; then
  OUTPUT="$(printf "%s" "$INPUT" | claude)"
  printf "%s" "$OUTPUT" > "$PATCH_OUT"

  if [[ -s "$PATCH_OUT" ]]; then
    echo "Patch written to: $PATCH_OUT"
    echo "Dry-run check: git apply --check \"$PATCH_OUT\""
    echo "Apply it with:  git apply \"$PATCH_OUT\""
    echo "Then review with: git diff"
  else
    echo "No patch output (Claude suggested no code changes)."
  fi
else
  printf "%s" "$INPUT" | claude
fi
