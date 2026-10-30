import SwiftUI
import VademCore

/// The in-app inbox, pushed from This month's bell button (`home.inbox`): the monthly insights,
/// newest first, each with its title, text, date and an unread marker.
///
/// Appearing marks every entry read (``InboxViewModel/open()``); the markers stay for this visit.
/// Swiping an entry deletes it (it does not come back). With no entries an empty state shows.
/// Plain list on `vademBackground` with `vademSurface` rows, no continuous animations, so it is idle
/// under `-ui-static-motion`; text wraps freely up to AX5.
///
/// Identifiers: `inbox.header` (serif title), `inbox.list` (the list), `inbox.entry.<index>` (entries,
/// from 0, newest first), `inbox.entry.<index>.delete` (swipe action), `inbox.empty` and `inbox.error`.
///
/// Debug launch arguments (sample data, in memory; reminders are never scheduled, so the permission
/// prompt never shows): ``launchArgument`` (`-ui-inbox`) fills the inbox with sample entries and
/// opens This month with the unread badge; ``openLaunchArgument`` (`-ui-inbox-open`) does the same and
/// pushes the inbox; ``emptyLaunchArgument`` (`-ui-inbox-empty`) pushes an empty inbox.
@MainActor
public struct InboxView: View {
    /// Sample inbox entries, This month with the unread badge (debug builds).
    public nonisolated static let launchArgument = "-ui-inbox"
    /// Sample inbox entries with the inbox pushed (debug builds, UI capture).
    public nonisolated static let openLaunchArgument = "-ui-inbox-open"
    /// An empty inbox, pushed (debug builds, UI capture of the empty state).
    public nonisolated static let emptyLaunchArgument = "-ui-inbox-empty"

    /// Every inbox launch argument; any of them starts the app on sample data.
    public nonisolated static let launchArguments = [launchArgument, openLaunchArgument, emptyLaunchArgument]

    @State private var model: InboxViewModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    /// Creates the screen for `model`.
    public init(model: InboxViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        content
            .foregroundStyle(Color.vademTextPrimary)
            .background(Color.vademBackground.ignoresSafeArea())
            .navigationTitle(Text("Inbox", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            // Diğer itilen ekranlar gibi: çubuk ekranın renk şemasına ve arka planına sabitlenir.
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbarBackground(Color(Color.vademBackground.resolve(in: environment)), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            // Ekran göründü: girdiler okundu sayılır (işaretler bu ziyarette kalır).
            .onAppear { model.open() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loaded:
            list
        case .empty:
            message(
                title: String(localized: "No notifications yet", bundle: .module),
                detail: String(localized: "Monthly insights about your payments appear here.", bundle: .module),
                systemImage: "bell.slash"
            )
            .accessibilityIdentifier("inbox.empty")
        case .error(let text):
            message(
                title: String(localized: "Something went wrong", bundle: .module), detail: text,
                systemImage: "exclamationmark.triangle"
            )
            .accessibilityIdentifier("inbox.error")
        }
    }

    // Kaydırarak silme yalnızca List'te var; her girdi kendi bölümünde, yüzey renginde bir kart gibi durur.
    private var list: some View {
        List {
            Section {
                header
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                Section {
                    InboxEntryRow(row: row)
                        .accessibilityIdentifier("inbox.entry.\(index)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                model.delete(id: row.id)
                            } label: {
                                Label { Text("Delete", bundle: .module) } icon: { Image(systemName: "trash") }
                            }
                            .accessibilityIdentifier("inbox.entry.\(index).delete")
                        }
                }
                .listRowBackground(Color.vademSurface)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        .listSectionSpacing(12)
        #endif
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("inbox.list")
    }

    // Serif ekran başlığı; AX5'te alt satıra sarılır.
    private var header: some View {
        DisplayTitle(String(localized: "Your notifications", bundle: .module), identifier: "inbox.header")
    }

    // Boş ve hata durumu: kaydırılabilir, ortalanmış ikon, başlık ve açıklama (AX5'te de kırpılmaz).
    private func message(title: String, detail: String, systemImage: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                VStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.largeTitle)
                        .foregroundStyle(Color.vademTextSecondary)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.vademTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.body)
                        .foregroundStyle(Color.vademTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .accessibilityElement(children: .combine)
            }
            // 20 pt yan boşluk: ekranın sol kenarında her zaman arka plan rengi kalır.
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One inbox entry: an unread marker, the title, the text and the date; VoiceOver reads it as one element.
@MainActor
struct InboxEntryRow: View {
    let row: InboxViewModel.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // Okunmamış işareti: dolu marka rengi nokta; okunmuşta yer tutan boşluk (hizalama bozulmaz).
            Circle()
                .fill(row.isUnread ? Color.vademBrand : Color.clear)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(row.title)
                    .font(row.isUnread ? .headline : .body.weight(.medium))
                    .foregroundStyle(Color.vademTextPrimary)
                Text(row.body)
                    .font(.body)
                    .foregroundStyle(Color.vademTextPrimary)
                Text(row.dateText)
                    .font(.footnote)
                    .foregroundStyle(Color.vademTextSecondary)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        InboxView(model: InboxViewModel(repository: HomeSampleData.makeInboxRepository()))
    }
}
#endif
