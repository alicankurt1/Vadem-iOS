# CLAUDE.md

Guidance for Claude Code (and its subagents) working in this repository.

## Project

**Vadem**: an iOS app that tracks credit card installments and subscriptions and answers "how much do I pay this month?". No bank connection; data is user-entered and stays on device.

The repo also hosts an **AI agent pipeline** that develops the app: issue → code → tests → verify → review + UI capture → fix → PR → (human merge) → docs. See `PLAN.md`.

## Language

- Talk to the user in **Turkish**. Keep answers short and scannable (bullets, no walls of text).
- Code comments: Turkish.
- Identifiers, commit messages, README, PLAN, CLAUDE.md, agent definitions: English.
- `NOTES.md` (learning notes): Turkish.

## Workflow rules

- After each step, explain in 3–5 short bullets: what was done, why, which concept it shows.
- **Never commit unless the user says "commit'le".** Exception: once the pipeline exists, the coder agent may commit on its own feature branch.
- **Merging is always done by the human.** Never merge PRs.
- Branch names say what the work is, never a guessed phase number: `issue/N-<slug>` (feature work, via `/ship`), `harness/<topic>` (scripts, agents, skills, UI-check plumbing), `docs/pr-P` (after merge). Commit format: `<imperative summary> (#N)` for issues, `Harness: <summary>` for harness PRs. The phase of a feature is tracked only in `PLAN.md` (each phase lists its issues and PRs); the current phase is the first one not checked there.
- At the end of each phase ask **one** interview-style question. If the user says "sen cevapla", answer it and add the answer to `NOTES.md`.
- Name the SOLID principle(s) applied in each phase and where.
- Public repo: no company names, interview references, personal notes, secrets or API keys. Team ID lives in git-ignored `Config/Local.xcconfig`.

## Build & test

- Do **not** launch the simulator or run UI tests unless asked (exception: the orchestrator during `/ship`, via `scripts/ui-check.sh` and `scripts/ui-functional.sh` in the background).
- **Verification gate** (single source of truth for pass/fail; also available as `/verify`):
  ```
  scripts/verify.sh            # package tests + app build-for-testing
  scripts/verify.sh --skip-app # package tests only (fast inner loop)
  ```
  Last line is `VERIFY: PASS` / `VERIFY: FAIL`. Logs in `.build/verify/`, summary in `.build/verify/last-run.json`.
- Never claim tests pass without a `VERIFY: PASS` on the current tree. Never weaken tests to get green.
- The shared `Vadem` scheme lives in `Vadem.xcodeproj/xcshareddata/xcschemes/`.
- **Functional UI tests** (fast, no screenshots, no accessibility audit): `scripts/ui-functional.sh` runs `VademUITests/FunctionalFlowTests` on the simulator (about 1 min, in-memory store via `-ui-sample-data`; `UI_FUNCTIONAL_ONLY=<test method>` selects tests). Last line `UI-FUNCTIONAL: PASS` / `UI-FUNCTIONAL: FAIL`. They prove the user can do the task end to end (open the form, enter values, save, see it on Home) and are separate from the capture below. A new form or flow gets a functional test (written by the test writer) before a capture test.
- **UI capture** (simulator, budget ≤ 4 min for the full gallery on iPhone 17): `scripts/ui-check.sh` builds once, then runs `VademUITests/UICheckTests` in two passes (light, dark), setting the appearance with `simctl ui … appearance` (not `XCUIDevice.appearance`, which does not apply). `UI_CHECK_ONLY` captures only the named tests: a full method name (`testAddCardForm`), the name without `test` (`addCardForm`) or a screen name (`gallery` = `testGalleryScreen`), e.g. `UI_CHECK_ONLY=addCardForm,gallery`; an unknown name fails the run and lists the available tests. `UI_CHECK_APPEARANCES=light` runs the light pass only (default `light dark`; the AX5 text variant runs in the light pass). A targeted single-test light run takes about 1 min once built; the budget above is for the full gallery only. It writes screenshots (light / dark / AX5 text, plus 600 px copies in `screenshots/small/`), **every** test failure (accessibility audit + appearance check) and non-failing notes (`notes.txt`) to `.build/ui-check/latest/`. Last line `UI-CHECK: PASS` / `UI-CHECK: FAIL`. Every new screen gets a `capture(screen:launchArguments:sections:navigate:)` test in `UICheckTests.swift` (written by the test writer):
  - `launchArguments` opens the screen directly (e.g. `["-ui-gallery"]`); never terminate and relaunch inside `navigate`.
  - Long screens are captured in parts with `sections: [.top, .scrolled(to: "<accessibilityIdentifier or label>", named: "<part>")]`; screenshots are named `<screen>-<part>__<variant>`. `.scrolled(to:)` brings the marker to the top ~15% of the screen (always below the navigation bar), so each part shows the content below its marker; give long sections their own markers (e.g. one per card). An unreachable marker fails with its frame, the bar bottom and the attempt count; a part identical to the previous one is a `[ui-note]` (end of content).
  - Each screenshot is taken after the screen stops changing (two identical frames, up to ~1.5 s), then audited. Audit issues on elements not fully visible (under the navigation bar or off screen) are notes (`[a11y-hidden]`), not failures.
  - Contrast findings of the audit are **notes**, not failures (`[a11y-contrast]`; `[a11y-flaky]` when a second measurement did not reproduce them): Apple's measurement over gradients and translucent backgrounds changes between runs of the same tree. Contrast is guaranteed by unit tests of the ratios instead (`TokenContrastTests` for token pairs, `CardContrastTests` for card faces); a new color token pair needs a pair in `TokenContrastTests.pairs`. Element-less contrast findings list the labels of content under the status bar. All other audit types still fail.
  - The light/dark check samples the **left 4 pt gutter**: screens keep their background color there (no edge-to-edge content at the left edge).
  - Every capture launches with `-ui-static-motion`. **The app must honor it** by stopping continuous animations (e.g. drifting meshes, `TimelineView(.animation)`), otherwise the accessibility audit never sees an idle app and times out.
  - An audit that fails to complete is reported as `[a11y] … audit did not complete` and the run continues with the next part and variant.

## Agent pipeline

Agents live in `.claude/agents/`. The main session is the **orchestrator**: it plans, delegates to subagents, runs the gate and reports. Subagents cannot spawn other subagents.

| Role | Definition | Writes |
|---|---|---|
| Coder | `.claude/agents/coder.md` | Production code only |
| Test writer | `.claude/agents/test-writer.md` | Tests only, from acceptance criteria |
| Verify | `scripts/verify.sh` (not an agent) | Pass/fail verdict |
| Reviewer | `.claude/agents/reviewer.md` | Nothing (read-only tools); returns findings |
| UI capture | `scripts/ui-check.sh`, run by the orchestrator (the `ui-checker` agent is off) | Nothing; summary lines, screenshots on demand |
| Writer | `.claude/agents/writer.md` | Docs only (`CHANGELOG.md`, `README.md`, `NOTES.md`), after merge |

**Commands** (skills in `.claude/skills/`):
- `/ship #N` — the whole pipeline for issue N: plan (waits for "ok") → coder → test writer → verify → reviewer + background UI capture (if UI is touched) → fix loop (max 2 review rounds) → push + PR → metrics. The procedure lives in `.claude/skills/ship/SKILL.md`; "do #N" means the same.
- `/after-merge #P` — after the human merges PR P: writer agent updates docs on `docs/pr-P` and opens a docs PR.
- `/verify` — the gate on its own.

Harness / factory problems found during a run (`scripts/`, `UICheckTests` plumbing, agent definitions) are never fixed on the issue branch; they get their own `harness/<topic>` PR first.

**Visible mode** (on request): instead of subagents, each role runs as its own session in the desktop app (split view), started one at a time in this checkout. The session's brief says: "Read `.claude/agents/<role>.md` and act as that role" plus the issue and branch. The orchestrator relays only what the next role needs, same as with subagents.

Rules:
- Cost: the orchestrator (main session) runs on Sonnet (personal `.claude/settings.local.json`); the coder is pinned to Opus, the other agents to Sonnet. One issue per chat.
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
  - `VademTestSupport` — test-only helpers used by every test target: `Fixture` (valid test values) and `PaymentRepositoryContract` (the repository behaviour every implementation must have). Each implementation runs the whole contract with one parameterized test: `@Test(arguments: <factories>, PaymentRepositoryContract.scenarios)`. A new repository rule = a new scenario here, never a test that only one implementation runs.
- Swift 6 language mode, strict concurrency. **Default actor isolation is off**; write `@MainActor` explicitly.
- Deployment target iOS 18. Newer APIs (e.g. FoundationModels, iOS 26) behind `@available`.
- Money is `Decimal`, never `Double`.
- Tests: Swift Testing for unit tests, XCUITest for UI tests.
- No third-party dependencies without discussing first.
- Build settings live in `Config/Shared.xcconfig` (all targets) and `Config/App.xcconfig` (app target: includes Shared, adds `CODE_SIGN_ENTITLEMENTS = Config/Vadem.entitlements` with the App Group); keep target-level overrides in the `.pbxproj` empty.
