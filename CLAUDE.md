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

- Do **not** launch the simulator or run UI tests unless asked (exception: the UI check agent in the pipeline, via `scripts/ui-check.sh`).
- **Verification gate** (single source of truth for pass/fail; also available as `/verify`):
  ```
  scripts/verify.sh            # package tests + app build-for-testing
  scripts/verify.sh --skip-app # package tests only (fast inner loop)
  ```
  Last line is `VERIFY: PASS` / `VERIFY: FAIL`. Logs in `.build/verify/`, summary in `.build/verify/last-run.json`.
- Never claim tests pass without a `VERIFY: PASS` on the current tree. Never weaken tests to get green.
- The shared `Vadem` scheme lives in `Vadem.xcodeproj/xcshareddata/xcschemes/`.
- **UI capture** (simulator, ~1–2 min): `scripts/ui-check.sh` builds once, then runs `VademUITests/UICheckTests` in two passes (light, dark), setting the appearance with `simctl ui … appearance` (not `XCUIDevice.appearance`, which does not apply). It writes screenshots (light / dark / AX5 text), **every** test failure (accessibility audit + appearance check) to `.build/ui-check/latest/`. Last line `UI-CHECK: PASS` / `UI-CHECK: FAIL`. Every new screen gets a `capture(screen:)` test in `UICheckTests.swift` (written by the test writer).

## Agent pipeline

Agents live in `.claude/agents/`. The main session is the **orchestrator**: it plans, delegates to subagents, runs the gate and reports. Subagents cannot spawn other subagents.

| Role | Definition | Writes |
|---|---|---|
| Coder | `.claude/agents/coder.md` | Production code only |
| Test writer | `.claude/agents/test-writer.md` | Tests only, from acceptance criteria |
| Verify | `scripts/verify.sh` (not an agent) | Pass/fail verdict |
| Reviewer | `.claude/agents/reviewer.md` | Nothing (read-only tools); returns findings |
| UI check | `.claude/agents/ui-checker.md` + `scripts/ui-check.sh` | Nothing; returns visual / a11y findings |
| Writer | `.claude/agents/writer.md` | Docs only (`CHANGELOG.md`, `README.md`, `NOTES.md`), after merge |

**Commands** (skills in `.claude/skills/`):
- `/ship #N` — the whole pipeline for issue N: plan (waits for "ok") → coder → test writer → verify → reviewer → UI check (if UI is touched) → fix loop (max 2 review rounds) → push + PR → metrics. The procedure lives in `.claude/skills/ship/SKILL.md`; "do #N" means the same.
- `/after-merge #P` — after the human merges PR P: writer agent updates docs on `docs/pr-P` and opens a docs PR.
- `/verify` — the gate on its own.

Harness / factory problems found during a run (`scripts/`, `UICheckTests` plumbing, agent definitions) are never fixed on the issue branch; they get their own `phase-N/...` PR first.

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
  - `VademCore` — pure domain. Must not import UIKit, SwiftUI or SwiftData. Builds on macOS so `swift test` works. Defines **repository protocols** (what the app needs to save and load), never their storage.
  - `VademPersistence` — the **only** module that imports SwiftData. `@Model` record classes, mapping to/from `VademCore` value types, and SwiftData implementations of the repository protocols. Schema is versioned from day one (`VersionedSchema` + `SchemaMigrationPlan`); never change a shipped schema version in place, add a new one. The store lives in the App Group container (`VademPersistence.appGroupIdentifier`), tests use an in-memory container.
  - `VademFeatures` — SwiftUI screens and view models. Depends on repository protocols, not on SwiftData.
- Swift 6 language mode, strict concurrency. **Default actor isolation is off**; write `@MainActor` explicitly.
- Deployment target iOS 18. Newer APIs (e.g. FoundationModels, iOS 26) behind `@available`.
- Money is `Decimal`, never `Double`.
- Tests: Swift Testing for unit tests, XCUITest for UI tests.
- No third-party dependencies without discussing first.
- Build settings live in `Config/Shared.xcconfig` (all targets) and `Config/App.xcconfig` (app target: includes Shared, adds `CODE_SIGN_ENTITLEMENTS = Config/Vadem.entitlements` with the App Group); keep target-level overrides in the `.pbxproj` empty.
