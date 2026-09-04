# Git Discipline — project-hadur

The single reference for how git is used in this project. Treated as **team
practice even though the project is solo** — the point is to demonstrate the
discipline, not to take shortcuts a team wouldn't.

Decisions that back this doc: `decision-log.md` D-008, D-011, D-012, D-013, D-014.

---

## 1. Branch model

- **Always branch off `main`. Never commit to `main` directly.** Every change —
  code, docs, config — lands via a pull request.
- **One concern per branch.** A branch is one reviewable, revertable unit: "why
  does this change exist." If two changes are unrelated, they get two branches
  (see §4).
- **Naming:**
  - Pre-Jira: `type/short-slug` — e.g. `docs/git-discipline`,
    `chore/branch-cleanup-hook`. The `type/` prefix matches the dominant
    Conventional Commit type of the branch's concern.
  - Once the Jira board exists: `hadur-<n>-<short-slug>`.
  - If a branch's scope outgrows its name, **rename it** (`git branch -m`) rather
    than letting the name lie.

## 2. Commits

- **Conventional Commits** for every commit message: `type: summary` in the
  imperative mood. Types used here: `feat`, `fix`, `docs`, `chore`, `test`,
  `refactor`, `build`, `ci`.
- **Atomic:** one logical change per commit — buildable and revertable on its own.
- **Mixed types on one branch are normal.** A branch carries whatever commit types
  serve its one concern; `type:` labels the *commit*, not the branch. Conventional
  Commits is a per-commit spec.
- Once Jira exists: at least one commit per branch carries a smart-commit tag
  (`HADUR-<n> ...`); the squash-merge message carries `HADUR-<n> #done`.

## 3. Pull requests

- **Claude Code may open PRs** — `git push` a feature branch, then `gh pr create`.
  This is durably authorized (D-012); no per-PR human approval to *open*.
- **Only a human merges.** Every merge into `main` is done by a person on
  github.com. The `code-reviewer` subagent and the CI review are **advisory**;
  the human merge is the gate (D-012).
- **PR body template:** what changed / why · ticket link · test evidence ·
  `code-reviewer` findings + resolution · handoff notes for the reviewer.
- **Squash-merge only.** `main` keeps a linear history; one commit per PR.

## 4. Separation of concerns & independent revertability

- **Decide branch/PR boundaries by *concern*, not by file type or commit type.**
  The test: would you ever want to merge one part without the other? If yes,
  they're separate concerns.
- **Two independent concerns → two branches / two PRs**, even when that costs an
  extra small PR. The payoff is:
  - **Independent revertability** — `git revert` one PR without dragging the
    other's changes along. A mixed PR is all-or-nothing.
  - **Focused review** — each diff is one idea to accept or reject.
- Git merging overlapping changes cleanly is *not* the reason to combine — git
  handles overlap fine, and a clean merge is not proof the combined result is
  correct (semantic conflicts pass silently).
- **Decision vs. implementation** are usually two concerns: the decision record
  in `decision-log.md` on one branch, the code/config that implements it on
  another. Precedent: D-012/D-013 (docs) vs. `.claude/settings.json` (chore);
  D-014 (docs) vs. the branch-cleanup hook (chore).

## 5. Branch protection on `main` (D-013)

Classic branch protection, **admin-enforced** (applies to the repo owner too):

| Rule | Value |
|---|---|
| Require a pull request | yes, **0 approvals** (solo repo; GitHub forbids self-approval) |
| Enforce for administrators | yes |
| Require conversation resolution | yes |
| Require linear history | yes |
| Force pushes | blocked |
| Branch deletion | blocked |
| Required status checks | none yet — CI review check added in Phase 2 |

Why admin-enforced: Claude Code runs `git`/`gh` with the owner's credentials, so
`.claude/settings.json` permissions alone don't bind it if misconfigured.
Server-side protection makes "Claude never pushes to or merges `main`" a
mechanical fact. Emergency bypass = toggle admin enforcement off, act, toggle
back; the friction is intended.

## 6. Automated local branch cleanup + `main` fast-forward (D-014)

A `SessionStart` hook (`.claude/hooks/prune-merged-branches.sh`, wired in
`.claude/settings.json`) runs at the start of every Claude Code session. It does
**exactly two mutations**, both narrowly guarded:

### 6a. Delete a local branch — merged-PR-only

A local branch `B` is deleted **if and only if all four hold**:

1. A PR exists with head `B`, base `main`, state `MERGED` (`mergedAt` non-null,
   `mergeCommit` present) — confirmed via the GitHub API (`gh`), not git's local
   merge detection.
2. `B`'s local tip SHA **equals** that PR's `headRefOid` — the exact commit that
   merged. Proves nothing local is lost.
3. `B` is not `main`.
4. `B` is not the currently checked-out branch.

Never a trigger: `origin/B` being gone; PR state `CLOSED`; no PR found;
`git branch --merged` ancestry; a force-pushed remote. Any of those → skip and
log the reason.

### 6b. Fast-forward local `main`

After `git fetch --prune`, advance local `main` to `origin/main` **only when it is
a clean fast-forward**:

- If on another branch: move the `main` ref without checking it out — working tree
  and current branch untouched.
- If `main` is checked out: `git merge --ff-only`; if it can't apply cleanly,
  skip.
- Never a merge commit, never `--force`, never a rebase. Never touches feature
  branches — incorporating new `main` into feature work stays a deliberate
  `git rebase main`.
- Not fast-forwardable (local commits on `main`, rewritten remote) → leave `main`
  alone and log it.
- **Opt-out** for deliberate pinning (`git bisect`, holding a reference point):
  `git config hadur.autoUpdateMain false`, or a `.git/NO_AUTO_MAIN` sentinel
  file. Branch cleanup still runs; only the `main` fast-forward is suppressed.

### Fail-safe

Not in a git repo, `gh` missing/unauthenticated, or offline → the hook does
nothing and exits 0. It can never block or error a session. It prints only when
it actually acts (deletion, skip-with-reason, fast-forward).

## 7. Commit / push authorization

- **Commit only when the user explicitly says so, in that moment** — not
  proactively, not as a side effect of finishing a task.
- **Push only when the user explicitly says so, in that moment.** The instruction
  is the authorization; no extra confirmation for a normal push. Riskier
  operations (force-push, diverged branch, unexpected branch) still get flagged
  first.
- `.claude/settings.json` encodes this: `allow` `git push` / `gh pr create`;
  `deny` `gh pr merge` / `git push --force`.

## 8. Remote transport

- `origin` uses **HTTPS** for both fetch and push:
  `https://github.com/m-ames1/project-hadur.git`.
- Credentials come from the `gh` OAuth token in the macOS keychain, via a
  repo-local credential helper (`credential.https://github.com.helper=!gh auth
  git-credential`). No token is stored in `.git/config` or any URL.
- `fetch.prune = true` (repo-local): every fetch drops `origin/*` refs for
  branches deleted on the remote (GitHub auto-deletes head branches on merge).
- SSH was the original choice but isn't usable from the Claude Code sandbox (no
  key in the agent); HTTPS + the `gh` token is the same path pushes already used.
  Reversible with `git remote set-url origin git@github.com:m-ames1/project-hadur.git`.
