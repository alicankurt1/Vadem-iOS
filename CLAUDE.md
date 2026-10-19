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
- Compile check:
  ```
  xcodebuild build -project Vadem.xcodeproj -scheme Vadem -destination 'generic/platform=iOS Simulator' -quiet
  ```
- Unit tests (business rules, no simulator):
  ```
  swift test --package-path Packages/VademKit
  ```

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
