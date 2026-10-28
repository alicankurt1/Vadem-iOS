import XCTest

/// App Store ekran görüntüleri (`scripts/appstore-screenshots.sh` çalıştırır).
/// Erişilebilirlik denetimi, AX5/koyu varyant veya görünüm kontrolü YOKTUR; yalnızca düz ekran görüntüsü alır.
/// Dil `APPSTORE_LANGUAGE` ortam değişkeninden gelir (`en` | `tr`). Değişken yoksa testler atlanır,
/// böylece normal fonksiyonel/UICheck kapıları etkilenmez.
final class AppStoreScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHome() throws {
        let app = try launch(extraArguments: [])
        XCTAssertTrue(app.staticTexts["home.month"].waitForExistence(timeout: 10), "home.month did not appear")
        try shoot(app, name: "01-home")
    }

    @MainActor
    func testAddInstallment() throws {
        let app = try launch(extraArguments: ["-ui-add-form"])
        XCTAssertTrue(app.textFields["addInstallment.title"].waitForExistence(timeout: 10), "addInstallment.title did not appear")
        try shoot(app, name: "02-add-installment")
    }

    @MainActor
    func testAnalytics() throws {
        let app = try launch(extraArguments: ["-ui-analytics"])
        let marker = app.descendants(matching: .any)["analytics.breakdown"]
        XCTAssertTrue(marker.waitForExistence(timeout: 10), "analytics.breakdown did not appear")
        try shoot(app, name: "03-analytics")
    }

    @MainActor
    func testCards() throws {
        let app = try launch(extraArguments: ["-ui-card-list"])
        let marker = app.descendants(matching: .any)["cards.row.0"]
        XCTAssertTrue(marker.waitForExistence(timeout: 10), "cards.row.0 did not appear")
        try shoot(app, name: "04-cards")
    }

    // MARK: - Yardımcılar

    /// Dil argümanlarını ortamdan okur; değişken yoksa atlar, bilinmeyen değerde net şekilde başarısız olur.
    private func languageArguments() throws -> [String] {
        guard let language = ProcessInfo.processInfo.environment["APPSTORE_LANGUAGE"], !language.isEmpty else {
            throw XCTSkip("APPSTORE_LANGUAGE is not set; App Store screenshots are skipped.")
        }
        switch language {
        case "tr": return ["-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"]
        case "en": return ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        default:
            XCTFail("Unknown APPSTORE_LANGUAGE '\(language)' (expected 'en' or 'tr').")
            throw XCTSkip("unknown language")
        }
    }

    @MainActor
    private func launch(extraArguments: [String]) throws -> XCUIApplication {
        let languageArgs = try languageArguments()
        let app = XCUIApplication()
        // Bellek içi depo, kişisel veri yok; sürekli animasyonlar durur.
        app.launchArguments = ["-ui-sample-data", "-ui-static-motion"] + extraArguments + languageArgs
        app.launch()
        return app
    }

    /// Ekran durulana kadar (iki özdeş kare, en fazla ~3 sn) bekler, sonra tam ekran görüntüsünü ekler.
    @MainActor
    private func shoot(_ app: XCUIApplication, name: String) throws {
        var previous = app.screenshot().pngRepresentation
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.3)
            let current = app.screenshot().pngRepresentation
            if current == previous { break }
            previous = current
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
