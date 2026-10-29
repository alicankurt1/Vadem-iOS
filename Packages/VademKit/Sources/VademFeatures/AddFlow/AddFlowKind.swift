import Foundation

/// What the user adds from the Add sheet on Home.
public enum AddFlowKind: String, CaseIterable, Sendable, Identifiable {
    case installment
    case subscription
    case payment

    public var id: String { rawValue }

    /// The sheet button's title ("Installment").
    public var title: String {
        switch self {
        case .installment: String(localized: "Installment", bundle: .module)
        case .subscription: String(localized: "Subscription", bundle: .module)
        case .payment: String(localized: "Payment", bundle: .module)
        }
    }

    /// The line under the title, also the button's VoiceOver hint.
    public var subtitle: String {
        switch self {
        case .installment: String(localized: "Split into monthly installments", bundle: .module)
        case .subscription: String(localized: "Renews every month or year", bundle: .module)
        case .payment: String(localized: "A one-off payment", bundle: .module)
        }
    }

    /// The SF Symbol shown on the button.
    public var systemImage: String {
        switch self {
        case .installment: "creditcard"
        case .subscription: "arrow.triangle.2.circlepath"
        case .payment: "banknote"
        }
    }

    /// The button's accessibility identifier: `add.sheet.<kind>`.
    public var accessibilityIdentifier: String { "add.sheet.\(rawValue)" }

    /// `true` when picking this kind closes the sheet and opens an existing form;
    /// `false` when its flow runs inside the sheet (Installment: ``InstallmentFlowView``; Subscription's quick steps;
    /// Payment: ``OneTimeFlowView``).
    public var opensExistingForm: Bool {
        switch self {
        case .installment, .subscription, .payment: false
        }
    }
}
