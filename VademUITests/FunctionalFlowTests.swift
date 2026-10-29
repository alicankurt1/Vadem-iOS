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

    /// Add sayfasındaki büyük düğmelerden birini seçer (`add.sheet.<kind>`).
    @MainActor
    private func chooseInSheet(_ kind: String, in app: XCUIApplication) {
        let button = element("add.sheet.\(kind)", in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 5), "add sheet option \(kind) not found")
        button.tap()
    }

    @MainActor
    func testAddSheetShowsThreeOptionsStartsFlowAndCloseReturnsHome() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        let add = app.buttons["home.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Home add button not found")
        add.tap()

        // Sayfa üç seçeneği gösterir.
        for kind in ["installment", "subscription", "payment"] {
            XCTAssertTrue(element("add.sheet.\(kind)", in: app).waitForExistence(timeout: 5), "option \(kind) not shown")
        }

        // Taksit (#189): akış sayfanın içinde başlar (tutar tuş takımı); kapat Home'a döner.
        chooseInSheet("installment", in: app)
        XCTAssertTrue(element("keypad.display", in: app).waitForExistence(timeout: 5), "installment flow did not start")
        XCTAssertFalse(app.textFields["addInstallment.title"].exists, "installment must not open the old form")
        app.buttons["flow.close"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5), "Home must be visible after closing the flow")

        // Abonelik (#190): akış sayfanın içinde tutar adımıyla başlar; ilk adımda geri seçime döner.
        add.tap()
        chooseInSheet("subscription", in: app)
        XCTAssertTrue(app.buttons["keypad.digit.1"].waitForExistence(timeout: 5), "subscription flow did not start on the amount step")
        app.buttons["flow.back"].tap()
        XCTAssertTrue(element("add.sheet.installment", in: app).waitForExistence(timeout: 5), "back on the first step must return to the options")
        element("add.sheet.close", in: app).tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5), "Home must be visible after closing the sheet")

        // Ödeme: akış sayfanın içinde başlar; geri düğmesi seçime döner, kapat Home'a döner.
        add.tap()
        chooseInSheet("payment", in: app)
        XCTAssertTrue(app.buttons["keypad.digit.1"].waitForExistence(timeout: 5), "payment flow did not start on the amount step")
        XCTAssertTrue(element("flow.progress", in: app).exists, "progress must be shown")
        app.buttons["flow.back"].tap()
        XCTAssertTrue(element("add.sheet.installment", in: app).waitForExistence(timeout: 5), "back must return to the options")
        chooseInSheet("payment", in: app)
        XCTAssertTrue(app.buttons["flow.close"].waitForExistence(timeout: 5), "close button not found")
        app.buttons["flow.close"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5), "Home must be visible after closing")
        XCTAssertFalse(element("add.sheet.installment", in: app).exists, "sheet must be dismissed")

        // Seçenekler ekranındaki kapat düğmesi de Home'a döner.
        add.tap()
        let close = app.buttons["add.sheet.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "sheet close button not found")
        close.tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5), "Home must be visible after closing the sheet")
        XCTAssertFalse(element("add.sheet.title", in: app).exists, "sheet must be dismissed")
    }

    @MainActor
    func testAddFlowKeypadTypesAmountAndContinueNeedsPositiveAmount() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ui-add-flow-keypad"])
        let continueButton = app.buttons["flow.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10), "continue button not found")
        XCTAssertFalse(continueButton.isEnabled, "continue must be disabled with no amount")
        app.buttons["keypad.digit.1"].tap()
        app.buttons["keypad.digit.5"].tap()
        app.buttons["keypad.separator"].tap()
        app.buttons["keypad.digit.5"].tap()
        XCTAssertTrue(continueButton.isEnabled, "continue must be enabled with an amount above zero")
        app.buttons["keypad.delete"].tap()
        app.buttons["keypad.delete"].tap()
        app.buttons["keypad.delete"].tap()
        app.buttons["keypad.delete"].tap()
        XCTAssertFalse(continueButton.isEnabled, "continue must be disabled again when the amount is cleared")
    }

    @MainActor
    func testAddFlowChipAutoAdvancesToCardPicker() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ui-add-flow-chips"])
        let chip = element("flow.period.chip.0", in: app)
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "chip not found")
        chip.tap()
        // Çip seçimi kendiliğinden bir sonraki adıma (kart seçimi) geçirir.
        XCTAssertTrue(element("cardPicker.noCard", in: app).waitForExistence(timeout: 5), "card picker step did not show after choosing a chip")
        XCTAssertTrue(element("cardPicker.newCard", in: app).exists, "'New card' row must be visible")
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

    /// Home'dan Add sayfası → Taksit → hızlı akış: yalnızca tutar yazılır; ödeme Home'da görünür (#189).
    @MainActor
    private func addInstallmentAndFindItOnHome(extraArguments: [String]) throws {
        let app = launchHome(extraArguments: extraArguments)
        let add = app.buttons["home.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Home add button not found")
        add.tap()
        chooseInSheet("installment", in: app)
        try completeInstallmentFlow(in: app, amount: "1200")
        XCTAssertTrue(add.waitForExistence(timeout: 5), "sheet must be dismissed after saving")
        XCTAssertTrue(scrollToInstallmentRow(in: app), "saved installment with the default title not shown on Home")
    }

    /// Varsayılan başlıklı ("Installment" / "Taksit") ve kartsız ("No card" / "Kart yok") satır.
    @MainActor
    private func installmentRow(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "(label CONTAINS 'Installment' AND label CONTAINS 'No card') OR (label CONTAINS 'Taksit' AND label CONTAINS 'Kart yok')"
            ))
            .firstMatch
    }

    @MainActor
    private func scrollToInstallmentRow(in app: XCUIApplication, attempts: Int = 6) -> Bool {
        let target = installmentRow(in: app)
        for _ in 0..<attempts {
            if target.exists { return true }
            app.swipeUp()
        }
        return target.exists
    }

    /// #203: gün satırına dokunur, sayfadaki tekerlekte `day`'i seçer, Bitti'ye basar ve satırın günü gösterdiğini doğrular.
    @MainActor
    private func pickDay(_ day: Int, identifier: String, in app: XCUIApplication) throws {
        let row = element(identifier, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "day row \(identifier) not shown")
        row.tap()
        XCTAssertTrue(element("\(identifier).sheet", in: app).waitForExistence(timeout: 5), "day picker sheet not shown")
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 5), "day wheel not shown")
        wheel.adjust(toPickerWheelValue: String(day))
        let done = element("\(identifier).done", in: app)
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Done button not shown")
        done.tap()
        XCTAssertTrue(
            element("\(identifier).sheet", in: app).waitForNonExistence(timeout: 5),
            "day picker sheet must close after Done"
        )
        XCTAssertTrue(element(identifier, in: app).label.contains(String(day)), "row must show the chosen day \(day)")
    }

    /// Akışın tüm adımlarını geçer: yalnızca tutar yazılır; sayı 6, kart "kart yok" (son kullanılan yok),
    /// ilk ay "bu ay", başlık atlanır. `paymentDay` verilirse özetteki "Değiştir" ile gün seçici sayfasından o gün seçilir.
    /// Kaydet'e basar; sayfa kapanmadan önceki özet kimliklerini doğrular.
    @MainActor
    private func completeInstallmentFlow(in app: XCUIApplication, amount: String, paymentDay: Int? = nil) throws {
        XCTAssertTrue(element("keypad.display", in: app).waitForExistence(timeout: 10), "amount step not shown")
        let continueButton = app.buttons["flow.continue"]
        XCTAssertFalse(continueButton.isEnabled, "continue must be disabled with no amount")
        for character in amount {
            app.buttons["keypad.digit.\(character)"].tap()
        }
        XCTAssertTrue(continueButton.isEnabled, "continue must be enabled once an amount is typed")
        continueButton.tap()

        // Sayı: 6. çip (3, 6, 9, 12, 18, Diğer); seçim kendiliğinden ilerler.
        let sixMonths = element("addInstallmentFlow.count.chip.1", in: app)
        XCTAssertTrue(sixMonths.waitForExistence(timeout: 5), "count step not shown")
        sixMonths.tap()

        // Kart: örnek veride son kullanılan yok, "Kart yok" seçili gelir.
        let noCard = element("cardPicker.noCard", in: app)
        XCTAssertTrue(noCard.waitForExistence(timeout: 5), "card step not shown")
        noCard.tap()

        // İlk ay: "Bu ay".
        let thisMonth = element("addInstallmentFlow.month.chip.0", in: app)
        XCTAssertTrue(thisMonth.waitForExistence(timeout: 5), "first month step not shown")
        thisMonth.tap()

        // Başlık isteğe bağlı: atlanır.
        let skip = element("addInstallmentFlow.skip", in: app)
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "title step not shown")
        skip.tap()

        // Özet: ödeme günü adım değil; varsayılan bugünün günü (12), isteğe bağlı değiştirilir.
        let save = app.buttons["addInstallmentFlow.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "summary not shown")
        XCTAssertTrue(save.isEnabled, "save must be enabled with only the amount typed")
        XCTAssertTrue(element("addInstallmentFlow.summary.paymentDay", in: app).label.contains("12"), "default payment day must be today's day (12)")
        if let paymentDay {
            element("addInstallmentFlow.changePaymentDay", in: app).tap()
            try pickDay(paymentDay, identifier: "addInstallmentFlow.paymentDayStepper", in: app)
        }
        save.tap()
    }

    /// #155 / #189: kartsız taksit, ödeme günü özetteki "Değiştir" ile 12'den 15'e alınır;
    /// Home satırı "No card" ve "due 15 October" gösterir.
    @MainActor
    func testAddInstallmentWithoutCardShowsPaymentOnHomeWithDueDay() throws {
        // Satır etiketi denetimi için arayüz İngilizceye sabitlenir.
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        let add = app.buttons["home.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Home add button not found")
        add.tap()
        chooseInSheet("installment", in: app)
        try completeInstallmentFlow(in: app, amount: "1200", paymentDay: 15)
        XCTAssertTrue(add.waitForExistence(timeout: 5), "sheet must be dismissed after saving")
        XCTAssertTrue(scrollToInstallmentRow(in: app), "saved card-less installment not shown on Home")
        let saved = installmentRow(in: app)
        XCTAssertTrue(saved.label.contains("due 15 October"), "row must show the chosen due day, got: \(saved.label)")
        XCTAssertTrue(saved.label.contains("No card"), "row must show no card, got: \(saved.label)")
    }

    /// #189: `-ui-add-installment-flow` açılışı doğrudan akışı başlatır; yalnızca tutar yazılır (İngilizce).
    @MainActor
    func testInstallmentQuickFlowWithOnlyAmountEnglish() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ui-add-installment-flow"])
        try completeInstallmentFlow(in: app, amount: "1200")
        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "sheet must close after saving")
        XCTAssertTrue(scrollToInstallmentRow(in: app), "saved installment 'Installment' not shown on Home")
        XCTAssertTrue(installmentRow(in: app).label.contains("due 12 October"), "default payment day must be today's day")
    }

    /// #189: aynı akış Türkçe arayüzle; kimlikler dilden bağımsız, varsayılan başlık "Taksit".
    @MainActor
    func testInstallmentQuickFlowWithOnlyAmountTurkish() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR", "-ui-add-installment-flow"])
        try completeInstallmentFlow(in: app, amount: "1200")
        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "sheet must close after saving")
        XCTAssertTrue(scrollToInstallmentRow(in: app), "saved installment 'Taksit' not shown on Home")
    }

    /// #189: akışta geri adımı önceki adıma döner; tutar korunur.
    @MainActor
    func testInstallmentQuickFlowBackKeepsAmount() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ui-add-installment-flow"])
        XCTAssertTrue(element("keypad.display", in: app).waitForExistence(timeout: 10), "amount step not shown")
        app.buttons["keypad.digit.7"].tap()
        app.buttons["flow.continue"].tap()
        XCTAssertTrue(element("addInstallmentFlow.count.chip.0", in: app).waitForExistence(timeout: 5), "count step not shown")
        app.buttons["flow.back"].tap()
        XCTAssertTrue(element("keypad.display", in: app).waitForExistence(timeout: 5), "back must return to the amount step")
        XCTAssertTrue(app.buttons["flow.continue"].isEnabled, "the typed amount must be kept")
    }

    /// #191: örnek veride "Dentist" tek seferlik ödemesi 20 Kasım 2026'dadır (Home Ekim'de açılır);
    /// sonraki aya geçince Home listesinde kartsız satır olarak görünür.
    @MainActor
    func testOneTimePaymentShowsOnHomeInItsDueMonth() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])

        let next = app.buttons["home.nextMonth"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "next month button not found on Home")
        XCTAssertFalse(row(titled: "Dentist", in: app).exists, "one-time payment must not show in October")
        next.tap()

        XCTAssertTrue(scrollToRow(titled: "Dentist", in: app), "one-time payment 'Dentist' not shown on Home in November")
        let saved = row(titled: "Dentist", in: app)
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
        chooseInSheet("installment", in: app)

        XCTAssertTrue(element("keypad.display", in: app).waitForExistence(timeout: 5), "amount step not shown")
        app.buttons["keypad.digit.5"].tap()
        app.buttons["flow.continue"].tap()
        XCTAssertTrue(element("addInstallmentFlow.count.chip.0", in: app).waitForExistence(timeout: 5), "count step not shown")

        app.buttons["flow.close"].tap()

        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "Home must be visible after closing")
        XCTAssertFalse(scrollToInstallmentRow(in: app, attempts: 3), "closed flow must not add a payment to Home")
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

    /// Kart seçmeden abonelik eklenir (#190 akışı): tutar, Aylık, "No card", hızlı başlık; özet "Change"
    /// bağlantısıyla yenileme gününü açar; kayıttan sonra Home satırı başlığı ve "No card"ı gösterir.
    @MainActor
    func testAddSubscriptionWithoutCardShowsPaymentOnHomeWithDueDay() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])

        let add = app.buttons["home.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Home add button not found")
        add.tap()
        chooseInSheet("subscription", in: app)

        let nine = app.buttons["keypad.digit.9"]
        XCTAssertTrue(nine.waitForExistence(timeout: 5), "keypad not found")
        nine.tap()
        nine.tap()
        app.buttons["flow.continue"].tap()

        // Dönem: ilk çip (Aylık) kendiliğinden ilerler.
        let period = element("subscriptionFlow.period.chip.0", in: app)
        XCTAssertTrue(period.waitForExistence(timeout: 5), "period chip not found")
        period.tap()

        let noCard = element("cardPicker.noCard", in: app)
        XCTAssertTrue(noCard.waitForExistence(timeout: 5), "'No card' row not found")
        noCard.tap()

        // Başlık: ilk hızlı çip "Streaming".
        let chip = element("subscriptionFlow.title.chip.0", in: app)
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "title chip not found")
        chip.tap()

        // Özet: "Change" yenileme günü satırını açar; gün sayfadan 20 seçilir.
        let change = app.buttons["subscriptionFlow.changeRenewalDay"]
        XCTAssertTrue(change.waitForExistence(timeout: 5), "summary 'Change' link not found")
        change.tap()
        try pickDay(20, identifier: "subscriptionFlow.renewalDay", in: app)

        let save = app.buttons["subscriptionFlow.save"]
        XCTAssertTrue(save.isEnabled, "save must be enabled with only an amount")
        save.tap()

        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "sheet must be dismissed after saving")
        XCTAssertTrue(scrollToRow(titled: "Streaming", in: app), "saved subscription 'Streaming' not shown on Home")
        XCTAssertTrue(row(titled: "Streaming", in: app).label.contains("No card"), "row must show no card, got: \(row(titled: "Streaming", in: app).label)")
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
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])

        let add = app.buttons["home.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Home add button not found")
        add.tap()
        chooseInSheet("subscription", in: app)

        // Akışta tutar yazılır, kapatılır (#190): hiçbir şey kaydedilmez.
        let five = app.buttons["keypad.digit.5"]
        XCTAssertTrue(five.waitForExistence(timeout: 5), "keypad not found")
        five.tap()
        app.buttons["flow.close"].tap()

        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "Home must be visible after close")
        XCTAssertFalse(scrollToRow(titled: "Subscription, ", in: app), "closed subscription flow must not add a payment to Home")
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

    // MARK: - Abonelik hızlı adımları (#190)

    /// Sadece tutar yazılır; dönem, kart ve başlık varsayılan/Geç ile geçilir; kayıt Home'da görünür.
    @MainActor
    func testSubscriptionQuickStepsWithOnlyAmountSavesAndShowsOnHome() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])

        let add = app.buttons["home.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Home add button not found")
        add.tap()
        chooseInSheet("subscription", in: app)

        // Tutar: 1 4 9; tutar yokken devam kapalıdır.
        let continueButton = app.buttons["flow.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5), "continue button not found")
        XCTAssertFalse(continueButton.isEnabled, "continue must be disabled without an amount")
        for digit in ["1", "4", "9"] {
            app.buttons["keypad.digit.\(digit)"].tap()
        }
        XCTAssertTrue(continueButton.isEnabled, "continue must be enabled with an amount")
        continueButton.tap()

        // Dönem: ilk çip (Aylık).
        let period = element("subscriptionFlow.period.chip.0", in: app)
        XCTAssertTrue(period.waitForExistence(timeout: 5), "period chip not found")
        period.tap()

        // Kart: "No card".
        let noCard = element("cardPicker.noCard", in: app)
        XCTAssertTrue(noCard.waitForExistence(timeout: 5), "'No card' row not found")
        noCard.tap()

        // Başlık: Skip.
        let skip = app.buttons["subscriptionFlow.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "Skip button not found")
        skip.tap()

        // Özet: varsayılan başlık görünür; tek Kaydet düğmesi.
        let save = app.buttons["subscriptionFlow.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "save button not found on the summary")
        XCTAssertTrue(element("subscriptionFlow.summary", in: app).exists, "summary not shown")
        XCTAssertTrue(save.isEnabled, "save must be enabled")
        save.tap()

        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "sheet must be dismissed after saving")
        XCTAssertFalse(element("add.sheet.installment", in: app).exists, "sheet must be gone")
        XCTAssertTrue(scrollToRow(titled: "Subscription, ", in: app), "saved subscription with the default title not shown on Home")
        XCTAssertTrue(row(titled: "Subscription, ", in: app).label.contains("No card"), "row must show no card")
    }

    // MARK: - Tek seferlik ödeme hızlı adımları (#192)

    /// Sadece tutar yazılır; tarih (Bugün), kart (No card) ve başlık (Skip) varsayılanlarla geçilir;
    /// kayıt varsayılan başlıkla Home'da (Ekim, bugünün ayı) görünür.
    @MainActor
    func testOneTimePaymentQuickStepsWithOnlyAmountSavesAndShowsOnHome() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])

        let add = app.buttons["home.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Home add button not found")
        add.tap()
        chooseInSheet("payment", in: app)

        // Tutar: 1 4 9; tutar yokken devam kapalıdır.
        let continueButton = app.buttons["flow.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5), "continue button not found")
        XCTAssertFalse(continueButton.isEnabled, "continue must be disabled without an amount")
        for digit in ["1", "4", "9"] {
            app.buttons["keypad.digit.\(digit)"].tap()
        }
        XCTAssertTrue(continueButton.isEnabled, "continue must be enabled with an amount")
        continueButton.tap()

        // Tarih: ilk çip (Today).
        let today = element("oneTimeFlow.date.chip.0", in: app)
        XCTAssertTrue(today.waitForExistence(timeout: 5), "date chip not found")
        today.tap()

        // Kart: "No card".
        let noCard = element("cardPicker.noCard", in: app)
        XCTAssertTrue(noCard.waitForExistence(timeout: 5), "'No card' row not found")
        noCard.tap()

        // Başlık: Skip.
        let skip = app.buttons["oneTimeFlow.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "Skip button not found")
        skip.tap()

        // Özet: tek Kaydet düğmesi.
        let save = app.buttons["oneTimeFlow.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "save button not found on the summary")
        XCTAssertTrue(element("oneTimeFlow.summary", in: app).exists, "summary not shown")
        XCTAssertTrue(save.isEnabled, "save must be enabled")
        save.tap()

        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "sheet must be dismissed after saving")
        XCTAssertTrue(scrollToRow(titled: "Payment, ", in: app), "saved payment with the default title not shown on Home")
        XCTAssertTrue(row(titled: "Payment, ", in: app).label.contains("No card"), "row must show no card")
    }

    @MainActor
    func testEditOneTimePaymentFromHomeSavesNewTitle() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        let next = app.buttons["home.nextMonth"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "next month button not found on Home")
        next.tap()
        XCTAssertTrue(scrollToRow(titled: "Dentist", in: app), "sample one-time payment 'Dentist' not shown in November")
        row(titled: "Dentist", in: app).tap()

        // Form kayıtlı değerlerle açılır.
        let titleField = app.textFields["editOneTime.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "edit form not shown")
        XCTAssertEqual(titleField.value as? String, "Dentist", "title must be prefilled")
        XCTAssertTrue(app.buttons["editOneTime.save"].isEnabled, "save must be enabled with the saved values")

        titleField.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        titleField.typeText(" Visit")
        app.buttons["editOneTime.save"].tap()

        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "form must be dismissed after saving")
        XCTAssertTrue(scrollToRow(titled: "Dentist Visit", in: app), "edited title not shown on Home")
    }

    @MainActor
    func testDeleteOneTimePaymentFromHomeRemovesPayment() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        let next = app.buttons["home.nextMonth"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "next month button not found on Home")
        next.tap()
        XCTAssertTrue(scrollToRow(titled: "Dentist", in: app), "sample one-time payment 'Dentist' not shown in November")
        row(titled: "Dentist", in: app).tap()

        let delete = revealDelete(prefix: "editOneTime", in: app)
        XCTAssertTrue(delete.exists, "delete button not found")
        delete.tap()

        // Önce onay istenir; vazgeçince form açık kalır.
        let cancel = app.buttons["editOneTime.delete.cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "confirmation not shown")
        cancel.tap()
        XCTAssertTrue(app.textFields["editOneTime.title"].exists, "form must stay open after cancelling")

        revealDelete(prefix: "editOneTime", in: app).tap()
        let confirm = app.buttons["editOneTime.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "confirmation not shown")
        confirm.tap()

        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "form must be dismissed after deleting")
        XCTAssertFalse(scrollToRow(titled: "Dentist", in: app), "deleted one-time payment must not appear on Home")
    }
}
