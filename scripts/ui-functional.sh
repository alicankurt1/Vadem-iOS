#!/usr/bin/env bash
# Hızlı işlevsel UI testleri (FunctionalFlowTests): formu aç, değer gir, kaydet, Home'da gör.
# Ekran görüntüsü ve erişilebilirlik denetimi yok (onlar scripts/ui-check.sh); bellek içi depo.
#
# Usage: scripts/ui-functional.sh
#   UI_CHECK_DEVICE   simulator name (default: "iPhone 17")
#   UI_FUNCTIONAL_ONLY  test methods, comma separated (e.g. "testAddInstallmentFromHomeShowsPaymentOnHome"); default: all
#
# Each run uses its own throw-away simulator of the same model and iOS version (deleted at the end),
# so parallel runs from other sessions or worktrees never share a device.
#
# Output: .build/ui-functional/ (build.log, test.log, result.xcresult).
# Last line is "UI-FUNCTIONAL: PASS" or "UI-FUNCTIONAL: FAIL".

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEVICE="${UI_CHECK_DEVICE:-iPhone 17}"
OUT="$ROOT/.build/ui-functional"
rm -rf "$OUT"
mkdir -p "$OUT"

fail() {
  echo "  $1"
  [ -n "${2:-}" ] && tail -30 "$2" | sed 's/^/    /'
  echo "UI-FUNCTIONAL: FAIL"
  exit 1
}

# Adı verilen simülatörün modeli ve en yeni iOS sürümü: "<deviceTypeIdentifier> <runtime>".
BASE=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
found = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if "iOS" not in runtime:
        continue
    version = tuple(int(p) for p in runtime.rsplit("iOS-", 1)[-1].split("-") if p.isdigit())
    found += [(version, d["deviceTypeIdentifier"], runtime) for d in devices if d["name"] == name]
print(" ".join(max(found)[1:]) if found else "")
' "$DEVICE")
[ -n "$BASE" ] || fail "no available simulator named '$DEVICE'"

# Ortak simülatör kullanılmaz ve kapatılmaz: aynı anda koşan başka bir oturumun testleri onu kullanıyor
# olabilir (ortak cihazda testler "signal kill" ile düşüyordu). Aynı model ve sürümde yeni bir cihaz kurulur,
# iş bitince (hata ya da kesinti dahil) silinir.
UDID=$(xcrun simctl create "ui-functional-$$" ${BASE% *} ${BASE#* }) || fail "could not create simulator for '$DEVICE'"
cleanup() {
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1
  xcrun simctl delete "$UDID" >/dev/null 2>&1
}
trap cleanup EXIT

echo "▶ simulator '$DEVICE' (own copy $UDID)"
xcrun simctl boot "$UDID" >/dev/null 2>&1
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || fail "simulator did not boot"

ONLY_TESTING=()
if [ -n "${UI_FUNCTIONAL_ONLY:-}" ]; then
  for name in ${UI_FUNCTIONAL_ONLY//,/ }; do
    ONLY_TESTING+=("-only-testing:VademUITests/FunctionalFlowTests/$name")
  done
else
  ONLY_TESTING=("-only-testing:VademUITests/FunctionalFlowTests")
fi

DEST="platform=iOS Simulator,id=$UDID"
start=$(date +%s)

echo "▶ build-for-testing"
xcodebuild build-for-testing -project Vadem.xcodeproj -scheme Vadem -destination "$DEST" -quiet \
  >"$OUT/build.log" 2>&1 || fail "build failed" "$OUT/build.log"

echo "▶ functional ui-tests"
xcodebuild test-without-building -project Vadem.xcodeproj -scheme Vadem -destination "$DEST" \
  "${ONLY_TESTING[@]}" \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 60 \
  -resultBundlePath "$OUT/result.xcresult" \
  >"$OUT/test.log" 2>&1
status=$?
echo "  done in $(( $(date +%s) - start ))s"

grep -E "^Test Case .* (passed|failed)|error:" "$OUT/test.log" | sed 's/^/  /'
if [ $status -eq 0 ]; then
  echo "UI-FUNCTIONAL: PASS"
else
  echo "Output: ${OUT#$ROOT/}/"
  echo "UI-FUNCTIONAL: FAIL"
  exit 1
fi
