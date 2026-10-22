import Foundation

/// The user's input for a new card, before it is valid.
///
/// ``errors`` lists every rule the draft breaks, one error per field at most;
/// ``makeCard(id:)`` returns a ``Card`` only when there are none. The rules are the
/// ``Card`` rules: trimmed name non-empty and at most ``Card/maxNameLength`` characters,
/// both days in ``Card/supportedDays``.
public struct CardDraft: Sendable, Hashable {
    /// A field of the draft, so a form can show each error under its own field.
    public enum Field: Sendable, Hashable, CaseIterable {
        case name
        case statementDay
        case dueDay
    }

    /// A broken rule; each error belongs to one ``Field``.
    public enum ValidationError: Error, Sendable, Hashable {
        /// The name is empty or whitespace only.
        case nameEmpty
        /// The trimmed name is longer than ``Card/maxNameLength``.
        case nameTooLong
        /// The statement day is missing or outside ``Card/supportedDays``.
        case statementDayOutOfRange
        /// The due day is missing or outside ``Card/supportedDays``.
        case dueDayOutOfRange

        /// The field this error belongs to.
        public var field: Field {
            switch self {
            case .nameEmpty, .nameTooLong: return .name
            case .statementDayOutOfRange: return .statementDay
            case .dueDayOutOfRange: return .dueDay
            }
        }
    }

    /// The name as typed; trimmed when the card is made.
    public var name: String
    /// The statement day, or `nil` when no valid number was entered.
    public var statementDay: Int?
    /// The due day, or `nil` when no valid number was entered.
    public var dueDay: Int?

    /// Creates a draft from raw form values.
    public init(name: String, statementDay: Int?, dueDay: Int?) {
        self.name = name
        self.statementDay = statementDay
        self.dueDay = dueDay
    }

    /// Every broken rule, in ``Field`` order; empty when the draft is valid.
    public var errors: [ValidationError] {
        var result: [ValidationError] = []
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            result.append(.nameEmpty)
        } else if trimmed.count > Card.maxNameLength {
            result.append(.nameTooLong)
        }
        // Girilmemiş gün de aralık dışı sayılır; formda aynı mesaj gösterilir.
        if !Self.isSupported(statementDay) {
            result.append(.statementDayOutOfRange)
        }
        if !Self.isSupported(dueDay) {
            result.append(.dueDayOutOfRange)
        }
        return result
    }

    /// `true` when ``errors`` is empty.
    public var isValid: Bool {
        errors.isEmpty
    }

    /// The error of `field`, or `nil` when the field is valid.
    public func error(for field: Field) -> ValidationError? {
        errors.first { $0.field == field }
    }

    /// The card the draft describes (name trimmed), or `nil` while ``errors`` is not empty.
    public func makeCard(id: UUID = UUID()) -> Card? {
        guard isValid, let statementDay, let dueDay else { return nil }
        return Card(id: id, name: name, statementDay: statementDay, dueDay: dueDay)
    }

    private static func isSupported(_ day: Int?) -> Bool {
        guard let day else { return false }
        return Card.supportedDays.contains(day)
    }
}
