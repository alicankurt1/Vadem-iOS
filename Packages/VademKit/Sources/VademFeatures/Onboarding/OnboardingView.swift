import SwiftUI
import VademCore

/// The first-run walkthrough: four pages in a paged `TabView` with a page indicator in its own row
/// above the bottom button (never over the page content), Skip at the
/// top right on pages 1–3, Continue at the bottom (Get started on the last page).
///
/// Each page shows a static SF Symbol, a title and one sentence; VoiceOver reads the title and the
/// text together. Page content scrolls, so it fits at AX5 Dynamic Type. Moving to the next page is
/// animated only when motion is on (not under Reduce Motion or `-ui-static-motion`); there are no
/// continuous animations. The screen keeps its background color at the left edge.
///
/// Identifiers: `onboarding` (screen), `onboarding.page.<1…4>` (title and text of each page),
/// `onboarding.skip`, `onboarding.continue`, `onboarding.getStarted`, `onboarding.turnOnReminders`,
/// `onboarding.notNow`, `onboarding.reminderStatus` (the line shown after a reminder choice) and
/// `onboarding.pageIndicator` (adjustable: "Page 2 of 4").
@MainActor
public struct OnboardingView: View {
    @Bindable private var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Simge yazı boyutuyla büyür; AX5'te metne yer kalsın diye üst sınırı vardır.
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 72
    private static let maxIconSize: CGFloat = 112

    /// Creates the walkthrough for `model`.
    public init(model: OnboardingViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $model.pageIndex) {
                ForEach(Array(model.pages.enumerated()), id: \.element) { index, page in
                    pageView(page)
                        .tag(index)
                }
            }
            #if os(iOS)
            // Sistem göstergesi içeriğin üstüne biniyordu (AX5); yerine kendi satırında bir gösterge var.
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            pageIndicator
            bottomButton
        }
        .foregroundStyle(Color.vademTextPrimary)
        .tint(Color.vademBrand)
        // Sol kenar dahil tüm ekran düz zemin: UI yakalaması sol 4 pt şeridi örnekler.
        .background { Color.vademBackground.ignoresSafeArea() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding")
    }

    // Sağ üstte "Geç"; son sayfada yoktur, yükseklik korunur ki sayfa kaymasın.
    private var topBar: some View {
        HStack {
            Spacer(minLength: 0)
            if model.showsSkip {
                Button {
                    model.skip()
                } label: {
                    Text("Skip", bundle: .module)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.vademBrand)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.skip")
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                // Durağan simge; canlandırmalar ayrı bir işte gelir.
                Image(systemName: page.systemImage)
                    .font(.system(size: min(iconSize, Self.maxIconSize), weight: .regular))
                    .foregroundStyle(Color.vademBrand)
                    .accessibilityHidden(true)
                    .padding(.top, 24)
                // Başlık ve cümle VoiceOver'da tek öğe olarak birlikte okunur.
                VStack(spacing: 12) {
                    Text(page.title)
                        .font(.title.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(page.message)
                        .font(.body)
                        .foregroundStyle(Color.vademTextSecondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("onboarding.page.\(page.number)")
                if page == .reminders {
                    reminderControls
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // Son sayfa: hatırlatma seçimi; seçimden sonra düğmeler yerine durum satırı görünür.
    @ViewBuilder
    private var reminderControls: some View {
        if model.showsReminderButtons {
            VStack(spacing: 12) {
                Button {
                    model.turnOnReminders()
                } label: {
                    Text("Turn on reminders", bundle: .module)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.vademBrand)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.vademSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.turnOnReminders")
                Button {
                    model.notNow()
                } label: {
                    Text("Not now", bundle: .module)
                        .font(.body)
                        .foregroundStyle(Color.vademBrand)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.notNow")
            }
        } else if let status = model.reminderStatusText {
            Text(status)
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.reminderStatus")
        }
    }

    // Sayfa noktaları kaydırılan içeriğin dışında, alt düğmenin üstünde kendi satırında durur.
    // VoiceOver'da tek öğe: "Sayfa 2 / 4"; yukarı/aşağı kaydırma sayfa değiştirir.
    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(model.pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == model.pageIndex ? Color.vademBrand : Color.vademSeparator)
                    .frame(width: 8, height: 8)
            }
        }
        // En az 44×44 pt dokunma ve erişilebilirlik alanı: dolgu noktaların kendi çerçevesini büyütür,
        // contentShape bütün alanı sayar (yalnızca 8 pt'lik noktalar değil).
        .padding(.horizontal, 12)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
        // Erişilebilirlik çerçevesi de aynı alan; yoksa öğe noktaların birleşimi (8 pt) olur.
        .contentShape(.accessibility, .rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(model.pageIndex + 1) of \(model.pages.count)", bundle: .module))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.pageIndex += 1
            case .decrement: model.pageIndex -= 1
            @unknown default: break
            }
        }
        .accessibilityIdentifier("onboarding.pageIndicator")
        // Satır kendi yüksekliğinde, kaydırılan içeriğin dışında kalır.
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // Alt düğme: Devam; son sayfada Başla.
    private var bottomButton: some View {
        Button {
            withAnimation(Motion.animation(Motion.quick, reduceMotion: reduceMotion)) {
                model.continueTapped()
            }
        } label: {
            Group {
                if model.isLastPage {
                    Text("Get started", bundle: .module)
                } else {
                    Text("Continue", bundle: .module)
                }
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.vademOnAccent)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.vademAccent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityIdentifier(model.isLastPage ? "onboarding.getStarted" : "onboarding.continue")
    }
}

#if DEBUG
#Preview {
    OnboardingView(model: OnboardingViewModel(
        defaults: UserDefaults(suiteName: "preview.onboarding") ?? .standard,
        reminders: SettingsViewModel(dependencies: .inMemory())
    ))
}
#endif
