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
    func testAnalyticsOpensFromHomeAndGoesBack() throws {
        let app = launchHome()

        // Araç çubuğundaki grafik düğmesi Analytics ekranını iter.
        let button = app.buttons["home.analytics"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "analytics button not found on Home")
        button.tap()
        XCTAssertTrue(element("analytics.screen", in: app).waitForExistence(timeout: 10), "Analytics screen must show")
        XCTAssertTrue(element("analytics.summary", in: app).waitForExistence(timeout: 5), "summary card must show")
        XCTAssertTrue(element("analytics.chart", in: app).exists, "chart must show")
        XCTAssertFalse(element("analytics.empty", in: app).exists, "sample data is not empty")

        // Geri düğmesi Home'a döner.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "Home must be visible after going back")
        XCTAssertFalse(element("analytics.screen", in: app).exists, "Analytics must be popped")
    }

    @MainActor
    func testSettingsTogglesRemindersAndPicksTiming() throws {
        let app = launchHome()

        let gear = app.buttons["home.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "settings button not found on Home")
        gear.tap()

        // Açılışta hatırlatmalar açık ve zamanlama satırı görünür.
        let toggle = app.switches["settings.reminders"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "reminders toggle not found")
        XCTAssertEqual(toggle.value as? String, "1", "reminders must start on")
        XCTAssertTrue(element("settings.timing", in: app).exists, "timing row must show while reminders are on")

        // Kapatınca zamanlama satırı kaybolur, açınca geri gelir.
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0", "reminders must turn off")
        XCTAssertFalse(element("settings.timing", in: app).waitForExistence(timeout: 2), "timing row must hide while off")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1", "reminders must turn on again")
        let timing = element("settings.timing", in: app)
        XCTAssertTrue(timing.waitForExistence(timeout: 5), "timing row must return when reminders are on")

        // Zamanlama listesi: 2. seçenek seçilince liste kapanır, ayarlar ekranına dönülür.
        timing.tap()
        let option = element("settings.timing.option.1", in: app)
        XCTAssertTrue(option.waitForExistence(timeout: 5), "timing option not found")
        option.tap()
        XCTAssertTrue(
            element("settings.timing", in: app).waitForExistence(timeout: 5),
            "must return to Settings after picking a timing"
        )
        XCTAssertFalse(element("settings.timing.option.1", in: app).exists, "option list must close after picking")

        // Bitti: sayfa kapanır ve Home görünür.
        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "Home must be visible after Done")
        XCTAssertFalse(app.switches["settings.reminders"].exists, "Settings must be dismissed")
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

    /// Silme düğmesi görünene dek formu yukarı kaydırır (en çok 6 kez).
    @MainActor
    private func revealDelete(prefix: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons["\(prefix).delete"]
        _ = button.waitForExistence(timeout: 5)
        for _ in 0..<6 where !button.isHittable {
            app.swipeUp()
        }
        return button
    }

    @MainActor
    func testEditInstallmentFromHomeSavesNewTitle() throws {
        let app = launchHome()
        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 10), "Home not shown")
        XCTAssertTrue(scrollToRow(titled: "Laptop", in: app), "sample installment 'Laptop' not shown on Home")
        row(titled: "Laptop", in: app).tap()

        // Form kayıtlı değerlerle açılır.
        let titleField = app.textFields["addInstallment.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "edit form not shown")
        XCTAssertEqual(titleField.value as? String, "Laptop", "title must be prefilled")
        XCTAssertTrue(app.buttons["addInstallment.save"].isEnabled, "save must be enabled with the saved values")

        titleField.tap()
        titleField.typeText(" Pro")
        app.buttons["addInstallment.save"].tap()

        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "form must be dismissed after saving")
        XCTAssertTrue(scrollToRow(titled: "Laptop Pro", in: app), "edited title not shown on Home")
    }

    @MainActor
    func testDeleteInstallmentFromHomeRemovesPayment() throws {
        let app = launchHome()
        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 10), "Home not shown")
        XCTAssertTrue(scrollToRow(titled: "Laptop", in: app), "sample installment 'Laptop' not shown on Home")
        row(titled: "Laptop", in: app).tap()

        let delete = revealDelete(prefix: "addInstallment", in: app)
        XCTAssertTrue(delete.exists, "delete button not found")
        delete.tap()

        // Önce onay istenir; vazgeçince form açık kalır.
        let cancel = app.buttons["addInstallment.delete.cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "confirmation not shown")
        cancel.tap()
        XCTAssertTrue(app.textFields["addInstallment.title"].exists, "form must stay open after cancelling")

        revealDelete(prefix: "addInstallment", in: app).tap()
        let confirm = app.buttons["addInstallment.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "confirmation not shown")
        confirm.tap()

        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "form must be dismissed after deleting")
        XCTAssertFalse(scrollToRow(titled: "Laptop", in: app), "deleted installment must not appear on Home")
    }

    @MainActor
    func testDeleteCardInUseShowsMessageAndKeepsForm() throws {
        let app = launchHome()
        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 10), "Home not shown")
        // Kart alt toplamları takvimin altında; ilki açılır.
        let card = element("home.card.0", in: app)
        for _ in 0..<6 where !card.exists { app.swipeUp() }
        XCTAssertTrue(card.exists, "card subtotal not found")
        card.tap()

        let delete = revealDelete(prefix: "addCard", in: app)
        XCTAssertTrue(delete.exists, "delete button not found")
        delete.tap()
        let confirm = app.buttons["addCard.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "confirmation not shown")
        confirm.tap()

        // Kart kullanımda: form açık kalır ve ret mesajı görünür.
        XCTAssertTrue(element("addCard.failure", in: app).waitForExistence(timeout: 5), "in-use message not shown")
        XCTAssertTrue(app.textFields["addCard.name"].exists, "form must stay open when the card is in use")
    }
}
