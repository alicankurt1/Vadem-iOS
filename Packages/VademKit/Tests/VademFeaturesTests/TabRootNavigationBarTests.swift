import Foundation
import SwiftUI
import Testing
@testable import VademFeatures

/// Sekme kök ekranlarının gezinme çubuğu ortam arka planıyla bütünleşmeli (#229).
@Suite("Tab root navigation bar")
struct TabRootNavigationBarTests {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()                              // VademKit
        .appendingPathComponent("Sources/VademFeatures")

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: sources.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("Bar background follows the system scroll-edge behavior, not a forced solid color")
    func backgroundIsAutomatic() {
        #expect(TabRootNavigationBarModifier.backgroundVisibility == .automatic)
    }

    @Test("Every tab root uses the shared navigation bar style", arguments: [
        "Home/HomeView.swift",
        "Analytics/AnalyticsView.swift",
        "Cards/CardListView.swift",
        "Settings/SettingsView.swift",
    ])
    func tabRootsUseSharedStyle(path: String) throws {
        let text = try Self.source(path)
        #expect(text.contains(".tabRootNavigationBar()"))
        // Düz vademBackground çubuk rengi (renk bandı) geri gelmemeli.
        #expect(!text.contains(".toolbarBackground(.visible, for: .navigationBar)"))
        #expect(!text.contains(".toolbarBackground(Color(Color.vademBackground"))
    }
}
