# Pipeline metrics

One JSON object per pipeline run in `runs.jsonl`, appended by the orchestrator at the end of a run.

| Field | Meaning |
|---|---|
| `date` | Run date (`YYYY-MM-DD`) |
| `issue` | Issue number |
| `phase` | Phase the pipeline was in when the run happened |
| `minutes` | Wall-clock duration from "do #N" to PR (or stop) |
| `verify_runs` | Total `scripts/verify.sh` runs |
| `verify_failures` | Runs that ended in `VERIFY: FAIL` |
| `fix_rounds` | Times work went back to the coder (red verify or review) |
| `bugs_caught_by_tests` | Failing tests written by the test-writer that exposed real code bugs |
| `review_findings` | Findings by severity, e.g. `{"blocker":0,"major":0,"minor":2,"nit":1}` (from Phase 3) |
| `ui_findings` | UI check findings by severity, or `null` when skipped (from Phase 4) |
| `pr` | PR number, or `null` |
| `notes` | One short line |
