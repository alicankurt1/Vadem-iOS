#!/usr/bin/env bash
# Deterministic UI capture: runs UICheckTests on a simulator, once per appearance, exports
# screenshots, every test failure and non-failing notes. The orchestrator runs it in the background
# and reads only the summary lines; screenshots are looked at only when a finding needs it.
#
# Usage: scripts/ui-check.sh
#   UI_CHECK_DEVICE   simulator name (default: "iPhone 17")
#   UI_CHECK_ONLY     screens to capture, comma separated (e.g. "gallery"); default: all.
#                     Screen "foo" is the test method testFooScreen in UICheckTests.
#
# Output: .build/ui-check/latest/
#   screenshots/<screen>__<variant>.png
#   screenshots/small/…  600 px wide copies (cheap to look at)
#   a11y.txt        one accessibility issue per line (empty = none)
#   notes.txt       non-failing notes: identical consecutive parts, issues on elements under a bar
#   report.md       summary for the PR (all failures, not only the first per test)
# Last line is "UI-CHECK: PASS" (screenshots captured, no failures) or "UI-CHECK: FAIL".

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEVICE="${UI_CHECK_DEVICE:-iPhone 17}"
OUT="$ROOT/.build/ui-check/latest"
APPEARANCES="light dark"
rm -rf "$OUT"
mkdir -p "$OUT/screenshots"

fail() {
  echo "  $1"
  [ -n "${2:-}" ] && tail -20 "$2" | sed 's/^/    /'
  echo "UI-CHECK: FAIL"
  exit 1
}

# Simülatörü adından bul (en yeni iOS sürümü) ve aç.
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
found = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if "iOS" not in runtime:
        continue
    version = tuple(int(p) for p in runtime.rsplit("iOS-", 1)[-1].split("-") if p.isdigit())
    found += [(version, d["udid"]) for d in devices if d["name"] == name]
print(max(found)[1] if found else "")
' "$DEVICE")
[ -n "$UDID" ] || fail "no available simulator named '$DEVICE'"

echo "▶ simulator '$DEVICE' ($UDID)"
xcrun simctl boot "$UDID" >/dev/null 2>&1
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || fail "simulator did not boot"

# Seçici koşu: "gallery,root" → -only-testing:…/testGalleryScreen -only-testing:…/testRootScreen
ONLY_TESTING=()
if [ -n "${UI_CHECK_ONLY:-}" ]; then
  for screen in ${UI_CHECK_ONLY//,/ }; do
    ONLY_TESTING+=("-only-testing:VademUITests/UICheckTests/test$(echo "${screen:0:1}" | tr '[:lower:]' '[:upper:]')${screen:1}Screen")
  done
else
  ONLY_TESTING=("-only-testing:VademUITests/UICheckTests")
fi

DEST="platform=iOS Simulator,id=$UDID"
start=$(date +%s)

echo "▶ build-for-testing"
xcodebuild build-for-testing -project Vadem.xcodeproj -scheme Vadem -destination "$DEST" -quiet \
  >"$OUT/build.log" 2>&1 || fail "build failed" "$OUT/build.log"

# Görünüm test içinden değil simctl ile ayarlanır; test hangi görünümde olduğunu
# TEST_RUNNER_UI_CHECK_APPEARANCE → UI_CHECK_APPEARANCE ortam değişkeninden okur.
# Paralel test kapalı: paralel koşu simülatörün bir kopyasını kullanır, ayar oraya geçmez.
# Test başına 180 sn sınır: XCTest arada uygulamayı bulurken dakikalarca takılıyordu (#37);
# sağlıklı bir galeri geçişi ~75 sn sürer.
for appearance in $APPEARANCES; do
  echo "▶ ui-tests ($appearance${UI_CHECK_ONLY:+, only: $UI_CHECK_ONLY})"
  xcrun simctl ui "$UDID" appearance "$appearance"
  TEST_RUNNER_UI_CHECK_APPEARANCE="$appearance" xcodebuild test-without-building \
    -project Vadem.xcodeproj -scheme Vadem -destination "$DEST" \
    "${ONLY_TESTING[@]}" \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
    -resultBundlePath "$OUT/UICheck-$appearance.xcresult" \
    -quiet >"$OUT/test-$appearance.log" 2>&1
  [ -d "$OUT/UICheck-$appearance.xcresult" ] || fail "no result bundle for $appearance" "$OUT/test-$appearance.log"
  xcrun xcresulttool export attachments --path "$OUT/UICheck-$appearance.xcresult" \
    --output-path "$OUT/export-$appearance" >/dev/null 2>&1
  xcrun xcresulttool get test-results tests --path "$OUT/UICheck-$appearance.xcresult" --compact \
    >"$OUT/tests-$appearance.json" 2>/dev/null
done
xcrun simctl ui "$UDID" appearance light
echo "  done in $(( $(date +%s) - start ))s"

python3 - "$OUT" $APPEARANCES <<'PY'
import json, os, re, shutil, sys
out, appearances = sys.argv[1], sys.argv[2:]

shots, failures, notes = [], [], []

def walk(node):
    # Her "Failure Message" düğümü ayrı bir hata; summary ise test başına sadece ilkini verir.
    if node.get("nodeType") == "Failure Message":
        text = re.sub(r"^\S+:\d+: ", "", node.get("name", ""))  # "Dosya.swift:NN: " önekini at
        failures.append(text.removeprefix("failed - "))
    for child in node.get("children", []):
        walk(child)

for appearance in appearances:
    # Ekleri insan okunur adlarla kopyala; sadece görüntüler (Xcode'un otomatik .mp4 kaydı hariç).
    export = os.path.join(out, f"export-{appearance}")
    manifest = os.path.join(export, "manifest.json")
    if os.path.exists(manifest):
        for test in json.load(open(manifest)):
            for a in test.get("attachments", []):
                # Metin ekleri testin hata saymadığı notlar (aynı parçalar, çubuk altındaki öğeler).
                if a["exportedFileName"].lower().endswith(".txt"):
                    # Xcode hata metinlerini de .txt ekler; sadece bizim notlar alınır.
                    lines = open(os.path.join(export, a["exportedFileName"])).read().splitlines()
                    notes += [l for l in lines if l.startswith(("[ui-note]", "[a11y-hidden]"))]
                    continue
                if not a["exportedFileName"].lower().endswith((".png", ".jpg", ".jpeg")):
                    continue
                name = a.get("suggestedHumanReadableName") or a["exportedFileName"]
                base = name.split("_0_")[0]
                if not base.endswith(".png"):
                    base += ".png"
                shutil.copy(os.path.join(export, a["exportedFileName"]), os.path.join(out, "screenshots", base))
                shots.append(base)

    tests = os.path.join(out, f"tests-{appearance}.json")
    if os.path.exists(tests) and os.path.getsize(tests):
        for node in json.load(open(tests)).get("testNodes", []):
            walk(node)

a11y = [f for f in failures if f.startswith("[a11y]")]
other = [f for f in failures if not f.startswith("[a11y]")]

open(os.path.join(out, "a11y.txt"), "w").write("\n".join(a11y) + ("\n" if a11y else ""))
open(os.path.join(out, "notes.txt"), "w").write("\n".join(notes) + ("\n" if notes else ""))
with open(os.path.join(out, "report.md"), "w") as r:
    r.write("# UI check capture\n\n## Screenshots\n\n")
    r.writelines(f"- screenshots/{s}\n" for s in sorted(shots))
    r.write(f"\n## Accessibility audit ({len(a11y)} issues)\n\n")
    r.writelines(f"- {t}\n" for t in a11y)
    r.write(f"\n## Other test failures ({len(other)})\n\n")
    r.writelines(f"- {t}\n" for t in other)
    r.write(f"\n## Notes ({len(notes)}, not failures)\n\n")
    r.writelines(f"- {t}\n" for t in notes)

print(f"  screenshots: {len(shots)}  a11y issues: {len(a11y)}  other failures: {len(other)}  notes: {len(notes)}")
for t in a11y + other + notes:
    print(f"    {t}")
sys.exit(0 if shots and not failures else 1)
PY
verdict=$?

# Bakmak için 600 px genişliğinde küçük kopyalar (tam boyutun yaklaşık dörtte biri piksel).
mkdir -p "$OUT/screenshots/small"
for f in "$OUT"/screenshots/*.png; do
  [ -e "$f" ] && sips --resampleWidth 600 "$f" --out "$OUT/screenshots/small/$(basename "$f")" >/dev/null 2>&1
done

echo "Output: ${OUT#$ROOT/}/"
if [ $verdict -eq 0 ]; then
  echo "UI-CHECK: PASS"
  exit 0
else
  echo "UI-CHECK: FAIL"
  exit 1
fi
