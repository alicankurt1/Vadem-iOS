#!/usr/bin/env bash
# App Store screenshots: runs VademUITests/AppStoreScreenshotTests for each device and language and
# collects the PNGs in a git-ignored folder. Data comes from the in-memory `-ui-sample-data` store, so
# no personal data appears. No accessibility audit or text-size variants (that is scripts/ui-check.sh).
#
# Usage: scripts/appstore-screenshots.sh
#   APPSTORE_DEVICES    simulator names, comma separated (default: "iPhone 17 Pro Max" = 6.9" display,
#                       1320x2868). Add "iPad Pro 13-inch (M5)" (2064x2752) if the app ships on iPad.
#   APPSTORE_LANGUAGES  languages, space separated (default: "en tr")
#   APPSTORE_OUT        output folder (default: AppStoreScreenshots/, git-ignored)
#   APPSTORE_TEST_TIMEOUT  per-test time allowance in seconds (default: 120)
#
# Output: AppStoreScreenshots/<device>/<language>/01-home.png, 02-add-installment.png, 03-analytics.png,
# 04-cards.png. The script checks each file's pixel size against the size App Store Connect expects
# for that device; an unknown device name needs an entry in EXPECTED_SIZE below.
# The status bar is overridden (9:41, full battery and signal), appearance is light.
# Last line is "APPSTORE-SHOTS: PASS" or "APPSTORE-SHOTS: FAIL".

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEVICES="${APPSTORE_DEVICES:-iPhone 17 Pro Max}"
LANGUAGES="${APPSTORE_LANGUAGES:-en tr}"
OUT="${APPSTORE_OUT:-$ROOT/AppStoreScreenshots}"
WORK="$ROOT/.build/appstore-screenshots"
SHOTS=(01-home 02-add-installment 03-analytics 04-cards)

# Cihaz → App Store Connect'in istediği piksel boyutu (genişlik x yükseklik).
expected_size() {
  case "$1" in
    "iPhone 17 Pro Max"|"iPhone 16 Pro Max") echo "1320x2868" ;;
    "iPad Pro 13-inch (M5)") echo "2064x2752" ;;
    *) echo "" ;;
  esac
}

fail() {
  echo "  $1"
  [ -n "${2:-}" ] && tail -20 "$2" | sed 's/^/    /'
  echo "APPSTORE-SHOTS: FAIL"
  exit 1
}

for lang in $LANGUAGES; do
  case "$lang" in en|tr) ;; *) fail "unknown language '$lang' (en or tr)" ;; esac
done

rm -rf "$WORK"
mkdir -p "$WORK"

# Simülatörü adından bul (en yeni iOS sürümü).
find_udid() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
found = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if "iOS" not in runtime:
        continue
    version = tuple(int(p) for p in runtime.rsplit("iOS-", 1)[-1].split("-") if p.isdigit())
    found += [(version, d["udid"]) for d in devices if d["name"] == name]
print(max(found)[1] if found else "")
' "$1"
}

start=$(date +%s)
failures=0
total=0
BOOTED=()
cleanup() {
  for udid in "${BOOTED[@]:-}"; do
    [ -n "$udid" ] && { xcrun simctl status_bar "$udid" clear >/dev/null 2>&1; xcrun simctl shutdown "$udid" >/dev/null 2>&1; }
  done
}
trap cleanup EXIT

IFS=',' read -r -a DEVICE_LIST <<<"$DEVICES"
for device in "${DEVICE_LIST[@]}"; do
  device="$(echo "$device" | sed 's/^ *//; s/ *$//')"
  slug="$(echo "$device" | tr -c 'A-Za-z0-9\n' '-' | sed 's/-*$//')"
  size="$(expected_size "$device")"
  [ -n "$size" ] || fail "no expected App Store size for '$device' (add it to expected_size)"
  udid="$(find_udid "$device")"
  [ -n "$udid" ] || fail "no available simulator named '$device'"
  echo "▶ simulator '$device' ($udid), expected $size"

  echo "▶ build-for-testing"
  xcodebuild build-for-testing -project Vadem.xcodeproj -scheme Vadem \
    -destination "platform=iOS Simulator,id=$udid" -quiet \
    >"$WORK/build-$slug.log" 2>&1 || fail "build failed" "$WORK/build-$slug.log"

  # Yalnızca bu script'in açtığı simülatör sonda kapatılır; kullanıcının açık simülatörüne dokunulmaz.
  if ! xcrun simctl list devices booted | grep -q "$udid"; then
    xcrun simctl boot "$udid" >/dev/null 2>&1
    BOOTED+=("$udid")
  fi
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || fail "simulator did not boot"
  xcrun simctl ui "$udid" appearance light
  xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiBars 3 >/dev/null 2>&1

  for lang in $LANGUAGES; do
    run="$slug-$lang"
    dest="$OUT/$slug/$lang"
    rm -rf "$dest"
    mkdir -p "$dest"
    echo "▶ screenshots ($device, $lang)"
    TEST_RUNNER_APPSTORE_LANGUAGE="$lang" xcodebuild test-without-building \
      -project Vadem.xcodeproj -scheme Vadem -destination "platform=iOS Simulator,id=$udid" \
      -only-testing:VademUITests/AppStoreScreenshotTests \
      -parallel-testing-enabled NO \
      -test-timeouts-enabled YES -default-test-execution-time-allowance "${APPSTORE_TEST_TIMEOUT:-120}" \
      -resultBundlePath "$WORK/$run.xcresult" -quiet >"$WORK/test-$run.log" 2>&1
    test_status=$?
    [ -d "$WORK/$run.xcresult" ] || fail "no result bundle for $device/$lang" "$WORK/test-$run.log"
    xcrun xcresulttool export attachments --path "$WORK/$run.xcresult" \
      --output-path "$WORK/export-$run" >/dev/null 2>&1

    python3 - "$WORK/export-$run" "$dest" <<'PY'
import json, os, shutil, sys
export, dest = sys.argv[1:]
manifest = os.path.join(export, "manifest.json")
if os.path.exists(manifest):
    for test in json.load(open(manifest)):
        for a in test.get("attachments", []):
            if not a["exportedFileName"].lower().endswith(".png"):
                continue
            name = (a.get("suggestedHumanReadableName") or a["exportedFileName"]).split("_0_")[0]
            if not name.endswith(".png"):
                name += ".png"
            shutil.copy(os.path.join(export, a["exportedFileName"]), os.path.join(dest, name))
PY

    for shot in "${SHOTS[@]}"; do
      total=$((total + 1))
      file="$dest/$shot.png"
      if [ ! -f "$file" ]; then
        echo "  missing: ${file#$ROOT/}"; failures=$((failures + 1)); continue
      fi
      actual="$(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w "x" h}')"
      if [ "$actual" != "$size" ]; then
        echo "  wrong size: ${file#$ROOT/} is $actual, expected $size"; failures=$((failures + 1))
      fi
    done
    if [ $test_status -ne 0 ]; then
      echo "  tests failed for $device/$lang"
      tail -20 "$WORK/test-$run.log" | sed 's/^/    /'
      failures=$((failures + 1))
    fi
  done
done

echo "  done in $(( $(date +%s) - start ))s, $total screenshots expected"
echo "Output: ${OUT#$ROOT/}/"
if [ $failures -eq 0 ]; then
  echo "APPSTORE-SHOTS: PASS"
else
  echo "APPSTORE-SHOTS: FAIL"
  exit 1
fi
