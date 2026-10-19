---
name: after-merge
description: After the human merges a pipeline PR in Vadem-iOS, run the writer agent to update CHANGELOG, README and NOTES on a docs branch and open a small docs PR. Use when the user types /after-merge #P or says a PR was merged and docs should be updated.
argument-hint: "#<merged-pr-number>"
---

# /after-merge #P

You are the orchestrator. The human merged PR `P`; now the docs catch up. You never merge.

Invoking `/after-merge #P` authorizes: the writer agent committing on `docs/pr-P`, pushing that branch and opening its PR. Nothing else.

1. Parse `P` from `$ARGUMENTS`. `gh pr view P --json state,mergedAt,title` must show `MERGED`; otherwise stop and tell the user.
2. Working tree must be clean. `git switch main && git pull --ff-only && git switch -c docs/pr-P`.
3. Agent `writer`: PR `P` and the branch name. Wait for its report.
4. Check scope: `git diff --stat main..HEAD` touches only `CHANGELOG.md`, `README.md`, `NOTES.md`. Anything else → revert that file and tell the user.
5. If the writer made no commit (nothing to update), switch back to `main`, delete the branch, and tell the user.
6. Otherwise `git push -u origin docs/pr-P` and `gh pr create --base main --title "Docs: update for PR #P"` with a body listing what changed per file and the attribution footer from the session's attribution instructions.
7. Report in ≤ 3 bullets with the docs PR link. Merging is the human's.
