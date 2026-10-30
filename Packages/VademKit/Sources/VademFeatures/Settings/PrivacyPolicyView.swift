import SwiftUI

/// The privacy policy, pushed from Settings: what the app stores, what it never does, the assistant,
/// notifications / widget / Siri and deleting data. The text mirrors `docs/privacy.md` (EN and TR).
///
/// Plain wrapping text on `vademBackground`, no animations, so it is idle under `-ui-static-motion`.
/// Identifiers: `privacy.policy` (the screen), `privacy.policy.intro` and
/// `privacy.policy.section.<index>` (section headings, from 0) as scroll markers for the UI check.
@MainActor
public struct PrivacyPolicyView: View {
    /// The launch argument that opens the app on the Settings tab with this screen pushed (debug builds).
    public nonisolated static let launchArgument = "-ui-privacy-policy"

    // Bir bölüm: başlık ve sırayla paragraf / madde blokları.
    private struct Section {
        enum Block {
            case paragraph(AttributedString)
            case bullet(AttributedString)
        }

        let title: String
        let blocks: [Block]
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    /// Creates the screen.
    public init() {}

    public var body: some View {
        FormScroll {
            Text(Self.intro)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("privacy.policy.intro")
            ForEach(Array(Self.sections.enumerated()), id: \.offset) { index, section in
                sectionView(section, index: index)
            }
        }
        .foregroundStyle(Color.vademTextPrimary)
        .multilineTextAlignment(.leading)
        .navigationTitle(Text("Privacy Policy", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // Ayarlar gibi: çubuk ekranın renk şemasına ve arka planına sabitlenir.
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .toolbarBackground(Color(Color.vademBackground.resolve(in: environment)), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .accessibilityIdentifier("privacy.policy")
    }

    // Bölüm: başlık (UI testi için kaydırma işareti) ve altında düz, sarılan metin.
    private func sectionView(_ section: Section, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("privacy.policy.section.\(index)")
            ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: Section.Block) -> some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bullet(let text):
            // Madde işareti yalnızca görsel; VoiceOver metni okur.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "•")
                    .font(.body)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Metin (docs/privacy.md ile aynı tutulmalı)

    private static var intro: AttributedString {
        AttributedString(localized: "Vadem tracks your credit card installments and subscriptions and shows how much you pay each month. It is built so that your data never leaves your device.", bundle: .module)
    }

    private static var sections: [Section] {
        [
            Section(title: String(localized: "What the app stores", bundle: .module), blocks: [
                .bullet(AttributedString(localized: "The cards, installments and subscriptions you enter yourself.", bundle: .module)),
                .bullet(AttributedString(localized: "Your reminder settings (whether payment reminders are on and when they fire).", bundle: .module)),
                .paragraph(AttributedString(localized: "This data is stored only on your device. Your cards and payments live in a storage area that the app shares only with its own Home Screen widget and Siri / Shortcuts actions; your reminder settings live in the app's own settings. iCloud sync (CloudKit) is off: nothing is copied to iCloud by the app.", bundle: .module)),
            ]),
            Section(title: String(localized: "What the app does not do", bundle: .module), blocks: [
                .bullet(AttributedString(localized: "**No account.** There is no sign-up and no login.", bundle: .module)),
                .bullet(AttributedString(localized: "**No bank connection.** The app never connects to your bank or card issuer; every value is entered by you.", bundle: .module)),
                .bullet(AttributedString(localized: "**No analytics, no tracking, no ads.** The app contains no analytics, crash reporting, advertising or tracking code and does not use any third-party services.", bundle: .module)),
                .bullet(AttributedString(localized: "**No network requests.** The app does not send your data to any server, including ours.", bundle: .module)),
            ]),
            Section(title: String(localized: "The assistant", bundle: .module), blocks: [
                .paragraph(AttributedString(localized: "On devices that support Apple Intelligence, the app offers an assistant that answers questions about your payments. It uses Apple's on-device language model (the Foundation Models framework). Your question and your payment data are processed on the device; the app sends nothing off the device. If the on-device model is not available, the assistant is simply unavailable.", bundle: .module)),
            ]),
            Section(title: String(localized: "Notifications, widget and Siri", bundle: .module), blocks: [
                .bullet(AttributedString(localized: "Payment reminders are local notifications scheduled on the device; they are only sent if you allow notifications.", bundle: .module)),
                .bullet(AttributedString(localized: "The widget and the Siri / Shortcuts actions read the same on-device data to show your upcoming payments and monthly total. When you use Siri, Apple's own privacy policy applies to Siri.", bundle: .module)),
            ]),
            Section(title: String(localized: "Deleting your data", bundle: .module), blocks: [
                .paragraph(AttributedString(localized: "Deleting a card or payment in the app removes it. Deleting the app removes all of its data from the device.", bundle: .module)),
            ]),
            Section(title: String(localized: "Changes to this policy", bundle: .module), blocks: [
                .paragraph(AttributedString(localized: "If this policy changes, the updated text will appear here with an app update.", bundle: .module)),
            ]),
        ]
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
#endif
