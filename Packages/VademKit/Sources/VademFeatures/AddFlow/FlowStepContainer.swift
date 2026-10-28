import SwiftUI

/// One step of an add flow: back and close buttons, a segmented progress bar ("Step 2 of 3"),
/// the step's question as a header and its content (one decision); an optional Continue button
/// sits below for steps that are not decided by a single tap (e.g. the amount keypad).
///
/// The content scrolls, so it fits at every Dynamic Type size. The progress bar animates with
/// ``Motion/quick`` only when ``Motion`` allows it (off under Reduce Motion and `-ui-static-motion`).
/// Identifiers: `flow.back`, `flow.close`, `flow.progress`, `flow.title`, `flow.continue`.
@MainActor
public struct FlowStepContainer<Content: View>: View {
    private let title: String
    private let stepNumber: Int
    private let stepCount: Int
    private let onBack: (() -> Void)?
    private let onClose: (() -> Void)?
    private let canContinue: Bool
    private let onContinue: (() -> Void)?
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates a step titled `title`, number `stepNumber` (1-based) of `stepCount`.
    ///
    /// `onBack` and `onClose` hide their buttons when `nil`. With `onContinue`, a Continue button
    /// is shown, enabled while `canContinue` is `true`.
    public init(
        title: String,
        stepNumber: Int,
        stepCount: Int,
        onBack: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        canContinue: Bool = true,
        onContinue: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        // Geçersiz sayılar ilerleme çubuğunu bozmasın: en az 1 adım, numara 1...adım sayısı.
        self.stepCount = max(stepCount, 1)
        self.stepNumber = min(max(stepNumber, 1), max(stepCount, 1))
        self.onBack = onBack
        self.onClose = onClose
        self.canContinue = canContinue
        self.onContinue = onContinue
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    progressBar
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.vademTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("flow.title")
                    content
                }
                // 20 pt yan boşluk: sol kenarda her zaman arka plan rengi kalır.
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let onContinue {
                continueButton(onContinue)
            }
        }
        .background(Color.vademBackground.ignoresSafeArea())
    }

    // Geri solda, kapat sağda; ikisi de en az 44 pt dokunma alanında.
    private var header: some View {
        HStack {
            if let onBack {
                iconButton(systemImage: "chevron.left", label: String(localized: "Back", bundle: .module), identifier: "flow.back", action: onBack)
            }
            Spacer(minLength: 0)
            if let onClose {
                iconButton(systemImage: "xmark", label: String(localized: "Close", bundle: .module), identifier: "flow.close", action: onClose)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(minHeight: 52)
    }

    // Adım başına bir dilim; geçilen ve mevcut adımlar dolu. VoiceOver "Adım 2 / 3" duyar.
    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(1...stepCount, id: \.self) { step in
                Capsule()
                    .fill(step <= stepNumber ? Color.vademBrand : Color.vademSeparator)
                    .frame(height: 6)
            }
        }
        .animation(Motion.animation(Motion.quick, reduceMotion: reduceMotion), value: stepNumber)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(stepNumber) of \(stepCount)", bundle: .module))
        .accessibilityIdentifier("flow.progress")
    }

    private func continueButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Continue", bundle: .module)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.vademOnAccent)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.vademAccent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canContinue)
        // Pasif durum saydamlıkla gösterilir; metin aynı kalır.
        .opacity(canContinue ? 1 : 0.5)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityIdentifier("flow.continue")
    }

    private func iconButton(systemImage: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.vademTextPrimary)
                // En az 44 pt dokunma alanı.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
