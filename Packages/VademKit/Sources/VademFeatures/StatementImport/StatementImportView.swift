import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VademCore

/// The "Import from statement" screen inside the ``AddFlowSheet``: pick a PDF (document picker) or an image
/// (photo picker); the file is read on the device and the installments found are listed read-only.
///
/// While reading, a progress indicator shows (a static symbol under Reduce Motion or `-ui-static-motion`);
/// nothing readable, no installment and a failed read each get their own message. Nothing is saved here.
/// Identifiers: `statementImport.back`, `statementImport.close`, `statementImport.title`,
/// `statementImport.choosePDF`, `statementImport.chooseImage`, `statementImport.reading`,
/// `statementImport.noText`, `statementImport.noInstallments`, `statementImport.failed`,
/// `statementImport.results` and `statementImport.candidate.<index>` (0-based, statement order).
@MainActor
public struct StatementImportView: View {
    @Bindable private var model: StatementImportViewModel
    private let onBack: () -> Void
    private let onClose: () -> Void

    @State private var isPDFPickerPresented = false
    @State private var photoItem: PhotosPickerItem?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates the screen for `model`; `onBack` returns to the Add sheet's options, `onClose` closes the sheet.
    public init(model: StatementImportViewModel, onBack: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.model = model
        self.onBack = onBack
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Import from statement", bundle: .module)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.vademTextPrimary)
                        // Metin her boyutta tam yüksekliğini alır, sarılır; asla kırpılmaz.
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("statementImport.title")
                    Text("Pick your statement as a PDF or an image. It is read on this device; nothing is uploaded.", bundle: .module)
                        .font(.subheadline)
                        .foregroundStyle(Color.vademTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)
                    Button {
                        isPDFPickerPresented = true
                    } label: {
                        optionLabel(
                            title: String(localized: "Choose PDF", bundle: .module),
                            subtitle: String(localized: "A statement downloaded from your bank", bundle: .module),
                            systemImage: "doc.text"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isReading)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("statementImport.choosePDF")
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        optionLabel(
                            title: String(localized: "Choose image", bundle: .module),
                            subtitle: String(localized: "A screenshot or photo of your statement", bundle: .module),
                            systemImage: "photo"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isReading)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("statementImport.chooseImage")
                    status
                        .padding(.top, 8)
                }
                // 20 pt yan boşluk: sol kenarda her zaman arka plan rengi kalır.
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color.vademBackground.ignoresSafeArea())
        .fileImporter(isPresented: $isPDFPickerPresented, allowedContentTypes: [.pdf]) { result in
            // Vazgeçilirse durum değişmez; açılamayan dosya hata mesajı gösterir.
            switch result {
            case .success(let url):
                Task { await model.readPDF(at: url) }
            case .failure:
                model.showFailure()
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            // Aynı resim yeniden seçilebilsin diye seçim hemen temizlenir.
            photoItem = nil
            Task { await model.readImage { try await item.loadTransferable(type: Data.self) } }
        }
    }

    // Geri solda, kapat sağda; ikisi de en az 44 pt dokunma alanında.
    private var header: some View {
        HStack {
            iconButton(systemImage: "chevron.left", label: String(localized: "Back", bundle: .module), identifier: "statementImport.back", action: onBack)
            Spacer(minLength: 0)
            iconButton(systemImage: "xmark", label: String(localized: "Close", bundle: .module), identifier: "statementImport.close", action: onClose)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(minHeight: 52)
    }

    @ViewBuilder
    private var status: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .reading:
            HStack(spacing: 12) {
                if Motion.isAnimated(reduceMotion: reduceMotion, staticMotionRequested: Motion.staticMotionRequested) {
                    ProgressView()
                } else {
                    // Sürekli dönen gösterge yerine sabit simge: UI kontrolünde ekran durgun kalır.
                    Image(systemName: "hourglass")
                        .foregroundStyle(Color.vademTextSecondary)
                }
                Text("Reading the statement…", bundle: .module)
                    .font(.body)
                    .foregroundStyle(Color.vademTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("statementImport.reading")
        case .noText:
            message(
                Text("Nothing readable was found in this file. Try a clearer image or another PDF.", bundle: .module),
                systemImage: "text.magnifyingglass", identifier: "statementImport.noText"
            )
        case .noInstallments:
            message(
                Text("No installments were found in this statement.", bundle: .module),
                systemImage: "list.bullet.rectangle", identifier: "statementImport.noInstallments"
            )
        case .failed:
            message(
                Text("This file could not be opened. Try another PDF or image.", bundle: .module),
                systemImage: "exclamationmark.triangle", identifier: "statementImport.failed"
            )
        case .found(let candidates):
            // #216 burada inceleme ve onay adımını gösterecek; şimdilik salt okunur liste.
            results(candidates)
        }
    }

    private func message(_ text: Text, systemImage: String, identifier: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.vademTextSecondary)
                .accessibilityHidden(true)
            text
                .font(.body)
                .foregroundStyle(Color.vademTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vademSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func results(_ candidates: [InstallmentCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Installments found", bundle: .module)
                .font(.headline)
                .foregroundStyle(Color.vademTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                    if index > 0 {
                        Divider().overlay(Color.vademSeparator)
                    }
                    candidateRow(candidate)
                        .accessibilityIdentifier("statementImport.candidate.\(index)")
                }
            }
            .background(Color.vademSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("statementImport.results")
    }

    // Satıcı, taksit sırası (3/6) ve taksit tutarı; VoiceOver hepsini tek öğe olarak, tam etiketle okur.
    private func candidateRow(_ candidate: InstallmentCandidate) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.merchant)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.vademTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "\(candidate.currentInstallment)/\(candidate.totalInstallments)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Color.vademTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            AmountText(Money(candidate.installmentAmount))
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.vademTextPrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Satır tek öğe ve etiketi tam ("taksit 3/6"); görünen "3/6" metni ayrı, kısa etiketli öğe olmaz,
        // böylece denetim onu kırpılmış metin sanmaz.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(candidate.merchant) + Text(verbatim: ", ")
                + Text("installment \(candidate.currentInstallment) of \(candidate.totalInstallments)", bundle: .module)
                + Text(verbatim: ", ") + Text(AmountText.spokenLabel(Money(candidate.installmentAmount)))
        )
    }

    // Ekle sayfasındaki seçeneklerle aynı görünüm: simge, başlık ve altında kısa açıklama.
    private func optionLabel(title: String, subtitle: String, systemImage: String) -> some View {
        AddFlowOptionLabel(title: title, subtitle: subtitle, systemImage: systemImage)
            .opacity(model.isReading ? 0.5 : 1)
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

#if DEBUG
/// The debug launch states of the statement import screen: each launch argument opens the Add sheet
/// on ``StatementImportView`` in that state, with a ``ScriptedStatementTextSource`` (no system picker needed).
public enum StatementImportLaunchState: String, CaseIterable, Sendable {
    /// `-ui-statement-import-found`: three sample installments listed.
    case found
    /// `-ui-statement-import-no-installments`: text without installments.
    case noInstallments = "no-installments"
    /// `-ui-statement-import-no-text`: nothing readable.
    case noText = "no-text"
    /// `-ui-statement-import-failed`: the file could not be opened.
    case failed
    /// `-ui-statement-import`: the screen before a file is picked.
    case idle

    /// The launch argument that opens this state.
    public var launchArgument: String {
        self == .idle ? "-ui-statement-import" : "-ui-statement-import-\(rawValue)"
    }

    /// The state whose ``launchArgument`` is in `arguments` (result states before ``idle``), or `nil`.
    public static func state(in arguments: [String]) -> StatementImportLaunchState? {
        allCases.first { arguments.contains($0.launchArgument) }
    }

    /// Synthetic statement lines with three installments and a total line the parser skips.
    public static let sampleLines = [
        "12.10.2026 ORNEK ELEKTRONIK 3/6 1.234,56 TL",
        "15.10.2026 ORNEK GIYIM Taksit 2/4 450,00",
        "ORNEK MOBILYA 5. taksit / 12 2.500,00",
        "DONEM BORCU TOPLAMI 4.184,56",
    ]

    /// A model in this state; picking a file again reads ``sampleLines``.
    @MainActor
    public func makeModel() -> StatementImportViewModel {
        let model = StatementImportViewModel(source: ScriptedStatementTextSource(lines: Self.sampleLines))
        switch self {
        case .found: model.show(lines: Self.sampleLines)
        case .noInstallments: model.show(lines: ["ORNEK MARKET 85,50", "DONEM BORCU TOPLAMI 85,50"])
        case .noText: model.show(lines: [])
        case .failed: model.showFailure()
        case .idle: break
        }
        return model
    }
}
#endif
