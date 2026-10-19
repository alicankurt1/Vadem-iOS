# CLAUDE.md

Guidance for Claude Code (and its subagents) working in this repository.

## Project

**Vadem**: an iOS app that tracks credit card installments and subscriptions and answers "how much do I pay this month?". No bank connection; data is user-entered and stays on device.

The repo also hosts an **AI agent pipeline** that develops the app: issue → code → tests → verify → review → fix → UI check → PR → (human merge) → docs. See `PLAN.md`.

## Language

- Talk to the user in **Turkish**. Keep answers short and scannable (bullets, no walls of text).
- Code comments: Turkish.
- Identifiers, commit messages, README, PLAN, CLAUDE.md, agent definitions: English.
- `NOTES.md` (learning notes): Turkish.

## Workflow rules

- After each step, explain in 3–5 short bullets: what was done, why, which concept it shows.
- **Never commit unless the user says "commit'le".** Exception: once the pipeline exists, the coder agent may commit on its own feature branch.
- **Merging is always done by the human.** Never merge PRs.
- One branch per phase: `phase-N/<topic>`. Commit format: `Phase N: <summary>`.
- At the end of each phase ask **one** interview-style question. If the user says "sen cevapla", answer it and add the answer to `NOTES.md`.
- Name the SOLID principle(s) applied in each phase and where.
- Public repo: no company names, interview references, personal notes, secrets or API keys. Team ID lives in git-ignored `Config/Local.xcconfig`.

## Build & test

- Do **not** launch the simulator or run UI tests unless asked (exception: the UI check agent in the pipeline).
- **Verification gate** (single source of truth for pass/fail; also available as `/verify`):
  ```
  scripts/verify.sh            # package tests + app build-for-testing
  scripts/verify.sh --skip-app # package tests only (fast inner loop)
  ```
  Last line is `VERIFY: PASS` / `VERIFY: FAIL`. Logs in `.build/verify/`, summary in `.build/verify/last-run.json`.
- Never claim tests pass without a `VERIFY: PASS` on the current tree. Never weaken tests to get green.
- The shared `Vadem` scheme lives in `Vadem.xcodeproj/xcshareddata/xcschemes/`.

## Agent pipeline

Agents live in `.claude/agents/`. The main session is the **orchestrator**: it plans, delegates to subagents, runs the gate and reports. Subagents cannot spawn other subagents.

| Role | Definition | Writes |
|---|---|---|
| Coder | `.claude/agents/coder.md` | Production code only |
| Test writer | `.claude/agents/test-writer.md` | Tests only, from acceptance criteria |
| Verify | `scripts/verify.sh` (not an agent) | Pass/fail verdict |
| Reviewer | `.claude/agents/reviewer.md` | Nothing (read-only tools); returns findings |

When the user says "do #N" (until `/ship` exists in Phase 5):
1. Read the issue, write a short plan (files, approach, risks) and show it to the user. Wait for "ok".
2. Branch: `issue/N-<slug>` from up-to-date `main`.
3. **Coder** → implements and commits.
4. **Test writer** → writes tests from the acceptance criteria and commits.
5. **Verify** → run `scripts/verify.sh` yourself. On FAIL, send the output back to the coder (max 3 rounds), then rerun verify.
6. **Reviewer** → reviews `main...HEAD`. Give it the issue and branch only.
7. **Fix loop** → on `CHANGES_REQUESTED`, send `blocker`/`major` findings (and cheap `minor`s) to the coder; test gaps go to the test writer. Verify again, then one re-review of the fix commits. Max 2 review rounds; anything left goes to the PR description.
8. Report to the user in short bullets; push and open the PR only when the user asks. The PR description includes the review findings and their status (fixed / open).
9. Append one line to `metrics/runs.jsonl` (format in `metrics/README.md`).

**Visible mode** (on request): instead of subagents, each role runs as its own session in the desktop app (split view), started one at a time in this checkout. The session's brief says: "Read `.claude/agents/<role>.md` and act as that role" plus the issue and branch. The orchestrator relays only what the next role needs, same as with subagents.

Rules:
- Branch per issue: `issue/N-<slug>`. Commits: `<imperative summary> (#N)`.
- Agents commit only on the issue branch; they never push, open PRs or merge.
- Agent comments on GitHub start with their role, e.g. `**[Review agent]**`.
- Coder and test writer get the issue, not each other's reasoning; independence is the point.

## Architecture

- SwiftUI + Observation (`@Observable`), MVVM.
- `Vadem/` — thin app target (entry point only).
- `Packages/VademKit/` — local Swift package:
  - `VademCore` — pure domain. Must not import UIKit, SwiftUI or SwiftData. Builds on macOS so `swift test` works.
  - `VademFeatures` — SwiftUI screens and view models.
- Swift 6 language mode, strict concurrency. **Default actor isolation is off**; write `@MainActor` explicitly.
- Deployment target iOS 18. Newer APIs (e.g. FoundationModels, iOS 26) behind `@available`.
- Money is `Decimal`, never `Double`.
- Tests: Swift Testing for unit tests, XCUITest for UI tests.
- No third-party dependencies without discussing first.
- Build settings live in `Config/Shared.xcconfig`; keep target-level overrides in the `.pbxproj` empty.
