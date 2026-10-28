import Foundation
import VademCore

/// Remembers the card of the last item saved through an add flow, so the next flow's
/// card picker can preselect it (``CardPicker/initialSelection(cards:lastUsedCardID:)``).
///
/// Backed by `UserDefaults` (device-local) under ``key``; tests pass `UserDefaults(suiteName:)`.
/// "No card" is remembered too: saving without a card clears the key.
@MainActor
public final class LastUsedCardStore {
    /// The `UserDefaults` key of the remembered card id (a UUID string).
    public nonisolated static let key = "vadem.addFlow.lastUsedCardID"

    private let defaults: UserDefaults

    /// Uses `defaults` (default: `.standard`).
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The remembered card id, or `nil` when none is saved (or the saved value is not a UUID).
    public var cardID: Card.ID? {
        get { defaults.string(forKey: Self.key).flatMap(UUID.init(uuidString:)) }
        set {
            if let newValue {
                defaults.set(newValue.uuidString, forKey: Self.key)
            } else {
                defaults.removeObject(forKey: Self.key)
            }
        }
    }
}
