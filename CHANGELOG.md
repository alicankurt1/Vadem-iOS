# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `Money` value type in `VademCore`: stores amounts as `Decimal`, rounds to two fraction digits (half away from zero), supports exact addition and subtraction, and encodes to JSON as a string to avoid `Double` precision loss (#4, PR #5)
- `YearMonth` value type in `VademCore`: month arithmetic with year rollover, signed month distance, days in month including leap years, and JSON as `"YYYY-MM"`; supported years are 1...9999 (#7, PR #8)

### Fixed

- The version label on the root screen now reads "Version 0.1.0" in a smaller primary-colored style, so it passes the accessibility audit (contrast, readable label) in light, dark and the largest Dynamic Type size; UI checks assert its text, position and size (#10, PR #12)

### Pipeline

- `scripts/ui-check.sh` now renders dark mode (set via `simctl` per appearance), reports every audit failure per test instead of only the first, and the dark-mode guard checks pixel brightness instead of comparing PNG bytes (PR #11)
