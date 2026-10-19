#!/usr/bin/env bash
# Deterministic UI capture for the UI check agent: runs UICheckTests on a simulator,
# exports screenshots and accessibility-audit failures. The agent judges the screenshots.
#
# Usage: scripts/ui-check.sh
#   UI_CHECK_DEVICE   simulator name (default: "iPhone 17")
#
# Output: .build/ui-check/latest/
#   screenshots/<screen>__<variant>.png
#   a11y.txt        one accessibility issue per line (empty = none)
#   report.md       summary for the agent / PR
# Last line is "UI-CHECK: PASS" (no a11y issues, screenshots captured) or "UI-CHECK: FAIL".

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEVICE="${UI_CHECK_DEVICE:-iPhone 17}"
OUT="$ROOT/.build/ui-check/latest"
RESULT="$OUT/UICheck.xcresult"
rm -rf "$OUT"
mkdir -p "$OUT/screenshots"

echo "▶ ui-tests on '$DEVICE'"
start=$(date +%s)
xcodebuild test \
  -project Vadem.xcodeproj \
  -scheme Vadem \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -only-testing:VademUITests/UICheckTests \
  -resultBundlePath "$RESULT" \
  -quiet >"$OUT/xcodebuild.log" 2>&1
test_status=$?
echo "  done in $(( $(date +%s) - start ))s (xcodebuild exit $test_status)"

if [ ! -d "$RESULT" ]; then
  echo "  no result bundle; see ${OUT#$ROOT/}/xcodebuild.log"
  tail -20 "$OUT/xcodebuild.log" | sed 's/^/    /'
  echo "UI-CHECK: FAIL"
  exit 1
fi

# Ekran görüntülerini ve test hatalarını result bundle'dan çıkar.
EXPORT="$OUT/export"
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$EXPORT" >/dev/null 2>&1
xcrun xcresulttool get test-results summary --path "$RESULT" --compact >"$OUT/summary.json" 2>/dev/null

python3 - "$EXPORT" "$OUT" <<'PY'
import json, os, shutil, sys
export, out = sys.argv[1], sys.argv[2]

# Ekleri insan okunur adlarla kopyala (manifest: dosya adı → attachment adı).
shots = []
manifest = os.path.join(export, "manifest.json")
if os.path.exists(manifest):
    for test in json.load(open(manifest)):
        for a in test.get("attachments", []):
            # Sadece görüntüler; Xcode'un otomatik ekran kaydı (.mp4) gibi ekleri atla.
            if not a["exportedFileName"].lower().endswith((".png", ".jpg", ".jpeg")):
                continue
            name = a.get("suggestedHumanReadableName") or a["exportedFileName"]
            base = name.split("_0_")[0]  # xcresulttool ekleri "<ad>_0_<uuid>.png" diye adlandırır
            if not base.endswith(".png"):
                base += ".png"
            shutil.copy(os.path.join(export, a["exportedFileName"]), os.path.join(out, "screenshots", base))
            shots.append(base)

# Erişilebilirlik ve diğer test hataları.
a11y, other = [], []
summary = json.load(open(os.path.join(out, "summary.json"))) if os.path.getsize(os.path.join(out, "summary.json")) else {}
for f in summary.get("testFailures", []):
    text = f.get("failureText", "").removeprefix("failed - ")
    (a11y if text.startswith("[a11y]") else other).append(text)

open(os.path.join(out, "a11y.txt"), "w").write("\n".join(a11y) + ("\n" if a11y else ""))
with open(os.path.join(out, "report.md"), "w") as r:
    r.write("# UI check capture\n\n## Screenshots\n\n")
    r.writelines(f"- screenshots/{s}\n" for s in sorted(shots))
    r.write(f"\n## Accessibility audit ({len(a11y)} issues)\n\n")
    r.writelines(f"- {t}\n" for t in a11y)
    if other:
        r.write(f"\n## Other test failures ({len(other)})\n\n")
        r.writelines(f"- {t}\n" for t in other)

print(f"  screenshots: {len(shots)}  a11y issues: {len(a11y)}  other failures: {len(other)}")
for t in a11y + other:
    print(f"    {t}")
sys.exit(0 if shots and not a11y and not other else 1)
PY
verdict=$?

echo "Output: ${OUT#$ROOT/}/"
if [ $verdict -eq 0 ]; then
  echo "UI-CHECK: PASS"
  exit 0
else
  echo "UI-CHECK: FAIL"
  exit 1
fi
