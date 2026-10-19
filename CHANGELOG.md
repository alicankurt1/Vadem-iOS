# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `Money` value type in `VademCore`: stores amounts as `Decimal`, rounds to two fraction digits (half away from zero), supports exact addition and subtraction, and encodes to JSON as a string to avoid `Double` precision loss (#4, PR #5)
- `YearMonth` value type in `VademCore`: month arithmetic with year rollover, signed month distance, days in month including leap years, and JSON as `"YYYY-MM"`; supported years are 1...9999 (#7, PR #8)
- `InstallmentPlan` in `VademCore`: splits a total (`Money`) into 1–36 monthly payments starting at a `YearMonth`, with `payments`, `lastMonth` and `amount(in:)`. Each installment is the total divided by the count, rounded down to kuruş, and the leftover kuruş go to the first installment (`1000.00 / 3 → 333.34, 333.33, 333.33`), so payments always sum to the total exactly (ADR-0001). Plans with a non-positive total, a count outside 1–36, or a last installment after 9999-12 are rejected, including when decoding JSON (#15, PR #16)

### Fixed

- The version label on the root screen now reads "Version 0.1.0" in a smaller primary-colored style, so it passes the accessibility audit (contrast, readable label) in light, dark and the largest Dynamic Type size; UI checks assert its text, position and size (#10, PR #12)

### Pipeline

- `scripts/ui-check.sh` now renders dark mode (set via `simctl` per appearance), reports every audit failure per test instead of only the first, and the dark-mode guard checks pixel brightness instead of comparing PNG bytes (PR #11)
