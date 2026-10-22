import SwiftUI

/// A rounded `vademSurface` container that stacks its rows with hairline `vademSeparator`
/// dividers between them (no border).
@MainActor
public struct SurfaceCard<Content: View>: View {
    private let content: Content

    @Environment(\.displayScale) private var displayScale

    /// Creates a card; every top-level view in `content` becomes one row.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    // Ayırıcı yalnızca satırların arasında; ilk satırın üstünde yok.
                    if row.id != rows.first?.id {
                        divider
                    }
                    row
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(Color.vademSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // Tek piksel kalınlığında çizgi; satır metniyle hizalı başlar.
    private var divider: some View {
        Rectangle()
            .fill(Color.vademSeparator)
            .frame(height: 1 / displayScale)
            .padding(.leading, 16)
            .accessibilityHidden(true)
    }
}

#Preview {
    SurfaceCard {
        Text("First")
        Text("Second")
        Text("Third")
    }
    .padding()
    .background(Color.vademBackground)
}
