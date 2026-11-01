import SwiftUI
import VademCore

/// The bottom sheet Home opens from Add: "What do you want to add?" and three large kind buttons,
/// Installment, Subscription and Payment (``AddFlowKind``).
///
/// Picking a kind that ``AddFlowKind/opensExistingForm`` calls `onSelect`; the presenter closes
/// the sheet and opens that form. Installment runs the ``InstallmentFlowView`` inside the sheet
/// (a new ``InstallmentFlowViewModel`` from `makeInstallmentFlow` each time; Save closes the sheet).
/// Subscription runs inside the sheet as a ``SubscriptionFlowView`` (back on its first step returns to the
/// three buttons). Payment runs inside the sheet as a ``OneTimeFlowView`` (a new ``OneTimeFlowViewModel``
/// from `makeOneTimeFlow` each time; back on its first step returns to the three buttons, Save closes the sheet).
/// The content scrolls and the sheet always opens at full height: with `presentationDetents`
/// (medium or even large only) the accessibility audit reported every multi-word text as clipped.
/// Each kind button reads its visible title and subtitle together (no custom label).
/// With `makeStatementImport`, a fourth option "Import from statement" (``statementImportIdentifier``) opens the
/// ``StatementImportView`` inside the sheet (back returns to the options). With `makeStatementReview` too, its
/// "Review and add" opens the ``StatementReviewView`` (back returns to the import screen, Add closes the sheet).
/// Identifiers: `add.sheet.title`, `add.sheet.close`, `add.sheet.<kind>` (``AddFlowKind/accessibilityIdentifier``),
/// `add.sheet.statementImport`.
/// No continuous animations, so it is idle under `-ui-static-motion`.
@MainActor
public struct AddFlowSheet: View {
    /// The launch argument that opens Home with this sheet already presented (UI check).
    public nonisolated static let launchArgument = "-ui-add-sheet"
    /// The accessibility identifier of the "Import from statement" option.
    public nonisolated static let statementImportIdentifier = "add.sheet.statementImport"

    private let onSelect: (AddFlowKind) -> Void
    private let makeInstallmentFlow: (() -> InstallmentFlowViewModel)?
    private let makeSubscriptionFlow: (() -> SubscriptionFlowViewModel)?
    private let makeOneTimeFlow: (() -> OneTimeFlowViewModel)?
    private let makeAddCardModel: (() -> AddCardViewModel)?
    private let makeStatementImport: (() -> StatementImportViewModel)?
    private let makeStatementReview: (([InstallmentCandidate]) -> StatementReviewViewModel)?
    // Sayfada süren abonelik akışının modeli; Abonelik seçilince kurulur.
    @State private var subscriptionFlow: SubscriptionFlowViewModel?
    // Sayfanın içinde süren akış; nil iken üç düğme görünür.
    @State private var inlineKind: AddFlowKind?
    // Süren taksit akışının modeli; her seçimde yenisi kurulur.
    @State private var installmentFlow: InstallmentFlowViewModel?
    // Süren tek seferlik ödeme akışının modeli; her seçimde yenisi kurulur.
    @State private var oneTimeFlow: OneTimeFlowViewModel?
    // Ekstreden içe aktarma ekranının modeli; nil değilken sayfada o ekran görünür.
    @State private var statementImport: StatementImportViewModel?
    // Bulunan taksitlerin inceleme ekranının modeli; nil değilken sayfada o ekran görünür.
    @State private var statementReview: StatementReviewViewModel?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates the sheet; `onSelect` gets the kinds that open an existing form and
    /// `makeInstallmentFlow` creates the model of the in-sheet installment flow.
    ///
    /// `makeSubscriptionFlow` and `makeAddCardModel` back the subscription flow; without them
    /// Subscription goes to `onSelect` like a kind that opens an existing form.
    /// `makeOneTimeFlow` creates the model of the in-sheet one-time payment flow (Payment); without it
    /// Payment goes to `onSelect`.
    /// `makeStatementImport` adds a fourth option, "Import from statement", that opens ``StatementImportView``
    /// inside the sheet with a new model each time; without it the option is hidden.
    /// `makeStatementReview` creates the review step's model for the found installments; without it the
    /// import screen has no review button.
    /// In debug builds, ``InstallmentFlowView/launchArgument`` starts with the installment flow running,
    /// a ``StatementImportLaunchState/launchArgument`` with the statement import screen in that state and
    /// ``StatementReviewView/launchArgument`` with the review of ``StatementReviewView/sampleCandidates``.
    public init(
        makeInstallmentFlow: (() -> InstallmentFlowViewModel)? = nil,
        makeSubscriptionFlow: (() -> SubscriptionFlowViewModel)? = nil,
        makeAddCardModel: (() -> AddCardViewModel)? = nil,
        makeOneTimeFlow: (() -> OneTimeFlowViewModel)? = nil,
        makeStatementImport: (() -> StatementImportViewModel)? = nil,
        makeStatementReview: (([InstallmentCandidate]) -> StatementReviewViewModel)? = nil,
        onSelect: @escaping (AddFlowKind) -> Void
    ) {
        self.makeInstallmentFlow = makeInstallmentFlow
        self.makeSubscriptionFlow = makeSubscriptionFlow
        self.makeAddCardModel = makeAddCardModel
        self.makeOneTimeFlow = makeOneTimeFlow
        self.makeStatementImport = makeStatementImport
        self.makeStatementReview = makeStatementReview
        self.onSelect = onSelect
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(StatementReviewView.launchArgument), let makeStatementReview {
            // İnceleme ekranı örnek adaylarla doğrudan açılır; geri dönülünce seçenekler görünür.
            _statementReview = State(initialValue: makeStatementReview(StatementReviewView.sampleCandidates))
        }
        if let launchState = StatementImportLaunchState.state(in: ProcessInfo.processInfo.arguments),
           let makeStatementImport {
            // Boş ekran gerçek kaynakla, sonuç durumları sahte kaynakla açılır.
            _statementImport = State(initialValue: launchState == .idle ? makeStatementImport() : launchState.makeModel())
        }
        if ProcessInfo.processInfo.arguments.contains(InstallmentFlowView.launchArgument), let makeInstallmentFlow {
            _installmentFlow = State(initialValue: makeInstallmentFlow())
            _inlineKind = State(initialValue: .installment)
        }
        #endif
    }

    public var body: some View {
        Group {
            if inlineKind == .installment, let installmentFlow {
                InstallmentFlowView(
                    model: installmentFlow,
                    onExit: { showChooser() },
                    onClose: { dismiss() },
                    onSaved: { dismiss() }
                )
            } else if inlineKind == .payment, let oneTimeFlow {
                OneTimeFlowView(
                    model: oneTimeFlow,
                    onExit: { showChooser() },
                    onClose: { dismiss() },
                    onSaved: { dismiss() }
                )
            } else if inlineKind == .subscription, let subscriptionFlow, let makeAddCardModel {
                SubscriptionFlowView(model: subscriptionFlow, makeAddCardModel: makeAddCardModel) {
                    withAnimation(Motion.animation(Motion.quick, reduceMotion: reduceMotion)) {
                        inlineKind = nil
                    }
                }
            } else if let statementReview {
                StatementReviewView(
                    model: statementReview,
                    onBack: { showStatementImport() },
                    onCancel: { dismiss() },
                    onSaved: { dismiss() }
                )
            } else if let statementImport {
                StatementImportView(
                    model: statementImport,
                    onBack: { showChooser() },
                    onClose: { dismiss() },
                    onReview: makeStatementReview.map { make in
                        { candidates in
                            withAnimation(Motion.animation(Motion.quick, reduceMotion: reduceMotion)) {
                                // Her incelemede yeni model: önceki düzenlemeler taşınmaz.
                                statementReview = make(candidates)
                            }
                        }
                    }
                )
            } else {
                chooser
            }
        }
        .background(Color.vademBackground.ignoresSafeArea())
    }

    private func select(_ kind: AddFlowKind) {
        if kind == .subscription {
            // Fabrika verilmediyse abonelik eski formu açar.
            guard let makeSubscriptionFlow, makeAddCardModel != nil else {
                onSelect(kind)
                return
            }
            // Her seçimde yeni akış: önceki yarım kalan girişler taşınmaz.
            subscriptionFlow = makeSubscriptionFlow()
        }
        if kind == .payment {
            // Fabrika verilmediyse seçim sunucuya bırakılır.
            guard let makeOneTimeFlow else {
                onSelect(kind)
                return
            }
            // Her seçimde yeni akış: önceki yarım kalan girişler taşınmaz.
            oneTimeFlow = makeOneTimeFlow()
        }
        if kind.opensExistingForm {
            onSelect(kind)
        } else {
            withAnimation(Motion.animation(Motion.quick, reduceMotion: reduceMotion)) {
                // Taksit akışı her açılışta baştan başlar.
                if kind == .installment { installmentFlow = makeInstallmentFlow?() }
                inlineKind = kind
            }
        }
    }

    // Akıştan üç düğmeye dönüş.
    private func showChooser() {
        withAnimation(Motion.animation(Motion.quick, reduceMotion: reduceMotion)) {
            inlineKind = nil
            installmentFlow = nil
            oneTimeFlow = nil
            statementImport = nil
            statementReview = nil
        }
    }

    // İncelemeden içe aktarma ekranına dönüş; okunan sonuç korunur (yoksa seçenekler görünür).
    private func showStatementImport() {
        withAnimation(Motion.animation(Motion.quick, reduceMotion: reduceMotion)) {
            statementReview = nil
        }
    }

    private var chooser: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.vademTextPrimary)
                        // En az 44 pt dokunma alanı.
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close", bundle: .module))
                .accessibilityIdentifier("add.sheet.close")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What do you want to add?", bundle: .module)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.vademTextPrimary)
                        // Metin her boyutta tam yüksekliğini alır, sarılır; asla kırpılmaz.
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("add.sheet.title")
                    ForEach(AddFlowKind.allCases) { kind in
                        kindButton(kind)
                    }
                    if let makeStatementImport {
                        statementImportButton(makeStatementImport)
                    }
                }
                // 20 pt yan boşluk: sol kenarda her zaman arka plan rengi kalır.
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    // Büyük düğme: simge, başlık ve altında kısa açıklama; VoiceOver ikisini birlikte okur.
    private func kindButton(_ kind: AddFlowKind) -> some View {
        optionButton(
            title: kind.title, subtitle: kind.subtitle, systemImage: kind.systemImage,
            identifier: kind.accessibilityIdentifier
        ) {
            select(kind)
        }
    }

    // Ekstreden içe aktarma: dördüncü seçenek, aynı görünümde.
    private func statementImportButton(_ makeStatementImport: @escaping () -> StatementImportViewModel) -> some View {
        optionButton(
            title: String(localized: "Import from statement", bundle: .module),
            subtitle: String(localized: "Find installments in a PDF or image", bundle: .module),
            systemImage: "doc.text.viewfinder",
            identifier: Self.statementImportIdentifier
        ) {
            withAnimation(Motion.animation(Motion.quick, reduceMotion: reduceMotion)) {
                // Her açılışta baştan: önceki sonuç taşınmaz.
                statementImport = makeStatementImport()
            }
        }
    }

    private func optionButton(
        title: String, subtitle: String, systemImage: String, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            AddFlowOptionLabel(title: title, subtitle: subtitle, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        // Etiket görünen başlık + açıklamanın kendisi: özel etiket görünen metinden farklı olunca
        // denetim metni "kırpılmış" sayıyor.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// The look of a large Add sheet option: symbol, title and a short line under it, on a surface card.
///
/// At accessibility text sizes the symbol sits above the text and the chevron is hidden, so words never break.
@MainActor
struct AddFlowOptionLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Erişilebilir yazı boyutlarında simge metnin üstünde ve ok gizli: metin tüm genişliği
        // alır, kelimeler ortadan bölünmez. AnyLayout metinlerin kimliğini korur.
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        layout {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.vademBrand)
                .frame(minWidth: 32, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.vademTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.vademTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .multilineTextAlignment(.leading)
            if !stacked {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.vademTextSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(Color.vademSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(.rect)
    }
}

#if DEBUG
#Preview {
    Color.vademBackground
        .sheet(isPresented: .constant(true)) {
            AddFlowSheet { _ in }
        }
}
#endif
