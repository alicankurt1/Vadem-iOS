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
- [ ] **Phase 12 — Notifications**: rolling window (iOS 64 pending limit). Not started; needs issues.
- [ ] **Phase 13 — Widget + App Intents (Siri)**.
- [ ] **Phase 14 — Swift Charts analytics**.
- [ ] **Phase 15 — On-device AI assistant**: Foundation Models, read-only tool calling, data/instruction separation, tests.
- [ ] **Phase 16 — Polish & release**: TR/EN, accessibility, icon, privacy manifest + policy, screenshots, App Store submission.

## Next up

1. Loose ends, small: a card list screen (an unused card cannot be deleted from the UI, found in #67); a subscription flow in `FunctionalFlowTests`; the Phase 6 screen recording.
2. Phase 12: write the first issues (schedule notifications, permission flow, rolling window), then `/ship` them.
