# claude-diff-review

A small bash wrapper that sends your git changes (plus your repo's `CLAUDE.md`) to the Claude Code CLI with a reusable review prompt. Works on unstaged, staged, or branch-vs-base diffs, and can optionally return a ready-to-apply patch.

## Prerequisites

- `git`
- Node.js 18+ and the Claude Code CLI:
  ```bash
  npm install -g @anthropic-ai/claude-code
  claude   # run once to log in
  ```

## Install

```bash
git clone <this-repo-url> ~/.claude-diff-review
~/.claude-diff-review/install.sh
```

The installer:

1. Copies the prompt files to **`~/.claude/prompts/`** (existing files are left alone, so you can customise them).
2. Symlinks the script to `~/bin/claude-diff-review` (or `~/.local/bin` if that's what's on your PATH).

### Manual install (if you'd rather not run the installer)

| What | Where it goes |
|---|---|
| `bin/claude-diff-review.sh` | anywhere on your `PATH`, e.g. `~/bin/` |
| `prompts/precommit-review.md` | `~/.claude/prompts/precommit-review.md` |
| `prompts/branch-review-origin-develop.md` | `~/.claude/prompts/branch-review-origin-develop.md` |

You can skip copying the prompts entirely: if `~/.claude/prompts/` doesn't exist, the script falls back to the `prompts/` folder that sits next to it in this repo.

## Usage

Run from inside any git repo:

```bash
claude-diff-review                       # review unstaged changes (default)
claude-diff-review --stat                # list changed files first
claude-diff-review --staged              # review what you're about to commit
claude-diff-review --all --include-untracked
claude-diff-review --branch-review       # branch vs origin/develop
claude-diff-review --branch-review --base origin/main
claude-diff-review --staged --patch-out /tmp/fix.patch   # get a patch instead of prose
```

`--help` prints all options and shows which prompt directory is currently in use.

## Where the prompt comes from

Resolved in this order; the first match wins:

1. `CLAUDE_REVIEW_PROMPT` — a specific prompt file (ignores mode)
2. `CLAUDE_REVIEW_PROMPT_DIR` — a folder containing the two default prompt files
3. `~/.claude/prompts/` — if the folder exists
4. `prompts/` next to the script (the copy in this repo)

Within the chosen folder, `--branch-review` uses `branch-review-origin-develop.md`; every other mode uses `precommit-review.md`.

To try a one-off prompt without touching your defaults:

```bash
CLAUDE_REVIEW_PROMPT=./my-security-review.md claude-diff-review --staged
```

## Other environment variables

| Variable | Default | Purpose |
|---|---|---|
| `BASE_REF` | `origin/develop` | Base ref for `--branch-review` |
| `MAX_UNTRACKED_LINES` | `400` | Lines per untracked file when `--include-untracked` |

## Repo instructions

If the repo has a `CLAUDE.md` (or `Claude.md`) at its root, it's included in the review context so Claude follows that project's conventions.

## Updating

```bash
cd ~/.claude-diff-review && git pull
```

The symlink means the script updates in place. Prompts in `~/.claude/prompts/` are *not* overwritten — diff them against `prompts/` here if you want the latest.
