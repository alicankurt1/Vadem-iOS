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

## Phases

### Pipeline (local)
- [x] **Phase 0 — Foundation**: Xcode project, SwiftUI skeleton, Swift package modules, Swift 6 settings, docs, smoke test, `gh`.
- [x] **Phase 1 — Verify script**: `scripts/verify.sh` (build + unit tests) and a `/verify` skill.
- [x] **Phase 2 — Coder + test writer subagents**: end-to-end trial on a small issue.
- [x] **Phase 3 — Review subagent**: findings format (severity, file:line), fix loop.
- [ ] **Phase 4 — UI check subagent**: deterministic screenshot capture + agent evaluation.
- [ ] **Phase 5 — Orchestrator**: `/ship #N` skill, PR creation, writer subagent.
- [ ] **Phase 6 — Showcase**: first feature through the pipeline, screen recording, README diagram + metrics.
- [ ] **Phase 7 — Cloud (optional)**: GitHub Actions CI + automatic PR review agent.

### Features
- [ ] **Phase 8 — Domain (TDD)**: `Money`, `Installment`, `Subscription`, schedule calculations, table tests. Starts with an ADR on rounding, statement/due days, month-end rules. v1: TRY only.
- [ ] **Phase 9 — Persistence**: SwiftData with `VersionedSchema` and App Group container from day one.
- [ ] **Phase 10 — Home**: this month's payments, calendar, upcoming months.
- [ ] **Phase 11 — Forms**: add/edit with validation.
- [ ] **Phase 12 — Notifications**: rolling window (iOS 64 pending limit).
- [ ] **Phase 13 — Widget + App Intents (Siri)**.
- [ ] **Phase 14 — Swift Charts analytics**.
- [ ] **Phase 15 — On-device AI assistant**: Foundation Models, read-only tool calling, data/instruction separation, tests.
- [ ] **Phase 16 — Polish & release**: TR/EN, accessibility, icon, privacy manifest + policy, screenshots, App Store submission.
