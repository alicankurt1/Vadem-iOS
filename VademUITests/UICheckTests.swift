import XCTest

// UI kontrol adımı için deterministik yakalama: her ekran, her görünüm varyantında
// ekran görüntüsü alır ve Apple'ın erişilebilirlik denetimini koşar.
// Kararı bu testler değil, ekran görüntülerini değerlendiren UI kontrol agent'ı verir;
// erişilebilirlik denetimi ise test hatası olarak raporlanır.
final class UICheckTests: XCTestCase {

    /// Bir görünüm varyantı: açık/koyu mod ve Dynamic Type boyutu.
    struct Variant {
        let name: String
        let appearance: XCUIDevice.Appearance
        let contentSize: String
    }

    static let variants: [Variant] = [
        Variant(name: "light-default", appearance: .light, contentSize: "UICTContentSizeCategoryL"),
        Variant(name: "dark-default", appearance: .dark, contentSize: "UICTContentSizeCategoryL"),
        Variant(name: "light-AX5", appearance: .light, contentSize: "UICTContentSizeCategoryAccessibilityXXXL"),
    ]

    override func setUpWithError() throws {
        // Bir varyant hata verse de diğerlerinin görüntüsü alınsın.
        continueAfterFailure = true
    }

    @MainActor
    override func tearDown() async throws {
        XCUIDevice.shared.appearance = .light
        try await super.tearDown()
    }

    @MainActor
    func testRootScreen() throws {
        try capture(screen: "root") { _ in
            // Kök ekran açılışta görünür; gezinme gerekmez.
        }
    }

    // MARK: - Helpers

    /// Uygulamayı her varyantta açar, `navigate` ile ekrana gider, görüntü alır ve denetler.
    @MainActor
    private func capture(screen: String, navigate: (XCUIApplication) -> Void) throws {
        for variant in Self.variants {
            XCUIDevice.shared.appearance = variant.appearance

            let app = XCUIApplication()
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", variant.contentSize]
            app.launch()
            navigate(app)

            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "\(screen)__\(variant.name)"
            attachment.lifetime = .keepAlways
            add(attachment)

            // Her sorun ayrı bir test hatası olur; mesajında ekran ve varyant yazar.
            try app.performAccessibilityAudit { issue in
                let element = issue.element.map { "'\($0.label)'" } ?? "screen"
                XCTFail("[a11y] \(screen)__\(variant.name): \(issue.compactDescription) — \(element)")
                return true
            }

            app.terminate()
        }
    }
}
