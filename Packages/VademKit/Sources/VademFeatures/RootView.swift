import SwiftUI
import VademCore

// Uygulamanın kök ekranı; özellik ekranları ileriki fazlarda buraya bağlanacak.
@MainActor
public struct RootView: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView(
            "Vadem",
            systemImage: "creditcard",
            description: Text("v\(VademCore.version)")
        )
    }
}

#Preview {
    RootView()
}
