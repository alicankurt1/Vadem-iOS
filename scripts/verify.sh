#!/usr/bin/env bash
# Deterministic verification gate: package unit tests + app build (incl. test targets).
# Agents write code and tests; this script decides whether they pass.
#
# Usage: scripts/verify.sh [--skip-app]
#   --skip-app   only run package tests (fast inner loop)
#
# Exit code 0 = pass, 1 = fail. Last line is always "VERIFY: PASS" or "VERIFY: FAIL".
# Logs: .build/verify/<step>.log, summary: .build/verify/last-run.json

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOG_DIR="$ROOT/.build/verify"
mkdir -p "$LOG_DIR"

SKIP_APP=0
for arg in "$@"; do
  case "$arg" in
    --skip-app) SKIP_APP=1 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

RESULTS=()   # "name|status|seconds"
FAILED=0
RUN_START=$(date +%s)

# run_step <name> <command...>
run_step() {
  local name="$1"; shift
  local log="$LOG_DIR/$name.log"
  local start end status
  printf '▶ %-14s ' "$name"
  start=$(date +%s)
  "$@" >"$log" 2>&1
  status=$?
  end=$(date +%s)
  if [ $status -eq 0 ]; then
    printf 'PASS  (%ss)\n' "$((end - start))"
    RESULTS+=("$name|pass|$((end - start))")
  else
    printf 'FAIL  (%ss)  log: %s\n' "$((end - start))" "${log#$ROOT/}"
    RESULTS+=("$name|fail|$((end - start))")
    FAILED=1
    # Önce derleyici/test hatalarını göster; yoksa log'un sonunu.
    if grep -qE "error:|✘|failed" "$log"; then
      grep -E "error:|✘|failed" "$log" | head -30 | sed 's/^/    /'
    else
      tail -30 "$log" | sed 's/^/    /'
    fi
  fi
}

run_step "package-tests" swift test --package-path Packages/VademKit

if [ $SKIP_APP -eq 0 ]; then
  # build-for-testing: uygulama + test target'ları derlenir, simülatör açılmaz.
  run_step "app-build" xcodebuild build-for-testing \
    -project Vadem.xcodeproj \
    -scheme Vadem \
    -destination 'generic/platform=iOS Simulator' \
    -quiet
fi

TOTAL=$(( $(date +%s) - RUN_START ))

# Makine tarafından okunabilir özet (ileride metrikler için).
{
  printf '{"timestamp":"%s","commit":"%s","passed":%s,"seconds":%s,"steps":[' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" \
    "$([ $FAILED -eq 0 ] && echo true || echo false)" \
    "$TOTAL"
  sep=""
  for r in "${RESULTS[@]}"; do
    IFS='|' read -r n s t <<<"$r"
    printf '%s{"name":"%s","status":"%s","seconds":%s}' "$sep" "$n" "$s" "$t"
    sep=","
  done
  printf ']}\n'
} >"$LOG_DIR/last-run.json"

echo "Total: ${TOTAL}s"
if [ $FAILED -eq 0 ]; then
  echo "VERIFY: PASS"
  exit 0
else
  echo "VERIFY: FAIL"
  exit 1
fi
