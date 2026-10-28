import SwiftUI
import VademCore

/// The settings sheet, opened from Home: payment reminders on or off and when they fire.
///
/// The "Remind me" row is shown only while reminders are on. When reminders are on but the
/// system permission is denied, an explanation and an "Open Settings" button show.
/// No continuous animations, so it is idle under `-ui-static-motion`.
/// Identifiers: `settings.reminders` (toggle), `settings.timing` (row), the pushed list
/// `settings.timing.options` with `settings.timing.option.<index>`, `settings.permissionDenied`
/// (explanation), `settings.openSystemSettings`, `settings.version` (app version) and `settings.done`.
/// When ``SettingsViewModel/showsCards`` is `true`, a Cards row (`settings.cards`) pushes the ``CardListView``.
/// A Privacy Policy row (`settings.privacy`) pushes the ``PrivacyPolicyView``.
@MainActor
public struct SettingsView: View {
    /// The launch argument that opens Home with this sheet already presented (UI check).
    public nonisolated static let launchArgument = "-ui-settings"
    /// The launch argument that opens this sheet (like ``launchArgument``) with a denied permission,
    /// in sample-data mode (`-ui-sample-data`).
    public nonisolated static let deniedLaunchArgument = "-ui-settings-denied"

    /// The explanation shown when the system permission is denied.
    public nonisolated static var permissionDeniedMessage: String {
        String(localized: "Notifications are turned off for Vadem in Settings.", bundle: .module)
    }

    @State private var model: SettingsViewModel
    @State private var isChoosingTiming = false
    // İtilmiş Kartlar ekranının modeli; nil iken ekran itilmemiştir.
    @State private var cardListModel: CardListViewModel?
    @State private var isShowingPrivacyPolicy: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    /// Creates the sheet for `model`.
    ///
    /// In debug builds, ``CardListView/launchArgument`` (or ``CardListView/emptyLaunchArgument``)
    /// pushes the Cards screen right away, for the UI check; ``PrivacyPolicyView/launchArgument``
    /// pushes the privacy policy.
    public init(model: SettingsViewModel) {
        _model = State(initialValue: model)
        var initialCardListModel: CardListViewModel?
        var initialShowsPrivacyPolicy = false
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(CardListView.launchArgument) || arguments.contains(CardListView.emptyLaunchArgument) {
            initialCardListModel = model.makeCardListModel()
        } else if arguments.contains(PrivacyPolicyView.launchArgument) {
            // İki ekran aynı anda itilemez; Kartlar önceliklidir.
            initialShowsPrivacyPolicy = true
        }
        #endif
        _cardListModel = State(initialValue: initialCardListModel)
        _isShowingPrivacyPolicy = State(initialValue: initialShowsPrivacyPolicy)
    }

    public var body: some View {
        NavigationStack {
            FormScroll {
                FormCard {
                    FormField(errorMessage: nil, errorIdentifier: "settings.reminders.error") {
                        Toggle(isOn: Binding(
                            get: { model.isEnabled },
                            set: { model.setEnabled($0) }
                        )) {
                            Text("Payment reminders", bundle: .module)
                        }
                        .foregroundStyle(Color.vademTextPrimary)
                        .accessibilityIdentifier("settings.reminders")
                    }
                    // Hatırlatmalar kapalıyken zamanlama seçilemez; satır gizlenir.
                    if model.showsTiming {
                        FormField(errorMessage: nil, errorIdentifier: "settings.timing.error") {
                            ChoiceRow(title: String(localized: "Remind me", bundle: .module), value: SettingsViewModel.title(of: model.timing)) {
                                isChoosingTiming = true
                            }
                            .accessibilityIdentifier("settings.timing")
                        }
                    }
                }
                if model.showsPermissionDenied {
                    permissionDeniedCard
                }
                if model.showsCards {
                    cardsCard
                }
                privacyCard
                versionCard
            }
            .foregroundStyle(Color.vademTextPrimary)
            .tint(Color.vademBrand)
            .navigationDestination(isPresented: $isChoosingTiming) {
                OptionList(
                    title: String(localized: "Remind me", bundle: .module), identifierPrefix: "settings.timing",
                    options: timingOptions,
                    selection: Binding(get: { model.timing }, set: { model.setTiming($0) })
                )
            }
            .navigationDestination(isPresented: cardListPresented) {
                if let cardListModel {
                    CardListView(model: cardListModel)
                }
            }
            .navigationDestination(isPresented: $isShowingPrivacyPolicy) {
                PrivacyPolicyView()
            }
            .navigationTitle(Text("Settings", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            // Formlar gibi: çubuk ekranın renk şemasına ve arka planına sabitlenir.
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbarBackground(Color(Color.vademBackground.resolve(in: environment)), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
        .task { await model.loadAuthorization() }
        // Ayarlar uygulamasından dönünce izin değişmiş olabilir.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.loadAuthorization() }
            }
        }
    }

    // İzin reddedilmiş: açıklama ve sistem Ayarları'nı açan düğme.
    private var permissionDeniedCard: some View {
        FormCard {
            // Düz metin: Dynamic Type ile sarılır, kırpılmaz.
            Text(Self.permissionDeniedMessage)
                .font(.body)
                .foregroundStyle(Color.vademTextPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .accessibilityIdentifier("settings.permissionDenied")
            // DeleteSection gibi düz metin + gizli simge; bağlantı satırı marka renginde (vurgu rengi metinde kullanılmaz).
            Button {
                model.openSystemSettings()
            } label: {
                HStack(spacing: 8) {
                    Text("Open Settings", bundle: .module)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.forward.app")
                        .font(.body)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Color.vademBrand)
                .multilineTextAlignment(.leading)
                .frame(minHeight: FormLayout.minRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.openSystemSettings")
        }
    }

    private var cardListPresented: Binding<Bool> {
        Binding(
            get: { cardListModel != nil },
            set: { if !$0 { cardListModel = nil } }
        )
    }

    // Kartlar satırı: kart listesini iter. ChoiceRow gibi düz düğme ve Dynamic Type ile büyüyen ok.
    private var cardsCard: some View {
        FormCard {
            Button {
                cardListModel = model.makeCardListModel()
            } label: {
                HStack(spacing: 8) {
                    Text("Cards", bundle: .module)
                        .font(.body)
                        .foregroundStyle(Color.vademTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.vademBrand)
                        .accessibilityHidden(true)
                }
                .multilineTextAlignment(.leading)
                .frame(minHeight: FormLayout.minRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens a list", bundle: .module))
            .accessibilityIdentifier("settings.cards")
        }
    }

    // Gizlilik politikası satırı: Kartlar satırı gibi düz düğme, politikayı uygulama içinde iter.
    private var privacyCard: some View {
        FormCard {
            Button {
                isShowingPrivacyPolicy = true
            } label: {
                HStack(spacing: 8) {
                    Text("Privacy Policy", bundle: .module)
                        .font(.body)
                        .foregroundStyle(Color.vademTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.vademBrand)
                        .accessibilityHidden(true)
                }
                .multilineTextAlignment(.leading)
                .frame(minHeight: FormLayout.minRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens the privacy policy", bundle: .module))
            .accessibilityIdentifier("settings.privacy")
        }
    }

    // Uygulama sürümü (Home'dan buraya taşındı); düz metin, Dynamic Type ile sarılır.
    private var versionCard: some View {
        FormCard {
            Text("Version \(VademCore.version)", bundle: .module)
                .font(.body)
                .foregroundStyle(Color.vademTextPrimary)
                .frame(maxWidth: .infinity, minHeight: FormLayout.minRowHeight, alignment: .leading)
                .accessibilityIdentifier("settings.version")
        }
    }

    private var timingOptions: [OptionList<ReminderTiming>.Option] {
        SettingsViewModel.timings.map { .init(value: $0, title: SettingsViewModel.title(of: $0)) }
    }
}

#if DEBUG
#Preview("Default") {
    SettingsView(model: SettingsViewModel(dependencies: .inMemory(), repository: HomeSampleData.makeRepository()))
}

#Preview("Denied") {
    SettingsView(model: SettingsViewModel(dependencies: SettingsDependencies(
        store: InMemoryReminderPreferencesStore(), center: FixedStatusReminderCenter(status: .denied)
    )))
}
#endif
