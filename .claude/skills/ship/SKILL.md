---
name: ship
description: Run the full Vadem-iOS agent pipeline for one GitHub issue — plan, coder, test writer, verify, reviewer, UI check, fix loop, PR and metrics — as the orchestrator. Use when the user types /ship #N or asks to ship / do issue #N.
argument-hint: "#<issue-number>"
---

# /ship #N

You are the **orchestrator** (main session). You plan, delegate to subagents, run the gates, relay findings, open the PR and record metrics. You do not write production code or tests yourself; agents do. You never merge.

Invoking `/ship #N` authorizes, for this issue only: agents committing on `issue/N-<slug>`, pushing that branch, opening its PR and committing the metrics line. Nothing else.

## 0. Start

- Parse `N` from `$ARGUMENTS` (accept `#12` or `12`). If missing, ask.
- Record the start time: `date +%s > .build/ship-N.start` (create `.build/` if needed).
- Working tree must be clean (`git status --short` empty). If not, stop and ask.

## 1. Plan (human gate)

- `gh issue view N --comments`. Stop if the issue is closed or has no acceptance criteria.
- Show the user a plan in ≤ 8 bullets: files/modules, approach, risks, whether UI check will run (diff touches `Vadem/`, `VademFeatures`, `VademUITests/`), and the branch name `issue/N-<slug>`.
- **Wait for "ok".** This is the only stop before the PR, apart from escalations below.

## 2. Branch

`git switch main && git pull --ff-only && git switch -c issue/N-<slug>`.

## 3. Coder → Test writer → Verify

1. Agent `coder`: issue N, branch, the approved plan. Wait for its report.
2. Check scope yourself: `git diff --stat main..HEAD`. Production files only; nothing under `scripts/`, `.claude/`, `.github/`, `Config/`.
3. Agent `test-writer`: issue N and branch only. **Do not pass the coder's report or reasoning.**
4. Check scope: test files only; grep the diff for `.disabled`, `withKnownIssue`, `#expect(true)`, deleted tests.
5. Run `scripts/verify.sh` yourself. On FAIL, send the failing output to the coder (or to the test writer if a test is wrong to compile). Max 3 rounds, then escalate.

Tell the user one line after each agent returns (who, what, verify result).

## 4. Review → UI check

1. Agent `reviewer`: issue N and branch only.
2. If UI is touched: agent `ui-checker`: issue N and branch. Otherwise skip and note "UI check skipped (domain-only)".
3. Collect findings. Classify each as **product** (coder / test writer) or **harness** (`scripts/`, `UICheckTests` plumbing, agent definitions).

## 5. Fix loop (max 2 rounds)

- `blocker` / `major` / cheap `minor` product findings → coder; test gaps → test writer. Same independence rule: send findings, not the other agent's reasoning.
- After fixes: verify, then re-review only `git diff <reviewed-head>..HEAD`, and re-run UI check only if UI changed.
- **Harness findings are never fixed on the issue branch.** Stop and tell the user: the factory needs its own `phase-N/...` PR first (as in #10 / PR #11).
- After 2 rounds, remaining `minor` / `nit` findings go to the PR as "accepted" or "open". Remaining `blocker` / `major` → escalate, no PR.

## 6. PR

1. `git push -u origin issue/N-<slug>`.
2. `gh pr create --base main` with title `<summary> (#N)` and a body containing:
   - `Closes #N`, a short summary of changes (from the diff, not from agent self-praise).
   - **Review** and **UI check** tables: round, severity, finding, status (✅ fixed + sha / accepted + reason / open).
   - **Verification:** last `VERIFY:` and `UI-CHECK:` lines.
   - **Metrics** line (see 7).
   - The PR attribution footer from the session's attribution instructions.

## 7. Metrics

Append one line to `metrics/runs.jsonl` (fields in `metrics/README.md`), with the real PR number, minutes from `.build/ship-N.start`, and counts you observed (verify runs/failures, fix rounds, findings by severity, `ui_findings` or `null`). Validate it parses as JSON. Commit `Record pipeline metrics for run (#N)` with the attribution trailer and push (the PR updates).

## 8. Report

Five bullets max to the user: PR link, what changed, what the gates found, what is accepted/open, and that merging is theirs. Then remind: after merge, `/after-merge #<PR>` runs the writer agent.

## Escalate (stop and ask the user) when

- verify stays red after 3 coder rounds, or blocker/major findings remain after 2 review rounds;
- a finding is a harness/factory problem;
- an agent touched files outside its role, or asks to;
- the issue is ambiguous enough that the plan needs a decision.
