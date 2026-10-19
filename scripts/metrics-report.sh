#!/usr/bin/env bash
# Renders metrics/runs.jsonl as a Markdown table (one row per pipeline run plus totals).
#
# Usage: scripts/metrics-report.sh                 print the table
#        scripts/metrics-report.sh --update-readme replace the block between
#                                                  <!-- metrics:start --> and <!-- metrics:end --> in README.md

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 - "${1:-}" <<'PY'
import json, re, sys

rows = [json.loads(line) for line in open("metrics/runs.jsonl") if line.strip()]

def findings(f):
    # blocker / major / minor / nit; "—" = adım o koşuda yoktu veya atlandı
    if not f:
        return "—"
    return " / ".join(str(f.get(k, 0)) for k in ("blocker", "major", "minor", "nit"))

def total(key, sev):
    return sum((r.get(key) or {}).get(sev, 0) for r in rows)

lines = [
    "| Issue | PR | Minutes | Verify runs (red) | Fix rounds | Review B / M / m / n | UI check B / M / m / n |",
    "|---|---|---|---|---|---|---|",
]
for r in rows:
    pr = f"#{r['pr']}" if r.get("pr") else "—"
    lines.append(
        f"| #{r['issue']} | {pr} | {r['minutes']} | {r['verify_runs']} ({r['verify_failures']}) "
        f"| {r['fix_rounds']} | {findings(r.get('review_findings'))} | {findings(r.get('ui_findings'))} |"
    )
sev = ("blocker", "major", "minor", "nit")
lines.append(
    f"| **{len(rows)} runs** | | **{sum(r['minutes'] for r in rows)}** "
    f"| **{sum(r['verify_runs'] for r in rows)} ({sum(r['verify_failures'] for r in rows)})** "
    f"| **{sum(r['fix_rounds'] for r in rows)}** "
    f"| **{' / '.join(str(total('review_findings', s)) for s in sev)}** "
    f"| **{' / '.join(str(total('ui_findings', s)) for s in sev)}** |"
)
table = "\n".join(lines)

if sys.argv[1] == "--update-readme":
    readme = open("README.md").read()
    block = f"<!-- metrics:start -->\n{table}\n<!-- metrics:end -->"
    new, n = re.subn(r"<!-- metrics:start -->.*?<!-- metrics:end -->", lambda _: block, readme, flags=re.S)
    if n != 1:
        sys.exit("README.md has no metrics block")
    open("README.md", "w").write(new)
    print("README.md metrics updated")
else:
    print(table)
PY
