# Plan

Pipeline first, features second. Early phases keep the app nearly empty; the goal is to run the chain end to end. Small domain issues (Phase 8) are used as the pipeline's first real work items.

## Agent pipeline (local, Claude Code subagents)

```
Human opens an issue → "do #12"
  → Orchestrator (main session): reads issue, plans, shows plan
  1. Coder subagent: branch + code
  2. Test writer subagent: unit tests
  3. Verify script (not an agent): build + swift test; red → back to coder
  4. Review subagent: findings by severity with file:line
  5. Coder subagent: fixes findings; verify reruns
  6. UI check subagent: simulator screenshots, visual/a11y report
  7. PR opened via gh: description + findings + screenshots
  → Human reviews and merges                                   ← human gate
  8. Writer subagent: CHANGELOG / NOTES / README
```

Principles:
- Agents **write** tests; a deterministic script **runs** them.
- The coder never approves its own code; review is a separate role with separate instructions.
- Merge is always human.
- Every agent instruction is versioned in the repo (`.claude/agents/`, `CLAUDE.md`, skills).
- Each run's duration and caught issues are recorded (`metrics/`), starting from Phase 2.

## How we work (read this first)

- **One source of truth for "where are we":** this file. The current phase is the first one below that is not `[x]`. After a PR merges, `/after-merge` (writer) ticks items here.
- **Feature work** = a GitHub issue → `/ship #N` → branch `issue/N-<slug>` → PR. The issue belongs to a phase listed below.
- **Harness work** (scripts, agents, skills, UI-check plumbing) = branch `harness/<topic>`, commit `Harness: <summary>`. It has no phase number.
- **Docs after merge** = `docs/pr-P` (writer agent).
- One issue per chat; a new chat starts by reading this file and `gh issue list`.
- History note: until PR #71, harness PRs were named `phase-N/...` with whatever feature phase was current (e.g. `phase-10/ui-check-*`, `phase-12/ui-check-targeted`). Those numbers are historical labels, not phases of this plan.

## Phases

### Pipeline (local)
- [x] **Phase 0 — Foundation**: Xcode project, SwiftUI skeleton, Swift package modules, Swift 6 settings, docs, smoke test, `gh`.
- [x] **Phase 1 — Verify script**: `scripts/verify.sh` (build + unit tests) and a `/verify` skill.
- [x] **Phase 2 — Coder + test writer subagents**: end-to-end trial on a small issue.
- [x] **Phase 3 — Review subagent**: findings format (severity, file:line), fix loop.
- [x] **Phase 4 — UI check subagent**: deterministic screenshot capture + agent evaluation (later made lean: no agent, `scripts/ui-check.sh`).
- [x] **Phase 5 — Orchestrator**: `/ship #N` skill, PR creation, writer subagent.
- [ ] **Phase 6 — Showcase**: README diagram + metrics report are merged (PR #18); the screen recording is still missing.
- [ ] **Phase 7 — Cloud (optional)**: GitHub Actions CI + automatic PR review agent.

### Features
- [x] **Phase 8 — Domain (TDD)**: `Money`, `YearMonth`, `InstallmentPlan`, `Subscription`, `Card`, tracked items, `MonthlySchedule` (#4, #7, #15, #19, #23, #26, #42).
- [x] **Phase 9 — Persistence**: SwiftData with `VersionedSchema` and App Group container (#30, PRs #22, #29).
- [x] **Phase 10 — Home**: design system, this month's payments, upcoming months, calendar (#33, #36, #45, #50, #53).
- [x] **Phase 11 — Forms**: add installment (#62), add card (#65), add subscription (#66), edit and delete (#67, PR #74).
- [x] **Design refresh (B2b, between phases 11 and 12)**: teal palette, bold hero panel. Tokens (#77, PRs #78, #79), `Design/` components (#82, PR #83), Home (#85, PR #86), forms (#88, PR #89), upcoming chips and calendar (#91, PR #92).
- [x] **Phase 12 — Notifications**: pure planner with the rolling 63 of 64 window (#95, PR #96), scheduler and permission flow (#98, PR #99), settings sheet with toggle and timing (#101, PR #102). The real permission alert is only checked by hand.
- [x] **Phase 13 — Widget + App Intents (Siri)**: pure payment summary (#105, PR #106), App Intents and Siri shortcuts (#108, PR #109), home-screen widget extension (#111, PR #112). The App Group for the widget's bundle id and the Siri/widget behaviour are only checked by hand on a device.
- [x] **Phase 14 — Swift Charts analytics**: pure spending analytics (#115, PR #118), monthly totals bar chart screen (#116, PR #119), card breakdown donut and debt-free insight (#117, PR #122). Chart rendering and VoiceOver reading are only checked by hand on a device.
- [x] **Phase 15 — On-device AI assistant**: read-only queries and tools (#125, PR #128), Foundation Models engine (#126, PR #130), chat screen (#127, PR #132). The real model is only checked by hand on an iOS 26 device with Apple Intelligence.
- [ ] **Phase 16 — Polish & release**: String Catalog (#135, PR #140), Turkish translation (#136, PR #143; parity test #174, PR #178), accessibility passes (#137, PR #145; #175, PR #179), privacy manifest and policy (#138, PR #149; #171; #172, PR #184), app icon and listing (#139, PR #151; #173), App Store screenshot script (#176, PR #182). Feedback fixes: Home header (#154, PR #157), optional card for installments (#155, PR #161), reminder permission retry (#156, PR #159), Cards screen (#165, PR #167), subscription functional tests (#166, PR #169). Still open: the App Store submission itself.
- [x] **Phase 17 — Quick add flows**: one-time payment domain and persistence, schema V3 (#187, PR #193), Add sheet shell and shared step components (#188, PR #194), installment (#189, PR #196), subscription (#190, PR #198) and one-time payment (#192, PR #201) as quick steps, one-time payments across the app (#191, PR #197).
- [x] **Phase 18 — Home and picker polish**: day-of-month bottom picker instead of a stepper (#203, PR #206), selected day's payments above By card (#204, PR #205).
- [x] **Phase 19 — Visual redesign**: floating glass tab bar (#208, PR #217), ambient animated background per tab (#209, PR #219), smooth tab transitions and staggered entry (#210, PR #220), serif titles and glass surfaces (#211, PR #221).
- [x] **Redesign feedback (between phases 20 and 21)**: system font back (#228, PR #239), navigation bar blends with the tab background (#229, PR #247), monthly total moved into the hero card (#230, PR #245), payments above By card (#231, PR #243), last rows above the tab bar (#232, PR #234), tab switching without a blank frame (#233, PR #236). The navigation bar on iOS 18 (no edge blur) is only checked by hand.
- [x] **Phase 20 — Insights and inbox**: monthly comparison insight and summary notification (#212, PR #223), in-app notification inbox with schema V4 (#213, PR #225).
- [x] **Phase 21 — Statement import**: statement line parser (#214, PR #227), statement text from PDF and images with on-device OCR (#215, PR #250), review and confirm imported installments (#216, PR #252). Import with a real bank statement is only checked by hand on a device.

## Next up

1. Loose ends: the Phase 6 screen recording (#177); tapping a notification while a sheet is open shows the inbox behind the sheet (found in #213).
2. Try by hand on a device: reminder permission, widget, Siri, assistant, statement import with a real PDF and photo, navigation bar on iOS 18. Then the App Store submission (Phase 16).
