import SwiftUI
import VademCore

/// The Settings tab of the ``AppTabShell``: payment reminders on or off and when they fire,
/// and the monthly summary on or off.
///
/// The "Remind me" row is shown only while reminders are on. When reminders are on but the
/// system permission is denied, an explanation and an "Open Settings" button show.
/// No continuous animations, so it is idle under `-ui-static-motion`.
/// A ``DisplayHeader`` (`settings.header`) tops the screen.
/// Identifiers: `settings.reminders` (toggle), `settings.timing` (row), `settings.monthlySummary`
/// (toggle), the pushed list
/// `settings.timing.options` with `settings.timing.option.<index>`, `settings.permissionDenied`
/// (explanation), `settings.openSystemSettings` and `settings.version` (app version).
/// Shown inside the shell's `NavigationStack`. A Privacy Policy row (`settings.privacy`) pushes the ``PrivacyPolicyView``.
/// A "Show walkthrough again" row (`settings.showWalkthrough`) opens the ``OnboardingView`` full screen.
@MainActor
public struct SettingsView: View {
    /// The launch argument that opens the app on the Settings tab (UI check).
    public nonisolated static let launchArgument = "-ui-settings"
    /// The launch argument that opens this screen (like ``launchArgument``) with a denied permission,
    /// in sample-data mode (`-ui-sample-data`).
    public nonisolated static let deniedLaunchArgument = "-ui-settings-denied"

    /// The explanation shown when the system permission is denied.
    public nonisolated static var permissionDeniedMessage: String {
        String(localized: "Notifications are turned off for Vadem in Settings.", bundle: .module)
    }

    @State private var model: SettingsViewModel
    @State private var isChoosingTiming = false
    @State private var isShowingPrivacyPolicy: Bool
    // "Tanıtımı yeniden göster" ile açılan tanıtım; nil iken kapalı.
    @State private var onboardingModel: OnboardingViewModel?

    @Environment(\.scenePhase) private var scenePhase

    /// Creates the screen for `model`.
    ///
    /// In debug builds, ``PrivacyPolicyView/launchArgument`` pushes the privacy policy right away,
    /// for the UI check.
    public init(model: SettingsViewModel) {
        _model = State(initialValue: model)
        var initialShowsPrivacyPolicy = false
        #if DEBUG
        initialShowsPrivacyPolicy = ProcessInfo.processInfo.arguments.contains(PrivacyPolicyView.launchArgument)
        #endif
        _isShowingPrivacyPolicy = State(initialValue: initialShowsPrivacyPolicy)
    }

    public var body: some View {
        // Sekme kökü: zemin AppTabShell'in ortam arka planı.
        FormScroll(opaqueBackground: false) {
            // İlk görünüşte kademeli giriş: önce başlık ve hatırlatma kartı, sonra diğer kartlar.
            header
                .motionEntry(order: .header)
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
                // Aylık özet, hatırlatmalardan bağımsız açılıp kapanır.
                FormField(errorMessage: nil, errorIdentifier: "settings.monthlySummary.error") {
                    Toggle(isOn: Binding(
                        get: { model.isMonthlySummaryEnabled },
                        set: { model.setMonthlySummaryEnabled($0) }
                    )) {
                        Text("Monthly summary", bundle: .module)
                    }
                    .foregroundStyle(Color.vademTextPrimary)
                    .accessibilityIdentifier("settings.monthlySummary")
                }
            }
            .motionEntry(order: .header)
            if model.showsPermissionDenied {
                permissionDeniedCard
                    .motionEntry(order: .hero)
            }
            walkthroughCard
                .motionEntry(order: .list)
            privacyCard
                .motionEntry(order: .list)
            versionCard
                .motionEntry(order: .list)
        }
        // Giriş yalnızca ilk görünüşte; sonradan çıkan kartlar (izin uyarısı) doğrudan görünür.
        .motionEntryScope()
        .foregroundStyle(Color.vademTextPrimary)
        .tint(Color.vademBrand)
        .navigationDestination(isPresented: $isChoosingTiming) {
            OptionList(
                title: String(localized: "Remind me", bundle: .module), identifierPrefix: "settings.timing",
                options: timingOptions,
                selection: Binding(get: { model.timing }, set: { model.setTiming($0) })
            )
        }
        .navigationDestination(isPresented: $isShowingPrivacyPolicy) {
            PrivacyPolicyView()
        }
        #if os(iOS)
        .fullScreenCover(item: $onboardingModel) { onboarding in
            OnboardingView(model: onboarding)
        }
        #else
        .sheet(item: $onboardingModel) { onboarding in
            OnboardingView(model: onboarding)
        }
        #endif
        .navigationTitle(Text("Settings", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // Sekme kökü: çubuk kaydırma kenarında saydam, içerik altından geçince sistem malzemesi.
        .tabRootNavigationBar()
        #endif
        .task { await model.loadAuthorization() }
        // Ayarlar uygulamasından dönünce izin değişmiş olabilir.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.loadAuthorization() }
            }
        }
    }

    // Ekran başlığı: "Sana özel", vurgu son sözcükte.
    private var header: some View {
        let accent = String(localized: "yours", bundle: .module, comment: "Accented word of the Settings display title (Make it yours)")
        return DisplayHeader(
            eyebrow: AppTab.settings.title,
            title: String(localized: "Make it \(accent)", bundle: .module, comment: "Settings display title; the argument is accented"),
            accent: accent,
            identifier: "settings.header"
        )
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

    // Tanıtımı yeniden açan satır; Geç ya da Başla tanıtımı kapatır.
    private var walkthroughCard: some View {
        FormCard {
            Button {
                onboardingModel = model.makeOnboardingModel(isReplay: true) { onboardingModel = nil }
            } label: {
                HStack(spacing: 8) {
                    Text("Show walkthrough again", bundle: .module)
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
            .accessibilityHint(Text("Opens the walkthrough", bundle: .module))
            .accessibilityIdentifier("settings.showWalkthrough")
        }
    }

    // Gizlilik politikası satırı: ChoiceRow gibi düz düğme, politikayı uygulama içinde iter.
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
    NavigationStack {
        SettingsView(model: SettingsViewModel(dependencies: .inMemory(), repository: HomeSampleData.makeRepository()))
    }
}

#Preview("Denied") {
    NavigationStack {
        SettingsView(model: SettingsViewModel(dependencies: SettingsDependencies(
            store: InMemoryReminderPreferencesStore(), center: FixedStatusReminderCenter(status: .denied)
        )))
    }
}
#endif
