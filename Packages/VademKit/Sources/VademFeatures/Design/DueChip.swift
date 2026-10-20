import SwiftUI

/// A small capsule label for how soon a payment is due.
@MainActor
public struct DueChip: View {
    /// How soon the payment is due; picks the matching token pair.
    public enum Kind: CaseIterable, Sendable {
        case today
        case soon
        case later

        /// Text color.
        public var foreground: Color {
            switch self {
            case .today: .vademDueToday
            case .soon: .vademDueSoon
            case .later: .vademDueLater
            }
        }

        /// Capsule fill.
        public var background: Color {
            switch self {
            case .today: .vademDueTodayBackground
            case .soon: .vademDueSoonBackground
            case .later: .vademDueLaterBackground
            }
        }
    }

    private let title: String
    private let kind: Kind

    public init(_ title: String, kind: Kind) {
        self.title = title
        self.kind = kind
    }

    public var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(kind.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(kind.background, in: .capsule)
    }
}

#Preview {
    HStack {
        DueChip("Today", kind: .today)
        DueChip("In 3 days", kind: .soon)
        DueChip("Later", kind: .later)
    }
}
