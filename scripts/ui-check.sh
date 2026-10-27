#!/usr/bin/env bash
# Deterministic UI capture: runs UICheckTests on a simulator, once per appearance, exports
# screenshots, every test failure and non-failing notes. The orchestrator runs it in the background
# and reads only the summary lines; screenshots are looked at only when a finding needs it.
#
# Usage: scripts/ui-check.sh
#   UI_CHECK_DEVICE   simulator name (default: "iPhone 17")
#   UI_CHECK_ONLY     tests to run, comma separated; default: all. A name is matched case-insensitively
#                     against the test methods of UICheckTests, as given ("testAddCardForm"), without the
#                     "test" prefix ("addCardForm") or as a screen ("gallery" = testGalleryScreen).
#                     An unknown name fails the run and lists the available tests.
#   UI_CHECK_APPEARANCES  appearances to run, space separated (default: "light dark"); "light" alone
#                     halves a targeted run. The AX5 text variant runs in the light pass.
#   UI_CHECK_DARK_AUDIT  1 = also run the accessibility audit in the dark pass (default: skipped, saves ~4 min;
#                     screenshots and the appearance check still run)
#   UI_CHECK_TEST_TIMEOUT  per-test time allowance in seconds (default: 180)
#
# Output: .build/ui-check/latest/
#   screenshots/<screen>__<variant>.png
#   screenshots/small/…  600 px wide copies (cheap to look at)
#   a11y.txt        one accessibility issue per line (empty = none)
#   notes.txt       non-failing notes: identical consecutive parts, issues on elements under a bar,
#                   contrast findings ([a11y-contrast], or [a11y-flaky] when a retry did not
#                   reproduce them; token ratios are covered by TokenContrastTests)
#   report.md       summary for the PR (all failures, not only the first per test)
# Last line is "UI-CHECK: PASS" (screenshots captured, no failures) or "UI-CHECK: FAIL".

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEVICE="${UI_CHECK_DEVICE:-iPhone 17}"
OUT="$ROOT/.build/ui-check/latest"
APPEARANCES="${UI_CHECK_APPEARANCES:-light dark}"
for appearance in $APPEARANCES; do
  case "$appearance" in light|dark) ;; *) echo "  unknown appearance '$appearance' (light or dark)"; echo "UI-CHECK: FAIL"; exit 1 ;; esac
done
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

# Seçici koşu: "gallery,addCardForm" → -only-testing:…/testGalleryScreen -only-testing:…/testAddCardForm
# Adlar UICheckTests'teki gerçek test metotlarına karşı doğrulanır; bilinmeyen ad koşuyu durdurur.
ONLY_TESTING=()
if [ -n "${UI_CHECK_ONLY:-}" ]; then
  METHODS=$(grep -oE 'func test[A-Za-z0-9_]*' VademUITests/UICheckTests.swift | sed 's/^func //')
  for name in ${UI_CHECK_ONLY//,/ }; do
    wanted=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    match=""
    for method in $METHODS; do
      lower=$(echo "$method" | tr '[:upper:]' '[:lower:]')
      if [ "$lower" = "$wanted" ] || [ "$lower" = "test$wanted" ] || [ "$lower" = "test${wanted}screen" ]; then
        match="$method"
        break
      fi
    done
    [ -n "$match" ] || fail "unknown test '$name' in UI_CHECK_ONLY; available: $(echo $METHODS | sed 's/test//g; s/ /, /g')"
    ONLY_TESTING+=("-only-testing:VademUITests/UICheckTests/$match")
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
# Her varyant (light-default, dark-default, light-AX5) kendi simülatör kopyasında ve aynı anda koşar (#148):
# tek simülatörde sırayla ~39 dk sürüyordu. Paralel test (-parallel-testing-enabled) kapalı kalır, çünkü
# onun kopyaları görünüm ayarını taşımaz; kopyaları burada kendimiz kurarız, böylece görünüm her birinde ayrı ayarlanır.
# Test başına 180 sn sınır: XCTest arada uygulamayı bulurken dakikalarca takılıyordu (#37).
JOBS=()
for appearance in $APPEARANCES; do
  case "$appearance" in
    light) JOBS+=("light-default:light" "light-AX5:light") ;;
    dark) JOBS+=("dark-default:dark") ;;
  esac
done

# Kopyalar yalnızca kapalı bir simülatörden alınır.
xcrun simctl shutdown "$UDID" >/dev/null 2>&1
CLONES=()
cleanup() {
  for clone in "${CLONES[@]:-}"; do
    [ -n "$clone" ] && { xcrun simctl shutdown "$clone" >/dev/null 2>&1; xcrun simctl delete "$clone" >/dev/null 2>&1; }
  done
}
trap cleanup EXIT

run_job() {
  local variant="$1" appearance="$2" clone="$3"
  xcrun simctl boot "$clone" >/dev/null 2>&1
  xcrun simctl bootstatus "$clone" -b >/dev/null 2>&1 || { echo "simulator did not boot" >"$OUT/test-$variant.log"; return; }
  xcrun simctl ui "$clone" appearance "$appearance"
  TEST_RUNNER_UI_CHECK_APPEARANCE="$appearance" TEST_RUNNER_UI_CHECK_VARIANT="$variant" \
    TEST_RUNNER_UI_CHECK_DARK_AUDIT="${UI_CHECK_DARK_AUDIT:-}" xcodebuild test-without-building \
    -project Vadem.xcodeproj -scheme Vadem -destination "platform=iOS Simulator,id=$clone" \
    "${ONLY_TESTING[@]}" \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES -default-test-execution-time-allowance "${UI_CHECK_TEST_TIMEOUT:-180}" \
    -resultBundlePath "$OUT/UICheck-$variant.xcresult" \
    -quiet >"$OUT/test-$variant.log" 2>&1
  [ -d "$OUT/UICheck-$variant.xcresult" ] || return
  xcrun xcresulttool export attachments --path "$OUT/UICheck-$variant.xcresult" \
    --output-path "$OUT/export-$variant" >/dev/null 2>&1
  xcrun xcresulttool get test-results tests --path "$OUT/UICheck-$variant.xcresult" --compact \
    >"$OUT/tests-$variant.json" 2>/dev/null
}

PIDS=()
for job in "${JOBS[@]}"; do
  variant="${job%%:*}"; appearance="${job##*:}"
  clone=$(xcrun simctl clone "$UDID" "ui-check-$variant-$$") || fail "could not clone simulator for $variant"
  CLONES+=("$clone")
  echo "▶ ui-tests ($variant${UI_CHECK_ONLY:+, only: $UI_CHECK_ONLY}) on $clone"
  run_job "$variant" "$appearance" "$clone" &
  PIDS+=($!)
done
wait "${PIDS[@]}"
for job in "${JOBS[@]}"; do
  variant="${job%%:*}"
  [ -d "$OUT/UICheck-$variant.xcresult" ] || fail "no result bundle for $variant" "$OUT/test-$variant.log"
done
echo "  done in $(( $(date +%s) - start ))s"

python3 - "$OUT" "${JOBS[@]%%:*}" <<'PY'
import json, os, re, shutil, sys
out, appearances = sys.argv[1], sys.argv[2:]

shots, failures, notes, times = [], [], [], []

def walk(node):
    # Her "Failure Message" düğümü ayrı bir hata; summary ise test başına sadece ilkini verir.
    if node.get("nodeType") == "Failure Message":
        text = re.sub(r"^\S+:\d+: ", "", node.get("name", ""))  # "Dosya.swift:NN: " önekini at
        failures.append(text.removeprefix("failed - "))
    for child in node.get("children", []):
        walk(child)

for appearance in appearances:  # varyant adları (light-default, ...)
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
                    times += [l for l in lines if l.startswith("[ui-time]")]
                    notes += [l for l in lines if l.startswith(("[ui-note]", "[a11y-hidden]", "[a11y-flaky]", "[a11y-contrast]"))]
                    continue
                if not a["exportedFileName"].lower().endswith((".png", ".jpg", ".jpeg")):
                    continue
                name = a.get("suggestedHumanReadableName") or a["exportedFileName"]
                base = name.split("_0_")[0]
                if not base.endswith(".png"):
                    base += ".png"
                # Süre aşımına uğrayan testlerin eki dışa aktarılmamış olabilir; eksik dosya özeti çökertmesin.
                try:
                    shutil.copy(os.path.join(export, a["exportedFileName"]), os.path.join(out, "screenshots", base))
                except FileNotFoundError:
                    continue
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

# Süre özeti (#148): zaman nereye gidiyor? Toplam, adım türüne göre ve en yavaş 10 adım.
open(os.path.join(out, "timing.txt"), "w").write("\n".join(times) + ("\n" if times else ""))
if times:
    rows = []
    for l in times:
        _, key, step, secs = l.split(" ")
        rows.append((key, step.split(":")[0], step, float(secs)))
    kinds, variants_ = {}, {}
    for key, kind, _, secs in rows:
        kinds[kind] = kinds.get(kind, 0) + secs
        variants_[key.split("__")[1]] = variants_.get(key.split("__")[1], 0) + secs
    print("  time by step: " + ", ".join(f"{k} {v:.0f}s" for k, v in sorted(kinds.items(), key=lambda i: -i[1])))
    print("  time by variant: " + ", ".join(f"{k} {v:.0f}s" for k, v in sorted(variants_.items())))
    print("  slowest steps: " + "; ".join(f"{k} {s} {t:.0f}s" for k, _, s, t in sorted(rows, key=lambda r: -r[3])[:10]))

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
