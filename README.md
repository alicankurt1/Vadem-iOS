# Vadem

An iOS app that tracks credit card installments and subscriptions and answers one question: **how much do I pay this month?**

No bank connection. Data is entered by the user and never leaves the device.

This repository is also an experiment in **developing with an AI agent team**: coder, test writer, reviewer, UI checker and writer agents take an issue all the way to a pull request, and a human merges it. See [PLAN.md](PLAN.md).

## Status

🚧 Phase 2 — Coder + test writer agents

## Stack

- SwiftUI, Observation, MVVM
- Swift 6 (strict concurrency), iOS 18+
- Local Swift package (`Packages/VademKit`) with a pure domain module tested via `swift test`
- Swift Testing, XCUITest
- No third-party dependencies

## Getting started

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig   # set your DEVELOPMENT_TEAM
open Vadem.xcodeproj
```

Verify (package unit tests + app build, no simulator):

```bash
scripts/verify.sh
```

## License

TBD
