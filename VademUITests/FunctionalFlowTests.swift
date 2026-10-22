import XCTest

// Hızlı işlevsel akış testleri: kullanıcının temel işini uçtan uca yapabildiğini kanıtlar
// (formu aç, tutarı yaz, kaydet, Home'da gör). Ekran görüntüsü ve erişilebilirlik denetimi yok;
// onlar `UICheckTests`te. `scripts/ui-functional.sh` ile koşulur.
//
// `-ui-sample-data` bellek içi depo açar: gerçek veriye dokunulmaz, her test temiz başlar.
// `-ui-static-motion` sürekli animasyonları durdurur; uygulama hızla boşa düşer.
final class FunctionalFlowTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchHome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-static-motion", "-ui-sample-data"]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Home satırları "başlık, tutar, …" biçiminde birleşik etiketle okunur; başlığı içeren öğe aranır.
    @MainActor
    private func row(titled title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", title))
            .firstMatch
    }

    /// Home'u satır görünene dek yukarı kaydırır (en çok `attempts` kez); satır bulunursa `true`.
    @MainActor
    private func scrollToRow(titled title: String, in app: XCUIApplication, attempts: Int = 6) -> Bool {
        let target = row(titled: title, in: app)
        for _ in 0..<attempts {
            if target.exists { return true }
            app.swipeUp()
        }
        return target.exists
    }

    @MainActor
    func testAddInstallmentFromHomeShowsPaymentOnHome() throws {
        let app = launchHome()
        let title = "Test Phone"

        let add = app.buttons["home.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Home add button not found")
        add.tap()
        // `home.add` bir menü (Installment / Subscription): önce taksit seçilir.
        app.buttons["home.add.installment"].tap()

        // Boş formda kaydet kapalı.
        let titleField = app.textFields["addInstallment.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "title field not found")
        XCTAssertFalse(app.buttons["addInstallment.save"].isEnabled, "save must be disabled while the form is empty")

        titleField.tap()
        titleField.typeText(title)

        // Kart: seçim listesini aç; 0. satır "kart yok", 1. satır ilk gerçek kart.
        element("addInstallment.card", in: app).tap()
        let firstCard = element("addInstallment.option.1", in: app)
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "card option not found")
        firstCard.tap()

        // Tutar: ondalık klavye, boş alana yazılır.
        let amount = app.textFields["addInstallment.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5), "amount field not found")
        amount.tap()
        amount.typeText("1200")

        let save = app.buttons["addInstallment.save"]
        XCTAssertTrue(save.isEnabled, "save must be enabled once title, card and amount are filled")
        save.tap()

        // Form kapanır, Home yeniden yüklenir; yeni ödeme listede (liste takvimin altında, kaydırılır).
        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "form must be dismissed after saving")
        // Varsayılan ilk ay kartın bir sonraki vadesi; örnek veride 12 Ekim'de Travel kartının Ekim ekstresi
        // kapandı, bu yüzden ödeme Kasım'da. Ekim'de yoksa sonraki aya geçilir.
        if !scrollToRow(titled: title, in: app, attempts: 0) {
            app.swipeDown()
            app.swipeDown()
            app.buttons["home.nextMonth"].tap()
        }
        XCTAssertTrue(
            scrollToRow(titled: title, in: app),
            "saved installment '\(title)' not shown on Home"
        )
    }

    @MainActor
    func testCancelAddInstallmentLeavesHomeUnchanged() throws {
        let app = launchHome()

        let add = app.buttons["home.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Home add button not found")
        add.tap()
        app.buttons["home.add.installment"].tap()

        let titleField = app.textFields["addInstallment.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "title field not found")
        titleField.tap()
        titleField.typeText("Cancelled item")

        app.buttons["addInstallment.cancel"].tap()

        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "Home must be visible after cancel")
        XCTAssertFalse(scrollToRow(titled: "Cancelled item", in: app), "cancelled item must not appear on Home")
    }
}
