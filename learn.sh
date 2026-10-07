#!/usr/bin/env bash
# Learning tick: evolve strategy/ from the journal, with no market access.
#
# This machine cannot reach gamma-api.polymarket.com (HTTP 451), so loop.sh
# can only produce empty cycles here. This runner does the half of the cycle
# that needs no market: pull the upstream runner's journal, score it, and let
# the agent improve its own judgment against it under a validation gate.
#
# Data comes from upstream. Judgment stays ours: only journal/ is merged,
# and upstream's strategy/ changes are offered to the agent as a diff to
# read, not as a merge.
#
# Usage: ./learn.sh
#   PHIL_LEARN_MODEL=claude-opus-5-5  override the model (default sonnet-5)
#   PHIL_LEARN_NO_PUSH=1              commit but do not push
set -euo pipefail
cd "$(dirname "$0")"

# Windows/Korean-locale Python defaults to cp949 and blows up on the journal's
# non-ASCII market titles, on read and worse on append. Force UTF-8.
export PYTHONUTF8=1
export PYTHONIOENCODING=utf-8

mkdir -p work
LOCK="work/learn.pid"
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
  echo "ERROR: learn.sh is already running in this checkout (pid $(cat "$LOCK"))" >&2
  exit 1
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

MODEL="${PHIL_LEARN_MODEL:-claude-sonnet-5}"
echo "=== learn tick $(date -u +%FT%TZ)  model: $MODEL ==="

# Never cycle on a detached HEAD: the push below would silently no-op.
if ! git symbolic-ref -q HEAD >/dev/null; then
  echo "WARNING: HEAD detached — reattaching main to HEAD" >&2
  git checkout -B main HEAD
fi

# Fast-forward our own fork. A real divergence needs a human.
if git fetch origin main 2>/dev/null; then
  if git merge-base --is-ancestor HEAD origin/main; then
    git checkout -B main origin/main
  elif ! git merge-base --is-ancestor origin/main HEAD; then
    echo "WARNING: main and origin/main have diverged — resolve manually" >&2
  fi
fi

# Data in, judgment untouched: take upstream's journal/ only.
if ! git fetch upstream main 2>/dev/null; then
  echo "WARNING: could not fetch upstream — learning on the journal we have" >&2
else
  UP="$(git rev-parse --short upstream/main)"
  git checkout upstream/main -- journal/ 2>/dev/null || true
  # Upstream's strategy/ changes are reference material for the agent, not a
  # merge. work/ is gitignored, so this never reaches a commit.
  #
  # Diff from the MERGE BASE, not from HEAD. `git diff HEAD upstream/main`
  # also renders our own strategy/ edits as deletions, and the first learning
  # tick duly read them as upstream having removed them (LEARN-20261007-0452,
  # "forward-test-run paragraphs removed ... now that the ruling is settled" —
  # upstream never had them; we added them in fd7fcf7). From the merge base
  # the file contains upstream's changes and nothing of ours.
  MB="$(git merge-base HEAD upstream/main)"
  {
    echo "# Upstream's own strategy/ changes since the common ancestor $(git rev-parse --short "$MB")."
    echo "# Nothing in this file is yours: '-' lines are what upstream removed from the"
    echo "# ancestor, '+' lines are what upstream added. Your own edits do not appear."
    echo
    git diff "$MB" upstream/main -- strategy/
  } > work/upstream-strategy.diff || true
  if git diff --cached --quiet; then
    echo "journal/ already current with upstream $UP"
  else
    git diff --cached --stat -- journal/ | tail -1
    git commit -q -m "data: pull upstream journal/ at $UP"
  fi
fi

echo
python3 core/score.py --skip-mtm
echo

CMD=(claude -p "$(cat LEARN.md)" --model "$MODEL"
     --allowedTools "Read" "Glob" "Grep" "Edit" "Write" "Task"
       "Bash(python3 core/*)" "Bash(git add:*)" "Bash(git commit:*)"
       "Bash(git log:*)" "Bash(git diff:*)" "Bash(git status:*)"
       "Bash(git show:*)" "Bash(git rev-parse:*)"
     --permission-mode acceptEdits)
GIT_TERMINAL_PROMPT=0 GIT_EDITOR=true "${CMD[@]}" \
  || echo "learn tick failed; continuing to the boundary check" >&2

# Same boundary loop.sh enforces, plus this runner's own files.
PROTECTED=(core/ config/ .github/ CYCLE.md REAL.md loop.sh CLAUDE.md LICENSE
           README.md .gitignore LEARN.md learn.sh)
if ! git diff --quiet HEAD -- "${PROTECTED[@]}"; then
  echo "WARNING: agent touched protected files — reverting" >&2
  git checkout -- "${PROTECTED[@]}"
fi

if [ -n "${PHIL_LEARN_NO_PUSH:-}" ]; then
  echo "PHIL_LEARN_NO_PUSH set — not pushing"
elif git remote get-url origin >/dev/null 2>&1; then
  git push origin main || echo "WARNING: push failed — commits are local only" >&2
fi

echo "=== learn tick done $(date -u +%FT%TZ) ==="
