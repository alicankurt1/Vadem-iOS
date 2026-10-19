---
name: verify
description: Run the deterministic verification gate (package unit tests + app build including test targets) and report the result. Use after any code change, before review, before opening a PR, or when the user types /verify.
argument-hint: "[--skip-app]"
allowed-tools: Bash(scripts/verify.sh:*), Read
---

# /verify

Run the project's verification gate and report its verdict. The script decides pass/fail, not you.

## Steps

1. Run from the repo root:
   ```
   scripts/verify.sh $ARGUMENTS
   ```
   Use `--skip-app` only for a fast inner loop on package-only changes. Before review or a PR, always run without it.
2. The last line is `VERIFY: PASS` or `VERIFY: FAIL`. Exit code 0 / 1 matches it.
3. Report in at most 5 bullets:
   - Verdict (PASS / FAIL) and total time.
   - On FAIL: each failing step, the first errors with `file:line`, and the log path (`.build/verify/<step>.log`). Read the log if the printed excerpt is not enough.

## Rules

- Never claim tests pass without this script's `VERIFY: PASS` from the current working tree.
- Never edit, skip, or weaken tests (or the script) to make the gate green. Fix the code, or report the failure.
- Do not launch the simulator or run UI tests here; the script only builds test targets.
- The run summary is written to `.build/verify/last-run.json` (used for pipeline metrics).
