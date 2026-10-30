import Foundation

/// One message in the in-app inbox: the text of a ``MonthlyInsight``, kept so the user can read it later.
///
/// The ``id`` is the insight's id (``MonthlyInsight/id``, e.g. `insight-2026-11-totalChange`), so the
/// same insight computed again (e.g. on the next launch) is the same entry and is never added twice.
/// The text is stored as it was produced (already localized), not rebuilt from the payments.
public struct InboxEntry: Sendable, Hashable, Identifiable {
    /// The insight's id: `insight-YYYY-MM-<kind>`.
    public let id: String
    /// The month the insight is about.
    public let month: YearMonth
    /// What the insight is about.
    public let kind: MonthlyInsight.Kind
    /// The entry's title, e.g. `"Installment ended"`.
    public let title: String
    /// The entry's text, e.g. `"Laptop: installment ended; you pay ₺500,00 less this month"`.
    public let body: String
    /// When the entry was produced.
    public let createdAt: Date
    /// `true` once the user has opened the inbox after the entry was added.
    public var isRead: Bool

    /// Creates an entry; a new entry is unread unless `isRead` is given.
    public init(
        id: String, month: YearMonth, kind: MonthlyInsight.Kind, title: String, body: String,
        createdAt: Date, isRead: Bool = false
    ) {
        self.id = id
        self.month = month
        self.kind = kind
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.isRead = isRead
    }

    /// Creates an unread entry for `insight` with the given text; ``id``, ``month`` and ``kind`` come from the insight.
    public init(insight: MonthlyInsight, title: String, body: String, createdAt: Date) {
        self.init(
            id: insight.id, month: insight.month, kind: insight.kind, title: title, body: body, createdAt: createdAt
        )
    }

    /// The inbox order, newest first: ``createdAt`` descending, then ``month`` descending, then
    /// ``kind`` by importance (``MonthlyInsight/Kind/rank``), then ``id`` ascending.
    public static func isOrdered(_ lhs: InboxEntry, before rhs: InboxEntry) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        if lhs.month != rhs.month { return lhs.month > rhs.month }
        if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
        return lhs.id < rhs.id
    }
}

/// Builds the inbox entries of a month from ``MonthlyInsightCalculator`` (pure; no side effects).
///
/// Every insight about the month becomes one entry (not only the top one the monthly summary
/// notification shows). The words come from the caller (`text`), so ``VademCore`` stays free of UI text.
public enum InboxPlanner {
    /// The title and body of an entry.
    public struct Text: Sendable, Hashable {
        public let title: String
        public let body: String

        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }

    /// One unread entry per insight about `month`, most important first, all created at `createdAt`.
    public static func entries(
        for month: YearMonth,
        createdAt: Date,
        cards: [Card],
        installments: [InstallmentItem],
        subscriptions: [SubscriptionItem],
        oneTimePayments: [OneTimePaymentItem] = [],
        text: (MonthlyInsight) -> Text
    ) -> [InboxEntry] {
        // Bildirimle aynı hesap: aynı içgörü aynı id'yi verir, depo ikinci kez eklemez.
        MonthlyInsightCalculator.insights(
            for: month, cards: cards, installments: installments,
            subscriptions: subscriptions, oneTimePayments: oneTimePayments
        ).map { insight in
            let words = text(insight)
            return InboxEntry(insight: insight, title: words.title, body: words.body, createdAt: createdAt)
        }
    }
}
