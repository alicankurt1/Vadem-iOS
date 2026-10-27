import SwiftUI
import VademCore

/// The Cards screen, pushed from Settings: every saved card as a card face with its name and due day.
///
/// Tapping a card opens the edit-card form (edit and delete) as a sheet; the toolbar's Add button
/// opens the add-card form. The list reloads whenever a form closes. Without cards an empty state
/// explains the screen and offers an add button. The card faces stop drifting under Reduce Motion
/// or `-ui-static-motion`, so the screen is idle in the UI check.
/// Identifiers: `cards.list` (the screen), `cards.add` (toolbar), `cards.row.<index>` (cards, from 0),
/// `cards.empty` (empty-state text), `cards.empty.add` (empty-state button) and `cards.error`.
@MainActor
public struct CardListView: View {
    /// The launch argument that opens Home with Settings presented and this screen pushed (debug builds).
    public nonisolated static let launchArgument = "-ui-card-list"
    /// The launch argument that opens this screen (like ``launchArgument``) on an empty store,
    /// in sample-data mode (`-ui-sample-data`), so the empty state shows.
    public nonisolated static let emptyLaunchArgument = "-ui-card-list-empty"

    @State private var model: CardListViewModel
    // Açık kart formunun modeli (ekleme veya düzenleme); nil iken sayfa kapalı.
    @State private var formModel: AddCardViewModel?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    /// Creates the screen for `model`.
    public init(model: CardListViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FormLayout.spacing) {
                content
            }
            // Yan boşluk: ekranın sol kenarında her zaman arka plan rengi kalır.
            .padding(FormLayout.spacing)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.vademBackground.ignoresSafeArea())
        .foregroundStyle(Color.vademTextPrimary)
        .tint(Color.vademBrand)
        .navigationTitle(Text("Cards", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // Ayarlar gibi: çubuk ekranın renk şemasına ve arka planına sabitlenir.
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .toolbarBackground(Color(Color.vademBackground.resolve(in: environment)), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) { addButton }
        }
        // Form kapanınca (kaydedilse, silinse veya iptal edilse de) liste yeniden yüklenir.
        .sheet(item: $formModel, onDismiss: { model.refresh() }) { formModel in
            AddCardView(model: formModel)
        }
        .accessibilityIdentifier("cards.list")
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loaded:
            ForEach(Array(model.cards.enumerated()), id: \.element.id) { index, card in
                row(card, index: index)
            }
        case .empty:
            emptyState
        case .error(let message):
            FormCard {
                FormFailureRow(message: message)
                    .accessibilityIdentifier("cards.error")
            }
        }
    }

    // Kart yüzü düğme: dokununca kartın düzenleme formu açılır.
    private func row(_ card: Card, index: Int) -> some View {
        Button {
            formModel = model.makeEditCardModel(for: card)
        } label: {
            CardFaceView(
                title: card.name,
                subtitle: CardListViewModel.dueDayText(for: card),
                style: .default(for: card.id)
            )
            .multilineTextAlignment(.leading)
            .contentShape(.rect(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Edits the card", bundle: .module))
        .accessibilityIdentifier("cards.row.\(index)")
    }

    // Boş durum: kısa açıklama ve kart ekleme düğmesi.
    private var emptyState: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                Image(systemName: "creditcard")
                    .font(.largeTitle)
                    .foregroundStyle(Color.vademTextSecondary)
                    .accessibilityHidden(true)
                Text("No cards yet", bundle: .module)
                    .font(.headline)
                    .foregroundStyle(Color.vademTextPrimary)
                Text("Add a card to start tracking installments.", bundle: .module)
                    .font(.body)
                    .foregroundStyle(Color.vademTextSecondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("cards.empty")
            Button {
                formModel = model.makeAddCardModel()
            } label: {
                Label { Text("Add a card", bundle: .module) } icon: { Image(systemName: "plus.circle") }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.vademTextPrimary)
                    .frame(maxWidth: .infinity, minHeight: FormLayout.minRowHeight)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cards.empty.add")
        }
    }

    // Araç çubuğundaki ekleme düğmesi: boş kart formunu açar.
    private var addButton: some View {
        Button {
            formModel = model.makeAddCardModel()
        } label: {
            Image(systemName: "plus")
                .foregroundStyle(Color.vademTextPrimary)
                // En az 44 pt dokunma alanı.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel(Text("Add a card", bundle: .module))
        .accessibilityIdentifier("cards.add")
    }
}

#if DEBUG
#Preview("Cards") {
    NavigationStack {
        CardListView(model: CardListViewModel(repository: HomeSampleData.makeRepository()))
    }
}

#Preview("Empty") {
    NavigationStack {
        CardListView(model: CardListViewModel(repository: InMemoryPaymentRepository()))
    }
}
#endif
