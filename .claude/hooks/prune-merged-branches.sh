#!/usr/bin/env bash
# SessionStart hook — project-hadur
# Two guarded mutations. See docs/git-discipline.md §6 and decision-log.md D-014.
#
#   1. Delete a local branch  iff  a PR for it (base main) is MERGED  AND  the
#      local tip SHA equals that PR's merged head SHA.
#   2. Fast-forward local `main` to origin/main, only on a clean fast-forward.
#      Opt-out: `git config hadur.autoUpdateMain false`  or  .git/NO_AUTO_MAIN
#
# Fail-safe: any missing prerequisite -> do nothing, exit 0. Never blocks a
# session. Prints only when it actually acts.

set -u

# --- prerequisites ---------------------------------------------------------------
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
command -v gh >/dev/null 2>&1            || exit 0
gh auth status >/dev/null 2>&1           || exit 0
git fetch --prune --quiet 2>/dev/null    || exit 0

current="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"

# --- 1. delete branches whose PR merged into main ------------------------------
while IFS= read -r b; do
  [ -n "$b" ]           || continue
  [ "$b" = "main" ]     && continue
  [ "$b" = "$current" ] && continue

  row="$(gh pr list --head "$b" --state merged --base main --limit 1 \
           --json number,state,mergedAt,baseRefName,headRefOid \
           --jq '(.[0] // empty) | [.number, .state, .mergedAt, .baseRefName, .headRefOid] | @tsv' \
           2>/dev/null || true)"
  [ -n "$row" ] || continue

  IFS=$'\t' read -r pr_num pr_state pr_merged pr_base pr_head <<<"$row"

  [ "$pr_state" = "MERGED" ]                          || continue
  [ -n "$pr_merged" ] && [ "$pr_merged" != "null" ]   || continue
  [ "$pr_base" = "main" ]                             || continue

  local_tip="$(git rev-parse "$b" 2>/dev/null || true)"
  if [ -z "$local_tip" ] || [ "$local_tip" != "$pr_head" ]; then
    echo "branch-cleanup: skip '$b' — local tip ${local_tip:0:12} != merged PR #$pr_num head ${pr_head:0:12}"
    continue
  fi

  if git branch -d "$b" >/dev/null 2>&1 || git branch -D "$b" >/dev/null 2>&1; then
    echo "branch-cleanup: deleted '$b' (PR #$pr_num merged into main)"
  else
    echo "branch-cleanup: could not delete '$b'"
  fi
done < <(git for-each-ref --format='%(refname:short)' refs/heads/)

# --- 2. fast-forward local main ------------------------------------------------
if [ "$(git config --bool hadur.autoUpdateMain 2>/dev/null)" = "false" ] \
   || [ -f "$(git rev-parse --git-dir)/NO_AUTO_MAIN" ]; then
  exit 0
fi

git rev-parse --verify --quiet refs/remotes/origin/main >/dev/null || exit 0
git rev-parse --verify --quiet refs/heads/main          >/dev/null || exit 0

main_local="$(git rev-parse refs/heads/main)"
main_remote="$(git rev-parse refs/remotes/origin/main)"
[ "$main_local" = "$main_remote" ] && exit 0

if git merge-base --is-ancestor refs/heads/main refs/remotes/origin/main; then
  if [ "$current" = "main" ]; then
    if git merge --ff-only --quiet origin/main 2>/dev/null; then
      echo "main: fast-forwarded to ${main_remote:0:12}"
    else
      echo "main: checked out but not cleanly fast-forwardable, left alone"
    fi
  else
    git update-ref refs/heads/main refs/remotes/origin/main
    echo "main: fast-forwarded ${main_local:0:12}..${main_remote:0:12}"
  fi
else
  echo "main: not fast-forwardable, left alone"
fi

exit 0
