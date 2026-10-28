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
    private func launchHome(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-static-motion", "-ui-sample-data"] + extraArguments
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
        try addInstallmentAndFindItOnHome(extraArguments: [])
    }

    /// Aynı akış Türkçe arayüzle (#136): kimlikler dilden bağımsız, kayıt ve Home listesi çalışmalı.
    @MainActor
    func testAddInstallmentFromHomeInTurkish() throws {
        try addInstallmentAndFindItOnHome(extraArguments: ["-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"])
    }

    @MainActor
    private func addInstallmentAndFindItOnHome(extraArguments: [String]) throws {
        let app = launchHome(extraArguments: extraArguments)
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

    /// #155: kart eklemeden taksit eklenir. Kart seçilmez ("No card" kalır), ödeme günü alanı görünür,
    /// gün 3 yapılır; kayıttan sonra Home satırı "No card" ve doğru vade gününü ("due 3 October") gösterir.
    /// Not: örnek veride kartlar vardır (boş depo açma bayrağı yok); önemli olan formun kart istememesidir.
    @MainActor
    func testAddInstallmentWithoutCardShowsPaymentOnHomeWithDueDay() throws {
        // Simülatör dili Türkçe olabilir; satır etiketi denetimi için arayüz İngilizceye sabitlenir.
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        let title = "Cardless Phone"

        let add = app.buttons["home.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Home add button not found")
        add.tap()
        app.buttons["home.add.installment"].tap()

        let titleField = app.textFields["addInstallment.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "title field not found")
        titleField.tap()
        titleField.typeText(title)

        let amount = app.textFields["addInstallment.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5), "amount field not found")
        amount.tap()
        amount.typeText("1200")

        // Kart seçilmedi: ödeme günü alanı var ve kaydet açık.
        let paymentDay = element("addInstallment.paymentDay", in: app)
        XCTAssertTrue(paymentDay.waitForExistence(timeout: 5), "payment day field not found without a card")
        // Stepper kimliği kapsayıcıdadır; artır/azalt düğmeleri "<kimlik>-Increment" kimliğini alır
        // (etiketleri dile bağlıdır, kimlik değildir).
        let increment = element("addInstallment.paymentDay-Increment", in: app)
        XCTAssertTrue(increment.waitForExistence(timeout: 5), "payment day stepper has no increment button")
        // Varsayılan gün 1; iki artışla 3. gün.
        increment.tap()
        increment.tap()

        let save = app.buttons["addInstallment.save"]
        XCTAssertTrue(save.isEnabled, "save must be enabled without a card once title and amount are filled")
        save.tap()

        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "form must be dismissed after saving")
        // Form Home'un seçili ayıyla (Ekim 2026) açılır; ödeme Ekim'in 3'ündedir.
        XCTAssertTrue(scrollToRow(titled: title, in: app), "saved card-less installment '\(title)' not shown on Home")
        let saved = row(titled: title, in: app)
        XCTAssertTrue(saved.label.contains("due 3 October"), "row must show the chosen due day, got: \(saved.label)")
        XCTAssertTrue(saved.label.contains("No card"), "row must show no card, got: \(saved.label)")
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
    func testAssistantChipShowsScriptedReply() throws {
        // Betiklenmiş asistan: gerçek model gerekmez.
        let app = XCUIApplication()
        app.launchArguments += ["-ui-static-motion", "-ui-sample-data", "-ui-scripted-assistant"]
        app.launch()

        let button = app.buttons["home.assistant"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "assistant button not found on Home")
        button.tap()
        XCTAssertTrue(element("assistant.screen", in: app).waitForExistence(timeout: 10), "Assistant screen must show")
        XCTAssertTrue(element("assistant.empty", in: app).exists, "empty state must show before any question")
        XCTAssertFalse(element("assistant.unavailable", in: app).exists)

        let chip = app.buttons["assistant.suggestion.0"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "first suggestion chip not found")
        chip.tap()

        // Soru ve cevap sırayla görünür.
        XCTAssertTrue(element("assistant.message.0", in: app).waitForExistence(timeout: 5), "question bubble must show")
        let reply = element("assistant.message.1", in: app)
        XCTAssertTrue(reply.waitForExistence(timeout: 10), "reply bubble must show")
        XCTAssertTrue(reply.label.contains("You pay"), "reply must be the scripted answer, got: \(reply.label)")
        XCTAssertFalse(element("assistant.empty", in: app).exists, "empty state must go away")

        // Geri düğmesi Home'a döner.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "Home must be visible after going back")
    }

    @MainActor
    func testAssistantUnavailableShowsExplanation() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-static-motion", "-ui-sample-data", "-ui-assistant-unavailable"]
        app.launch()

        let button = app.buttons["home.assistant"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "assistant button must stay for unavailable models")
        button.tap()
        XCTAssertTrue(element("assistant.unavailable", in: app).waitForExistence(timeout: 10), "explanation must show")
        XCTAssertFalse(app.textFields["assistant.input"].exists, "no chat input when unavailable")
    }

    @MainActor
    func testAnalyticsSelectingBarChangesDonut() throws {
        let app = launchHome()
        let button = app.buttons["home.analytics"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "analytics button not found on Home")
        button.tap()
        XCTAssertTrue(element("analytics.screen", in: app).waitForExistence(timeout: 10), "Analytics screen must show")

        // Örnek veride Ekim 2026'da Everyday kartının Laptop taksidi var: halka ve açıklama kartı gösterir.
        XCTAssertTrue(element("analytics.donut", in: app).waitForExistence(timeout: 5), "donut must show")
        XCTAssertTrue(element("analytics.legend", in: app).exists, "legend must show")
        let everyday = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Everyday card,"))
        XCTAssertTrue(everyday.firstMatch.waitForExistence(timeout: 5), "Everyday card must be in the October breakdown")
        XCTAssertFalse(element("analytics.donut.empty", in: app).exists)

        // Sağdaki çubuklardan birini seç (Ağustos/Eylül 2027): Laptop taksidi Temmuz 2027'de biter,
        // bu yüzden Everyday kartı dağılımdan çıkar ve halka değişir.
        // Aynı kimliği paylaşan birden çok öğe olabilir; ilkini (kapsayıcıyı) kullan.
        let chart = element("analytics.chart", in: app).firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5), "chart must show")
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).press(forDuration: 0.3) // Kısa dokunuş grafik seçimini tetiklemiyor; basılı tutmak tetikliyor.

        let gone = NSPredicate(format: "exists == false")
        let change = XCTNSPredicateExpectation(predicate: gone, object: everyday.firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [change], timeout: 5), .completed, "donut must change after selecting a bar")
        XCTAssertTrue(element("analytics.donut", in: app).exists, "donut still shows the remaining cards")
    }

    @MainActor
    func testHomeHasNoVersionAndSettingsShowsVersion() throws {
        let app = launchHome()

        let gear = app.buttons["home.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "settings button not found on Home")
        // Başlık gezinme çubuğunda; Home'da sürüm metni yok (#154).
        XCTAssertTrue(app.staticTexts["Vadem"].exists, "Vadem title must show on Home")
        let versionQuery = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Version ", "Sürüm "))
        XCTAssertEqual(versionQuery.count, 0, "Home must not show a version text")

        gear.tap()
        let version = app.staticTexts["settings.version"]
        XCTAssertTrue(version.waitForExistence(timeout: 5), "Settings must show the app version")
        XCTAssertNotNil(
            version.label.wholeMatch(of: /(Version|Sürüm) [0-9]+(\.[0-9]+)*/),
            "version label '\(version.label)' has an unexpected format"
        )
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

        // Dikey eksenli alanda ortaya dokunmak imleci metnin ortasına koyar;
        // sağ kenara dokunarak imleci sona alırız.
        titleField.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
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

    // MARK: - Abonelik akışı (#166)

    /// Kart seçmeden abonelik eklenir: kart "No card" kalır, yenileme günü stepper ile 3 yapılır;
    /// kayıttan sonra Home satırı "No card" ve doğru vade gününü ("due 3 October") gösterir.
    @MainActor
    func testAddSubscriptionWithoutCardShowsPaymentOnHomeWithDueDay() throws {
        // Satır etiketi denetimi için arayüz İngilizceye sabitlenir (#155 testiyle aynı).
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        let title = "Cardless Streaming"

        let add = app.buttons["home.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Home add button not found")
        add.tap()
        app.buttons["home.add.subscription"].tap()

        let titleField = app.textFields["addSubscription.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "title field not found")
        titleField.tap()
        titleField.typeText(title)

        let amount = app.textFields["addSubscription.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5), "amount field not found")
        amount.tap()
        amount.typeText("99")

        // Kart seçilmez. Stepper kimliği kapsayıcıdadır; düğmeler "<kimlik>-Increment" alır.
        let increment = element("addSubscription.renewalDay-Increment", in: app)
        XCTAssertTrue(increment.waitForExistence(timeout: 5), "renewal day stepper has no increment button")
        // Varsayılan gün 1; iki artışla 3. gün.
        increment.tap()
        increment.tap()

        let save = app.buttons["addSubscription.save"]
        XCTAssertTrue(save.isEnabled, "save must be enabled without a card once title and amount are filled")
        save.tap()

        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "form must be dismissed after saving")
        // Form Home'un seçili ayıyla (Ekim 2026) açılır; çekim Ekim'in 3'ündedir.
        XCTAssertTrue(scrollToRow(titled: title, in: app), "saved card-less subscription '\(title)' not shown on Home")
        let saved = row(titled: title, in: app)
        XCTAssertTrue(saved.label.contains("due 3 October"), "row must show the chosen due day, got: \(saved.label)")
        XCTAssertTrue(saved.label.contains("No card"), "row must show no card, got: \(saved.label)")
    }

    @MainActor
    func testEditSubscriptionFromHomeSavesNewTitle() throws {
        let app = launchHome()
        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 10), "Home not shown")
        XCTAssertTrue(scrollToRow(titled: "Netflix", in: app), "sample subscription 'Netflix' not shown on Home")
        row(titled: "Netflix", in: app).tap()

        // Form kayıtlı değerlerle açılır.
        let titleField = app.textFields["addSubscription.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "edit form not shown")
        XCTAssertEqual(titleField.value as? String, "Netflix", "title must be prefilled")
        XCTAssertTrue(app.buttons["addSubscription.save"].isEnabled, "save must be enabled with the saved values")

        // İmleci sona almak için sağ kenara dokunulur (dikey eksenli alan).
        titleField.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        titleField.typeText(" Plus")
        app.buttons["addSubscription.save"].tap()

        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "form must be dismissed after saving")
        XCTAssertTrue(scrollToRow(titled: "Netflix Plus", in: app), "edited title not shown on Home")
    }

    @MainActor
    func testDeleteSubscriptionFromHomeRemovesPayment() throws {
        let app = launchHome()
        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 10), "Home not shown")
        XCTAssertTrue(scrollToRow(titled: "Gym", in: app), "sample subscription 'Gym' not shown on Home")
        row(titled: "Gym", in: app).tap()

        let delete = revealDelete(prefix: "addSubscription", in: app)
        XCTAssertTrue(delete.exists, "delete button not found")
        delete.tap()

        // Önce onay istenir; vazgeçince form açık kalır.
        let cancel = app.buttons["addSubscription.delete.cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "confirmation not shown")
        cancel.tap()
        XCTAssertTrue(app.textFields["addSubscription.title"].exists, "form must stay open after cancelling")

        revealDelete(prefix: "addSubscription", in: app).tap()
        let confirm = app.buttons["addSubscription.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "confirmation not shown")
        confirm.tap()

        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "form must be dismissed after deleting")
        XCTAssertFalse(scrollToRow(titled: "Gym", in: app), "deleted subscription must not appear on Home")
    }

    @MainActor
    func testCancelAddSubscriptionLeavesHomeUnchanged() throws {
        let app = launchHome()

        let add = app.buttons["home.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Home add button not found")
        add.tap()
        app.buttons["home.add.subscription"].tap()

        let titleField = app.textFields["addSubscription.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "title field not found")
        titleField.tap()
        titleField.typeText("Cancelled sub")

        app.buttons["addSubscription.cancel"].tap()

        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "Home must be visible after cancel")
        XCTAssertFalse(scrollToRow(titled: "Cancelled sub", in: app), "cancelled subscription must not appear on Home")
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

    /// Kartlar ekranı (`-ui-card-list-empty` ile doğrudan açılır): kart ekle, listede gör, aç, sil, liste yeniden boş.
    /// Örnek verideki kartların hepsi kullanımda olduğundan önce yeni bir kart eklenir.
    @MainActor
    func testCardsScreenAddOpenAndDeleteCard() throws {
        let app = launchHome(extraArguments: ["-ui-card-list-empty"])
        // Boş depo ile Kartlar ekranı açılış argümanıyla doğrudan açılır; Ayarlar'dan gezinme yapılmaz.
        // (Ayarlar → Kartlar gezinmesi testSettingsCardsRowOpensCardsAndDeletesNewCard'da sınanır.)
        XCTAssertTrue(element("cards.list", in: app).waitForExistence(timeout: 10), "Cards screen not shown")
        XCTAssertTrue(element("cards.empty", in: app).exists, "empty state must show with no cards")

        try addAndDeleteCard(in: app, addIdentifier: "cards.empty.add")
    }

    @MainActor
    func testSettingsPrivacyRowOpensPolicyAndGoesBack() throws {
        let app = launchHome()
        let gear = app.buttons["home.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "settings button not found on Home")
        gear.tap()
        let privacyRow = element("settings.privacy", in: app)
        XCTAssertTrue(privacyRow.waitForExistence(timeout: 5), "Privacy row not shown in Settings")
        privacyRow.tap()
        XCTAssertTrue(element("privacy.policy", in: app).waitForExistence(timeout: 5), "Privacy policy not shown")
        XCTAssertTrue(element("privacy.policy.intro", in: app).exists, "policy intro text not shown")

        // Gezinme çubuğundaki geri düğmesiyle Ayarlar'a dönülür.
        // Ayarlar sayfa (sheet) olarak açık; arkadaki Home'un çubuğu da var. Sheet'teki çubuk daha aşağıdadır
        // (en büyük minY), geri düğmesi onun ilk düğmesidir. Başlık metni dile bağlı olduğundan kullanılmaz.
        let policyBar = app.navigationBars.allElementsBoundByIndex
            .filter { $0.exists }
            .max { $0.frame.minY < $1.frame.minY }
        let back = try XCTUnwrap(policyBar, "navigation bar of the policy not found").buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "back button not found in the policy navigation bar")
        back.tap()
        XCTAssertTrue(element("settings.privacy", in: app).waitForExistence(timeout: 5), "must return to Settings")
        XCTAssertFalse(element("privacy.policy", in: app).exists, "policy must close after going back")
    }

    @MainActor
    func testSettingsCardsRowOpensCardsAndDeletesNewCard() throws {
        let app = launchHome()
        let gear = app.buttons["home.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "settings button not found on Home")
        gear.tap()
        let cardsRow = element("settings.cards", in: app)
        XCTAssertTrue(cardsRow.waitForExistence(timeout: 5), "Cards row not shown in Settings")
        cardsRow.tap()
        XCTAssertTrue(element("cards.list", in: app).waitForExistence(timeout: 5), "Cards screen not shown")
        // Örnek veride üç kart var, hepsi kullanımda.
        XCTAssertTrue(element("cards.row.0", in: app).waitForExistence(timeout: 5), "sample cards not listed")
        XCTAssertFalse(element("cards.empty", in: app).exists, "empty state must not show with cards")

        // Yeni kart "Zzz Fresh" ada göre son sıraya girer; satır etiketiyle bulunur.
        app.buttons["cards.add"].tap()
        try fillAndSaveCard(named: "Zzz Fresh", in: app)
        let fresh = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Zzz Fresh'")).firstMatch
        XCTAssertTrue(fresh.waitForExistence(timeout: 5), "new card not listed")
        XCTAssertTrue(element("cards.row.3", in: app).exists, "list must have four cards now")
        fresh.tap()

        let name = app.textFields["addCard.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "edit form not shown")
        XCTAssertEqual(name.value as? String, "Zzz Fresh", "name must be prefilled")
        try deleteCardInOpenForm(in: app)

        XCTAssertTrue(element("cards.list", in: app).waitForExistence(timeout: 5), "must return to the list")
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'Zzz Fresh'")).firstMatch.exists,
            "deleted card must leave the list"
        )
        XCTAssertFalse(element("cards.row.3", in: app).exists, "list must be back to three cards")
    }

    @MainActor
    private func fillAndSaveCard(named title: String, in app: XCUIApplication) throws {
        let name = app.textFields["addCard.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "add card form not shown")
        name.tap()
        name.typeText(title)
        let statement = app.textFields["addCard.statementDay"]
        statement.tap()
        statement.typeText("10")
        let due = app.textFields["addCard.dueDay"]
        due.tap()
        due.typeText("20")
        let save = app.buttons["addCard.save"]
        XCTAssertTrue(save.isEnabled, "save must be enabled with a valid card")
        save.tap()
    }

    @MainActor
    private func deleteCardInOpenForm(in app: XCUIApplication) throws {
        let delete = revealDelete(prefix: "addCard", in: app)
        XCTAssertTrue(delete.exists, "delete button not found")
        delete.tap()
        let confirm = app.buttons["addCard.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "confirmation not shown")
        confirm.tap()
    }

    /// Boş durumdan: ekle, listede gör, aç, sil, boş durum geri gelir.
    @MainActor
    private func addAndDeleteCard(in app: XCUIApplication, addIdentifier: String) throws {
        app.buttons[addIdentifier].tap()
        try fillAndSaveCard(named: "Fresh", in: app)
        let row = element("cards.row.0", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "new card not listed")
        XCTAssertFalse(element("cards.empty", in: app).exists, "empty state must disappear")
        row.tap()
        XCTAssertTrue(app.textFields["addCard.name"].waitForExistence(timeout: 5), "edit form not shown")
        try deleteCardInOpenForm(in: app)
        XCTAssertTrue(element("cards.empty", in: app).waitForExistence(timeout: 5), "list must be empty again")
        XCTAssertFalse(element("cards.row.0", in: app).exists, "no rows may remain")
    }
}
