# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `Money` value type in `VademCore`: stores amounts as `Decimal`, rounds to two fraction digits (half away from zero), supports exact addition and subtraction, and encodes to JSON as a string to avoid `Double` precision loss (#4, PR #5)
- `YearMonth` value type in `VademCore`: month arithmetic with year rollover, signed month distance, days in month including leap years, and JSON as `"YYYY-MM"`; supported years are 1...9999 (#7, PR #8)
- `InstallmentPlan` in `VademCore`: splits a total (`Money`) into 1–36 monthly payments starting at a `YearMonth`, with `payments`, `lastMonth` and `amount(in:)`. Each installment is the total divided by the count, rounded down to kuruş, and the leftover kuruş go to the first installment (`1000.00 / 3 → 333.34, 333.33, 333.33`), so payments always sum to the total exactly (ADR-0001). Plans with a non-positive total, a count outside 1–36, or a last installment after 9999-12 are rejected, including when decoding JSON (#15, PR #16)
- `Subscription` in `VademCore`: a recurring charge with an amount, a monthly or yearly period, a renewal day (1–31), a first month and an optional last month, with `charges(in:)`, `amount(in:)` and `chargeDay(in:)`. Yearly subscriptions charge only in the month of their first charge. In shorter months the renewal day moves to the month's last day (day 31 → Feb 28, Feb 29 in leap years, Apr 30). Subscriptions with a non-positive amount, a renewal day outside 1–31, or a last month before the first are rejected, including when decoding JSON (#19, PR #20)
- `Card` in `VademCore`: a credit card with a display name (trimmed, 1–40 characters), a statement day and a due day (1–31), and a stable `id`; no card numbers are stored. `statementDay(in:)` moves the statement day to the month's last day in shorter months, and `dueDate(forStatementIn:)` returns the first due day strictly after the statement date, in the same month or the next (statement 25, due 5 in March → April 5; the same day counts as the next month). Cards with an empty or too-long name or a day outside 1–31 are rejected, including when decoding JSON (#23, PR #24)
- Tracked items and a storage contract in `VademCore`: `InstallmentItem` (always on a card) and `SubscriptionItem` (card optional) give a plan or subscription an `id` and a title (trimmed, 1–60 characters, also checked when decoding JSON). `PaymentRepository` defines how cards, installments and subscriptions are saved and loaded: save replaces by `id`, a card still used by an item cannot be deleted (`cardInUse`), an item cannot point to an unsaved card (`unknownCard`), and lists have a fixed order (text compared with `caseInsensitiveCompare`, not localized, then `id`). `InMemoryPaymentRepository` is the reference implementation for previews and tests; storage on disk comes next (#26, PR #27)
- Cards, installments and subscriptions are now stored on device with SwiftData: `SwiftDataPaymentRepository` in `VademPersistence` follows the same `PaymentRepository` contract as the in-memory reference (all 29 shared scenarios pass). The store lives in the App Group container with no iCloud sync, data survives reopening, amounts are stored as exact decimal text (never `Double`), every write is saved immediately, and corrupt stored records fail with an error instead of crashing. The schema is versioned from the start (`VademSchemaV1`, `1.0.0`) with a migration plan. Not yet used by any screen (#30, PR #31)

### Fixed

- The version label on the root screen now reads "Version 0.1.0" in a smaller primary-colored style, so it passes the accessibility audit (contrast, readable label) in light, dark and the largest Dynamic Type size; UI checks assert its text, position and size (#10, PR #12)

### Pipeline

- `scripts/ui-check.sh` now renders dark mode (set via `simctl` per appearance), reports every audit failure per test instead of only the first, and the dark-mode guard checks pixel brightness instead of comparing PNG bytes (PR #11)
