import SwiftUI
import VademCore

/// The app's root screen: the ``AppTabShell`` (Home and the other tabs), or a message when the store could not be opened.
@MainActor
public struct RootView: View {
    private enum Content {
        case home(HomeViewModel)
        case unavailable
    }

    /// The message shown when the store could not be opened.
    public nonisolated static var storeUnavailableMessage: String {
        String(localized: "Your data could not be opened. Please restart the app.", bundle: .module)
    }

    private let content: Content

    /// Shows the tab shell for `model`.
    public init(model: HomeViewModel) {
        content = .home(model)
    }

    /// Shows an error instead of Home, e.g. when the store could not be opened.
    public static func unavailable() -> RootView {
        RootView(content: .unavailable)
    }

    private init(content: Content) {
        self.content = content
    }

    public var body: some View {
        switch content {
        case .home(let model):
            AppTabShell(model: model)
        case .unavailable:
            // Depo açılamazsa uygulama çökmez; başlık ve sürüm yine görünür.
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AppHeader()
                    Label(Self.storeUnavailableMessage, systemImage: "exclamationmark.triangle")
                        .font(.body)
                        .foregroundStyle(Color.vademTextPrimary)
                        .accessibilityIdentifier("root.unavailable")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.vademBackground.ignoresSafeArea())
        }
    }
}

#if DEBUG
#Preview {
    RootView(model: HomeSampleData.makeViewModel())
}
#endif
