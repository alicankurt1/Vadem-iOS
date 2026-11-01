import XCTest

// Hızlı işlevsel akış testleri: kullanıcının temel işini uçtan uca yapabildiğini kanıtlar
// (formu aç, tutarı yaz, kaydet, Home'da gör). Ekran görüntüsü ve erişilebilirlik denetimi yok;
// onlar `UICheckTests`te. `scripts/ui-functional.sh` ile koşulur.
//
// `-ui-sample-data` bellek içi depo açar: gerçek veriye dokunulmaz, her test temiz başlar.
// `-ui-static-motion` sürekli animasyonları durdurur; uygulama hızla boşa düşer. Animasyonlu yolu
// sınayan testler `animated: true` ile açar (argüman gönderilmez); diğer testler değişmez.
final class FunctionalFlowTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchHome(extraArguments: [String] = [], animated: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        // Animasyonlu açılışta hareket uygulamanın kendi kuralına kalır (simülatörde Reduce Motion kapalı).
        let motionArguments = animated ? [] : ["-ui-static-motion"]
        app.launchArguments += motionArguments + ["-ui-sample-data"] + extraArguments
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
    func testAddSheetStatementImportOptionOpensImportScreenAndBackReturns() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        let add = app.buttons["home.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Home add button not found")
        add.tap()

        // Dördüncü seçenek: ekstreden içe aktarma.
        chooseInSheet("statementImport", in: app)
        XCTAssertTrue(element("statementImport.title", in: app).waitForExistence(timeout: 5), "import screen did not open")
        XCTAssertTrue(element("statementImport.choosePDF", in: app).exists, "Choose PDF not shown")
        XCTAssertTrue(element("statementImport.chooseImage", in: app).exists, "Choose image not shown")

        // Geri seçeneklere döner; seçenekler yine görünür.
        app.buttons["statementImport.back"].tap()
        XCTAssertTrue(element("add.sheet.statementImport", in: app).waitForExistence(timeout: 5), "back must return to the options")
        XCTAssertTrue(element("add.sheet.installment", in: app).exists, "kind options must still be shown")

        // Yeniden açılıp kapat Home'a döner.
        chooseInSheet("statementImport", in: app)
        XCTAssertTrue(app.buttons["statementImport.close"].waitForExistence(timeout: 5), "close button not found")
        app.buttons["statementImport.close"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5), "Home must be visible after closing")
    }

    @MainActor
    func testStatementImportFoundLaunchStateListsCandidates() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ui-statement-import-found"])
        XCTAssertTrue(element("statementImport.results", in: app).waitForExistence(timeout: 10), "results not shown")
        XCTAssertTrue(element("statementImport.candidate.0", in: app).exists, "first candidate not shown")
        XCTAssertTrue(element("statementImport.candidate.2", in: app).exists, "third candidate not shown")
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
        // Satır ChoiceRow: etiket başlık, değer "Day N" / "N. gün".
        let shown = element(identifier, in: app).value as? String ?? ""
        XCTAssertTrue(shown.contains(String(day)), "row must show the chosen day \(day), got: \(shown)")
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

    /// #204: örnek veride 15 Ekim'de ödeme vardır (Shopping kartı vadesi). Gün seçilince o günün satırı
    /// "By card" başlığının üstünde olur. #231: ödemeler listesi seçim olsa da olmasa da her zaman "By card"
    /// başlığının üstündedir.
    @MainActor
    func testPaymentsListStaysAboveByCardWithAndWithoutSelectedDay() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])

        let day = element("home.calendar.day.15", in: app)
        var attempts = 0
        while !(day.exists && day.isHittable) && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(day.exists && day.isHittable, "calendar day 15 not reachable on Home")

        let cards = element("home.cards", in: app)
        let firstRow = element("home.row.0", in: app)

        // Seçim yokken: ödemeler listesi kartlardan önce.
        XCTAssertTrue(cards.waitForExistence(timeout: 5), "'By card' header not found")
        XCTAssertTrue(element("home.list", in: app).exists, "payments header not found")
        XCTAssertLessThan(
            element("home.list", in: app).frame.minY, cards.frame.minY,
            "without a selected day the payments list must be above 'By card'"
        )

        day.tap()
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "selected day's payment row not found")
        XCTAssertTrue(cards.exists, "'By card' header must stay with a selected day")
        XCTAssertLessThan(
            firstRow.frame.minY, cards.frame.minY,
            "selected day's payment row must be above the 'By card' header"
        )
        XCTAssertLessThan(
            element("home.list", in: app).frame.minY, cards.frame.minY,
            "selected day's list header must be above the 'By card' header"
        )

        // Aynı güne tekrar dokunmak seçimi kaldırır.
        var tapAttempts = 0
        while !(day.exists && day.isHittable) && tapAttempts < 8 {
            app.swipeDown()
            tapAttempts += 1
        }
        day.tap()
        XCTAssertTrue(element("home.list", in: app).waitForExistence(timeout: 5), "payments header not found after deselect")
        XCTAssertLessThan(
            element("home.list", in: app).frame.minY, cards.frame.minY,
            "after deselecting the day the payments list must still be above 'By card'"
        )
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

    /// #230: Home'da ekran başlığı yok; ay şeridi panelin üstünde, panel başlığı "You pay this month" ve tutarı okunur biçimde söyler.
    @MainActor
    func testHomeHasNoDisplayHeaderAndHeroCarriesTitle() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        let total = element("home.total", in: app)
        XCTAssertTrue(total.waitForExistence(timeout: 10), "home.total not shown")
        XCTAssertFalse(element("home.header", in: app).exists, "Home must not show the display header any more")
        XCTAssertTrue(total.label.contains("You pay this month"), "hero label must carry the title, got: \(total.label)")
        XCTAssertFalse(total.label.contains("₺"), "hero label must read the amount in spoken form, got: \(total.label)")
        XCTAssertTrue(total.label.contains("Due so far"), "hero label must keep the progress, got: \(total.label)")
        // Ay şeridi panelin üstünde; ekleme ve takvim düğmeleri durur.
        let previous = app.buttons["home.previousMonth"]
        XCTAssertTrue(previous.exists, "month bar missing")
        XCTAssertLessThan(previous.frame.minY, total.frame.minY, "month bar must be above the hero card")
        XCTAssertTrue(element("home.add", in: app).exists, "Add button missing")
        XCTAssertTrue(element("home.showCalendar", in: app).exists, "Calendar button missing")
    }

    /// #211: dört sekmenin başlığı görünür; VoiceOver başlığı vurgu sözcüğünde bölmeden tek öğe okur.
    @MainActor
    func testTabHeadersShowAsSingleElements() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])

        // (sekme, başlık kimliği, başlığın tam metninde geçmesi gereken parçalar)
        let headers: [(tab: String, id: String, fragments: [String])] = [
            ("tab.home", "home.total", ["You pay"]),
            ("tab.analytics", "analytics.header", ["Your next", "12 months"]),
            ("tab.cards", "cards.header", ["Your", "cards", "at a glance"]),
            ("tab.settings", "settings.header", ["Make it", "yours"]),
        ]
        for header in headers {
            let tab = app.buttons[header.tab]
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "\(header.tab) not found")
            tab.tap()
            // Home'da ekran başlığı yok; panel özeti (home.total) birleşik öğe olduğundan her türde aranır.
            let title = app.descendants(matching: .any).matching(identifier: header.id)
            XCTAssertTrue(title.firstMatch.waitForExistence(timeout: 10), "\(header.id) not shown")
            // Tek öğe: vurgu sözcüğü ayrı bir öğe olmamalı.
            XCTAssertEqual(title.count, 1, "\(header.id) must be exactly one element (not split by the accent word)")
            let label = title.firstMatch.label
            for fragment in header.fragments {
                XCTAssertTrue(label.contains(fragment), "\(header.id) label '\(label)' must contain '\(fragment)'")
            }
        }
    }

    @MainActor
    func testAnalyticsTabShowsChartAndHomeTabComesBack() throws {
        let app = launchHome()

        // Alttaki çubuktaki Analytics sekmesi grafik ekranını gösterir.
        let button = app.buttons["tab.analytics"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "analytics tab not found")
        button.tap()
        XCTAssertTrue(element("analytics.screen", in: app).waitForExistence(timeout: 10), "Analytics screen must show")
        XCTAssertTrue(element("analytics.summary", in: app).waitForExistence(timeout: 5), "summary card must show")
        XCTAssertTrue(element("analytics.chart", in: app).exists, "chart must show")
        XCTAssertFalse(element("analytics.empty", in: app).exists, "sample data is not empty")

        // "Bu ay" sekmesi Home'a döner; Analytics gizlenir.
        app.buttons["tab.home"].tap()
        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "Home must be visible after switching back")
        XCTAssertFalse(element("analytics.screen", in: app).waitForExistence(timeout: 2), "Analytics must be hidden on the Home tab")
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
        app.navigationBars.buttons["BackButton"].tap()
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
        let button = app.buttons["tab.analytics"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "analytics tab not found")
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

        let gear = app.buttons["tab.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "settings tab not found")
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

        let gear = app.buttons["tab.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "settings tab not found")
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

        // "Bu ay" sekmesi Home'u gösterir; Ayarlar gizlenir.
        app.buttons["tab.home"].tap()
        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 5), "Home must be visible after switching tab")
        XCTAssertFalse(app.switches["settings.reminders"].waitForExistence(timeout: 2), "Settings must be hidden on the Home tab")
    }

    @MainActor
    func testSettingsTogglesMonthlySummary() throws {
        // Aylık özet anahtarı: varsayılan açık, hatırlatmalardan bağımsız; açıp kapatmak izin sorusu açmaz.
        let app = launchHome()

        let gear = app.buttons["tab.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "settings tab not found")
        gear.tap()

        let summary = app.switches["settings.monthlySummary"]
        // Uzun ekranda anahtar kaydırma gerektirebilir.
        var attempts = 0
        while !(summary.exists && summary.isHittable) && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(summary.exists, "monthly summary toggle not found")
        XCTAssertEqual(summary.value as? String, "1", "monthly summary must start on")

        summary.tap()
        XCTAssertEqual(summary.value as? String, "0", "monthly summary must turn off")
        // Hatırlatma anahtarı etkilenmez; zamanlama satırı görünür kalır.
        XCTAssertTrue(element("settings.timing", in: app).exists, "reminders must stay on when the summary is off")
        summary.tap()
        XCTAssertEqual(summary.value as? String, "1", "monthly summary must turn on again")

        // Sistem izin penceresi (springboard) açılmamış olmalı.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertFalse(
            springboard.alerts.firstMatch.waitForExistence(timeout: 1),
            "toggling the summary must not show a system permission prompt"
        )
        XCTAssertTrue(app.switches["settings.monthlySummary"].exists, "Settings must still be shown")
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
        // Boş depo ile Kartlar sekmesi açılış argümanıyla doğrudan seçilir.
        // (Sekme çubuğundan geçiş testCardsTabListsCardsAndDeletesNewCard'da sınanır.)
        XCTAssertTrue(element("cards.list", in: app).waitForExistence(timeout: 10), "Cards screen not shown")
        XCTAssertTrue(element("cards.empty", in: app).exists, "empty state must show with no cards")

        try addAndDeleteCard(in: app, addIdentifier: "cards.empty.add")
    }

    @MainActor
    func testSettingsPrivacyRowOpensPolicyAndGoesBack() throws {
        let app = launchHome()
        let gear = app.buttons["tab.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "settings tab not found")
        gear.tap()
        let privacyRow = element("settings.privacy", in: app)
        XCTAssertTrue(privacyRow.waitForExistence(timeout: 5), "Privacy row not shown in Settings")
        privacyRow.tap()
        XCTAssertTrue(element("privacy.policy", in: app).waitForExistence(timeout: 5), "Privacy policy not shown")
        XCTAssertTrue(element("privacy.policy.intro", in: app).exists, "policy intro text not shown")

        // Gizlilik metni Ayarlar sekmesinin yığınına itilir; geri düğmesi Ayarlar'a döner.
        let back = app.navigationBars.buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "back button not found in the policy navigation bar")
        back.tap()
        XCTAssertTrue(element("settings.privacy", in: app).waitForExistence(timeout: 5), "must return to Settings")
        XCTAssertFalse(element("privacy.policy", in: app).exists, "policy must close after going back")
    }

    @MainActor
    func testCardsTabListsCardsAndDeletesNewCard() throws {
        let app = launchHome()
        let cardsTab = app.buttons["tab.cards"]
        XCTAssertTrue(cardsTab.waitForExistence(timeout: 10), "cards tab not found")
        cardsTab.tap()
        XCTAssertTrue(element("cards.list", in: app).waitForExistence(timeout: 5), "Cards screen not shown")
        // Örnek veride üç kart var, hepsi kullanımda.
        XCTAssertTrue(element("cards.row.0", in: app).waitForExistence(timeout: 5), "sample cards not listed")
        XCTAssertFalse(element("cards.empty", in: app).exists, "empty state must not show with cards")

        // Yeni kart "Zzz Fresh" ada göre son sıraya girer; satır etiketiyle bulunur.
        app.buttons["cards.add"].tap()
        try fillAndSaveCard(named: "Zzz Fresh", in: app)
        let fresh = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Zzz Fresh'")).firstMatch
        XCTAssertTrue(fresh.waitForExistence(timeout: 5), "new card not listed")
        // Başlık (#211) listeyi aşağı iter: son kart ekran dışında kalabilir.
        for _ in 0..<4 where !fresh.isHittable { app.swipeUp() }
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

    /// #208: tüm sekmelere geçilir; ＋ ile ödeme eklenir ve "Bu ay"da görünür.
    @MainActor
    func testTabBarSwitchesThroughAllTabsAndAddsPaymentWithPlus() throws {
        let app = launchHome()

        // Beş kimlik de çubukta var.
        for id in ["tab.home", "tab.analytics", "tab.cards", "tab.settings", "tab.add"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 10), "\(id) not found")
        }

        // Açılışta Home; her sekme kendi ekranını gösterir.
        XCTAssertTrue(app.staticTexts["home.month"].waitForExistence(timeout: 5), "Home must be the first tab")
        app.buttons["tab.analytics"].tap()
        XCTAssertTrue(element("analytics.screen", in: app).waitForExistence(timeout: 10), "Analytics tab must show")
        app.buttons["tab.cards"].tap()
        XCTAssertTrue(element("cards.list", in: app).waitForExistence(timeout: 10), "Cards tab must show")
        app.buttons["tab.settings"].tap()
        XCTAssertTrue(app.switches["settings.reminders"].waitForExistence(timeout: 10), "Settings tab must show")
        app.buttons["tab.home"].tap()
        XCTAssertTrue(app.staticTexts["home.month"].waitForExistence(timeout: 5), "Home must show again")

        // Başka bir sekmeden ＋: ekleme sayfası açılır, ödeme kaydedilir, "Bu ay"da görünür.
        app.buttons["tab.cards"].tap()
        XCTAssertTrue(element("cards.list", in: app).waitForExistence(timeout: 10))
        app.buttons["tab.add"].tap()
        chooseInSheet("installment", in: app)
        try completeInstallmentFlow(in: app, amount: "1200")
        app.buttons["tab.home"].tap()
        XCTAssertTrue(scrollToInstallmentRow(in: app), "payment added with + not shown on This month")
    }

    /// #233: hareket açıkken (animasyonlu geçiş yolu) sekmelere art arda hızlıca dokunulur; boş kare kalmaz,
    /// son dokunulan sekmenin içeriği görünür ve dokunulabilir, öncekilerin içeriği gizlidir.
    @MainActor
    func testFastTabSwitchingWithMotionEndsOnLastTappedTab() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"], animated: true)
        XCTAssertTrue(element("home.total", in: app).waitForExistence(timeout: 10), "Home must be the first tab")

        // (sekme, içerik kimliği): her sekmenin kendine özgü başlığı.
        let tabs: [(tab: String, content: String)] = [
            ("tab.home", "home.total"),
            ("tab.analytics", "analytics.header"),
            ("tab.cards", "cards.header"),
            ("tab.settings", "settings.header"),
        ]
        let buttons = tabs.map { app.buttons[$0.tab] }
        for (button, tab) in zip(buttons, tabs) {
            XCTAssertTrue(button.waitForExistence(timeout: 10), "\(tab.tab) not found")
        }

        // İki tur: ileri (Home→…→Settings) ve geri (…→Analytics); arada bekleme yok, geçişler birbirini keser.
        let rounds: [[Int]] = [[1, 2, 3], [2, 0, 3, 1]]
        for round in rounds {
            for index in round {
                buttons[index].tap()
            }
            let last = tabs[round.last!]
            let content = element(last.content, in: app)
            XCTAssertTrue(content.waitForExistence(timeout: 5), "\(last.content) must show after fast taps ending on \(last.tab)")
            XCTAssertTrue(content.isHittable, "\(last.content) must be hittable (no blank or covered state)")
            for other in tabs where other.content != last.content {
                XCTAssertFalse(element(other.content, in: app).exists, "\(other.content) must be hidden on \(last.tab)")
            }
        }

        // Geçiş oturur, yarım kaymada takılı kalmaz: başlık ekranın içinde ve bir saniye sonra yerinde durur.
        let header = element("analytics.header", in: app)
        let settled = header.frame
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(header.frame, settled, "Analytics header must stay put once the switch has settled")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(settled), "Analytics header must be fully on screen")
    }

    /// #208: her sekmenin kendi NavigationStack'i var; sekme değişince itilmiş ekran korunur ve çubuk görünür kalır.
    @MainActor
    func testTabKeepsPushedScreenWhenSwitchingTabs() throws {
        let app = launchHome()
        let tabIDs = ["tab.home", "tab.analytics", "tab.cards", "tab.settings", "tab.add"]

        app.buttons["tab.settings"].tap()
        let privacyRow = element("settings.privacy", in: app)
        XCTAssertTrue(privacyRow.waitForExistence(timeout: 10), "Privacy row not shown in Settings")
        privacyRow.tap()
        XCTAssertTrue(element("privacy.policy", in: app).waitForExistence(timeout: 5), "Privacy policy not shown")
        for id in tabIDs {
            XCTAssertTrue(app.buttons[id].exists, "\(id) must stay visible on the pushed screen")
        }

        // Başka sekmeye geçip dönünce itilmiş ekran yerinde durur.
        app.buttons["tab.analytics"].tap()
        XCTAssertTrue(element("analytics.screen", in: app).waitForExistence(timeout: 10), "Analytics tab must show")
        app.buttons["tab.settings"].tap()
        XCTAssertTrue(element("privacy.policy", in: app).waitForExistence(timeout: 5), "pushed policy must be kept")
        XCTAssertFalse(element("settings.privacy", in: app).exists, "Settings root must not show over the pushed policy")

        // Geri düğmesi Ayarlar köküne döner.
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(element("settings.privacy", in: app).waitForExistence(timeout: 5), "must return to Settings")
        XCTAssertFalse(element("privacy.policy", in: app).exists, "policy must close after going back")
    }
    /// #213: Home'daki zil rozeti okunmamışları gösterir; gelen kutusu açılınca girdi görünür ve rozet temizlenir.
    @MainActor
    func testInboxBadgeOpensInboxAndClearsBadge() throws {
        let app = launchHome(extraArguments: ["-ui-inbox", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        let bell = app.buttons["home.inbox"]
        XCTAssertTrue(bell.waitForExistence(timeout: 10), "Home inbox button not found")
        XCTAssertEqual(bell.value as? String, "2 unread", "badge must show the two unread sample entries")

        bell.tap()
        XCTAssertTrue(element("inbox.list", in: app).waitForExistence(timeout: 5), "inbox list not shown")
        XCTAssertTrue(element("inbox.entry.0", in: app).waitForExistence(timeout: 5), "first inbox entry not shown")
        XCTAssertTrue(element("inbox.entry.2", in: app).exists, "all three sample entries must be listed")
        XCTAssertFalse(element("inbox.empty", in: app).exists, "empty state must not show with entries")

        // Geri dönünce rozet temizlenmiştir (girdiler okundu sayıldı).
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(bell.waitForExistence(timeout: 5), "Home must be visible after leaving the inbox")
        XCTAssertEqual(bell.value as? String, "0 unread", "badge must be cleared after opening the inbox")
    }

    // MARK: - Akıcı sekme geçişi (#233)

    /// #233: tüm sekmelere art arda hızlıca dokunulur; son dokunulan sekme içeriğiyle görünür kalır.
    @MainActor
    func testRapidTabSwitchingEndsOnLastTabWithContentVisible() throws {
        let app = launchHome()
        for id in ["tab.home", "tab.analytics", "tab.cards", "tab.settings"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 10), "\(id) not found")
        }

        // Bekleme olmadan hızlı geçişler; iki tur.
        for _ in 0..<2 {
            app.buttons["tab.analytics"].tap()
            app.buttons["tab.cards"].tap()
            app.buttons["tab.settings"].tap()
            app.buttons["tab.home"].tap()
        }
        app.buttons["tab.analytics"].tap()
        app.buttons["tab.cards"].tap()
        app.buttons["tab.settings"].tap()

        // Son sekme Settings: içeriği görünür, diğerleri gizli.
        XCTAssertTrue(app.switches["settings.reminders"].waitForExistence(timeout: 10), "Settings content must be visible after rapid switching")
        XCTAssertFalse(element("cards.list", in: app).exists, "Cards must be hidden after ending on Settings")
        XCTAssertFalse(element("analytics.screen", in: app).exists, "Analytics must be hidden after ending on Settings")

        // Başka bir sırayla bitiş: Home son.
        app.buttons["tab.cards"].tap()
        app.buttons["tab.home"].tap()
        XCTAssertTrue(app.staticTexts["home.month"].waitForExistence(timeout: 10), "Home content must be visible after ending on Home")
        XCTAssertFalse(app.switches["settings.reminders"].waitForExistence(timeout: 1), "Settings must be hidden after ending on Home")
    }

    // MARK: - Alt çubuk payı (#232)

    /// Yüzen çubuğun (sekme düğmeleri ve ＋) en üst kenarı.
    @MainActor
    private func barTop(in app: XCUIApplication) -> CGFloat {
        let ids = ["tab.home", "tab.analytics", "tab.cards", "tab.settings", "tab.add"]
        let tops = ids.map { app.buttons[$0] }.filter { $0.exists }.map { $0.frame.minY }
        return tops.min() ?? .greatestFiniteMagnitude
    }

    /// Ekrandaki kaydırılabilir kapsayıcı (ScrollView, List ya da Form).
    @MainActor
    private func scrollContainer(in app: XCUIApplication) -> XCUIElement {
        let candidates = [app.scrollViews.firstMatch, app.collectionViews.firstMatch, app.tables.firstMatch]
        return candidates.first { $0.exists } ?? app.scrollViews.firstMatch
    }

    /// Kapsayıcının tek bir anlık görüntüsünü bellekte gezer (öğe öğe sorgu yok, hızlı); ekranda görünen
    /// metin ve düğmelerin en alttakinin alt kenarını ve kimliğini/etiketini döndürür.
    @MainActor
    private func lowestContentEdge(of container: XCUIElement, in app: XCUIApplication) throws -> (edge: CGFloat, identifier: String, label: String)? {
        let screenHeight = app.windows.firstMatch.frame.height
        let snapshot = try container.snapshot()
        var bestEdge: CGFloat = 0
        var best: (edge: CGFloat, identifier: String, label: String)?
        func walk(_ node: XCUIElementSnapshot) {
            let isContent = node.elementType == .staticText || node.elementType == .button
            let frame = node.frame
            let visible = frame.height > 0 && frame.minY < screenHeight
            if isContent && visible && !node.identifier.hasPrefix("tab.") && frame.maxY > bestEdge {
                bestEdge = frame.maxY
                best = (frame.maxY, node.identifier, node.label)
            }
            for child in node.children { walk(child) }
        }
        walk(snapshot)
        return best
    }

    /// Kaydırma bitene kadar (en alttaki içerik kenarı değişmeyene kadar, sınırlı) yukarı kaydırır; son öğeyi çubukla karşılaştırır.
    @MainActor
    private func assertEndOfScrollClearsBar(in app: XCUIApplication, screen: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let container = scrollContainer(in: app)
        XCTAssertTrue(container.waitForExistence(timeout: 10), "\(screen): scroll container not found", file: file, line: line)

        var previous: CGFloat = -1
        var stable = 0
        for _ in 0..<12 {
            container.swipeUp(velocity: .fast)
            let current = try lowestContentEdge(of: container, in: app)?.edge ?? 0
            // İki ardışık kaydırma aynı sonucu verirse uçtayız.
            stable = abs(current - previous) < 0.5 ? stable + 1 : 0
            previous = current
            if stable >= 2 { break }
        }
        XCTAssertGreaterThanOrEqual(stable, 2, "\(screen): scroll never settled", file: file, line: line)

        let top = barTop(in: app)
        let last = try XCTUnwrap(lowestContentEdge(of: container, in: app), "\(screen): no content found", file: file, line: line)
        // Çubukla son satır arasında küçük bir boşluk olmalı (barGap 12 pt; ölçüm payı için 4 pt aranır).
        XCTAssertLessThanOrEqual(last.edge + 4, top, "\(screen): last content (\(last.edge)) must end with a gap above the floating bar (\(top))", file: file, line: line)
        // Tek sorgu: son öğe fiziksel olarak dokunulabilir olmalı.
        let lastElement = last.identifier.isEmpty ? app.staticTexts[last.label] : element(last.identifier, in: app)
        if lastElement.exists {
            XCTAssertTrue(lastElement.isHittable, "\(screen): last element must be hittable at the end of the scroll", file: file, line: line)
        }
    }

    @MainActor
    func testHomeLastContentStaysAboveFloatingBarAtScrollEnd() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 10), "tab bar not found")
        try assertEndOfScrollClearsBar(in: app, screen: "Home")
    }

    @MainActor
    func testSettingsLastContentStaysAboveFloatingBarAtScrollEnd() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        let settings = app.buttons["tab.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "settings tab not found")
        settings.tap()
        XCTAssertTrue(app.staticTexts["settings.version"].waitForExistence(timeout: 5), "Settings not shown")
        try assertEndOfScrollClearsBar(in: app, screen: "Settings")
        // Sürüm metni Ayarlar'ın son öğesi: tam görünür ve çubuğun üstünde olmalı.
        let version = app.staticTexts["settings.version"]
        XCTAssertLessThanOrEqual(version.frame.maxY + 4, barTop(in: app), "version text must clear the floating bar")
    }

    @MainActor
    func testCardsLastContentStaysAboveFloatingBarAtScrollEnd() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        let cards = app.buttons["tab.cards"]
        XCTAssertTrue(cards.waitForExistence(timeout: 10), "cards tab not found")
        cards.tap()
        XCTAssertTrue(element("cards.list", in: app).waitForExistence(timeout: 5), "Cards not shown")
        try assertEndOfScrollClearsBar(in: app, screen: "Cards")
    }

    @MainActor
    func testAnalyticsLastContentStaysAboveFloatingBarAtScrollEnd() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        let analytics = app.buttons["tab.analytics"]
        XCTAssertTrue(analytics.waitForExistence(timeout: 10), "analytics tab not found")
        analytics.tap()
        XCTAssertTrue(element("analytics.donut", in: app).waitForExistence(timeout: 5), "Analytics not shown")
        try assertEndOfScrollClearsBar(in: app, screen: "Analytics")
    }

    @MainActor
    func testPrivacyPolicyPushedFromSettingsEndsAboveFloatingBar() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        let settings = app.buttons["tab.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "settings tab not found")
        settings.tap()
        let privacy = element("settings.privacy", in: app)
        XCTAssertTrue(privacy.waitForExistence(timeout: 5), "privacy row not found")
        privacy.tap()
        XCTAssertTrue(element("privacy.policy.intro", in: app).waitForExistence(timeout: 5), "privacy policy not pushed")
        try assertEndOfScrollClearsBar(in: app, screen: "Privacy policy")
    }

    // MARK: Ekstre incelemesi (#216)

    /// İnceleme ekranı örnek adaylarla açılır: bir satırın seçimi kaldırılır, biri düzenlenir, kaydedilir;
    /// seçili satırlar Home'da görünür, seçimi kaldırılan görünmez.
    @MainActor
    func testStatementReviewUnselectEditSaveShowsOnHome() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ui-statement-review"])
        XCTAssertTrue(element("statementReview.title", in: app).waitForExistence(timeout: 10), "review screen not shown")
        let save = app.buttons["statementReview.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Add button not found")

        // Seçimi kaldır: ikinci satır ("ORNEK GIYIM"); varsayılan seçili, değilse olduğu gibi bırakılır.
        let giyim = app.buttons["statementReview.row.1"]
        XCTAssertTrue(giyim.waitForExistence(timeout: 5), "second row not found")
        if giyim.isSelected { giyim.tap() }
        XCTAssertFalse(giyim.isSelected, "row must be unselected after tapping")

        // Birinci satırı düzenle: başlığın sonuna metin ekle.
        let edit = app.buttons["statementReview.row.0.edit"]
        XCTAssertTrue(edit.exists, "edit button of the first row not found")
        edit.tap()
        let titleField = app.textFields["statementReview.edit.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "edit sheet not shown")
        titleField.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        titleField.typeText(" Duzen")
        app.buttons["statementReview.edit.done"].tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5), "review must be shown again after editing")

        XCTAssertTrue(save.isEnabled, "Add must be enabled with valid selected rows")
        save.tap()

        // Sayfa kapanır, Home'da düzenlenen satır görünür; seçimi kaldırılan görünmez.
        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 10), "sheet must close after saving")
        XCTAssertTrue(scrollToRow(titled: "Duzen", in: app), "edited imported installment not shown on Home")
        XCTAssertTrue(scrollToRow(titled: "ORNEK MOBILYA", in: app), "selected imported installment not shown on Home")
        XCTAssertFalse(row(titled: "ORNEK GIYIM", in: app).exists, "unselected row must not be added")
    }

    /// Örnek veride "Laptop" zaten kayıtlı: üçüncü aday (indeks 2) olası tekrar rozetini gösterir, seçili başlamaz
    /// ve Ekle düğmesi 4 değil 3 taksiti sayar.
    @MainActor
    func testStatementReviewSampleDuplicateShowsBadgeAndStartsUnselected() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ui-statement-review"])
        XCTAssertTrue(element("statementReview.title", in: app).waitForExistence(timeout: 10), "review screen not shown")
        XCTAssertTrue(element("statementReview.row.2.duplicate", in: app).waitForExistence(timeout: 5), "duplicate badge of the Laptop row not shown")
        XCTAssertFalse(element("statementReview.row.0.duplicate", in: app).exists, "first row must not be flagged")
        XCTAssertFalse(element("statementReview.row.1.duplicate", in: app).exists, "second row must not be flagged")
        XCTAssertFalse(element("statementReview.row.3.duplicate", in: app).exists, "fourth row must not be flagged")
        let laptop = app.buttons["statementReview.row.2"]
        XCTAssertTrue(laptop.exists, "Laptop row not found")
        XCTAssertFalse(laptop.isSelected, "possible duplicate must start unselected")
        XCTAssertTrue(app.buttons["statementReview.row.0"].isSelected, "non-duplicate rows start selected")
        let save = app.buttons["statementReview.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Add button not found")
        XCTAssertTrue(save.label.contains("3"), "Add button must count 3 installments, got: \(save.label)")
    }

    /// İptal hiçbir şey kaydetmez; Home'a dönülür.
    @MainActor
    func testStatementReviewCancelSavesNothing() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ui-statement-review"])
        XCTAssertTrue(element("statementReview.title", in: app).waitForExistence(timeout: 10), "review screen not shown")
        app.buttons["statementReview.cancel"].tap()
        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 10), "sheet must close after cancel")
        XCTAssertFalse(scrollToRow(titled: "ORNEK MOBILYA", in: app, attempts: 3), "cancel must not add anything")
    }

    // MARK: Ekstre toplamı (#256)

    /// Ekstre toplamı satırı listenin sonundadır; görünür olana dek yukarı kaydırır.
    @MainActor
    private func scrollToStatementTotal(in app: XCUIApplication, attempts: Int = 6) -> Bool {
        let toggle = app.buttons["statementReview.statementTotal.toggle"]
        for _ in 0..<attempts {
            if toggle.exists && toggle.isHittable { return true }
            app.swipeUp()
        }
        return toggle.exists && toggle.isHittable
    }

    /// Örnek veride ekstre toplamı sunulur: seçili başlar, hesabı gösterir, Ekle düğmesi onu sayar;
    /// kapatılınca düğmeden kalkar, açılınca geri gelir. Hiçbir şey Ekle'den önce kaydedilmez.
    @MainActor
    func testStatementReviewStatementTotalOfferToggles() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ui-statement-review"])
        XCTAssertTrue(element("statementReview.title", in: app).waitForExistence(timeout: 10), "review screen not shown")
        let save = app.buttons["statementReview.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Add button not found")
        XCTAssertTrue(save.label.localizedCaseInsensitiveContains("statement total"), "Add must count the statement total, got: \(save.label)")

        XCTAssertTrue(scrollToStatementTotal(in: app), "statement total toggle not reachable")
        XCTAssertTrue(element("statementReview.statementTotal", in: app).exists, "statement total row not found")
        let toggle = app.buttons["statementReview.statementTotal.toggle"]
        XCTAssertTrue(toggle.isSelected, "statement total must start selected")
        let breakdown = element("statementReview.statementTotal.breakdown", in: app)
        XCTAssertTrue(breakdown.exists, "breakdown not shown")
        XCTAssertFalse(breakdown.label.isEmpty, "breakdown must be readable")
        XCTAssertFalse(element("statementReview.statementTotal.none", in: app).exists, "sample statement is not covered by its installments")

        toggle.tap()
        XCTAssertFalse(toggle.isSelected, "toggle must unselect the statement total")
        XCTAssertFalse(save.label.localizedCaseInsensitiveContains("statement total"), "Add must drop the statement total, got: \(save.label)")
        toggle.tap()
        XCTAssertTrue(toggle.isSelected, "toggle must select the statement total again")
        XCTAssertTrue(save.label.localizedCaseInsensitiveContains("statement total"))
    }

    /// Satırın seçimi değişince hesap canlı güncellenir (seçili satır tutarı toplamdan düşer).
    @MainActor
    func testStatementReviewBreakdownUpdatesWithRowSelection() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ui-statement-review"])
        XCTAssertTrue(element("statementReview.title", in: app).waitForExistence(timeout: 10), "review screen not shown")
        XCTAssertTrue(scrollToStatementTotal(in: app), "statement total toggle not reachable")
        let breakdown = element("statementReview.statementTotal.breakdown", in: app)
        let before = breakdown.label
        XCTAssertFalse(before.isEmpty)

        // Satırlar listenin üstünde: ikinci satırın seçimini kaldır, hesabı yeniden oku.
        for _ in 0..<6 where !app.buttons["statementReview.row.1"].isHittable { app.swipeDown() }
        let giyim = app.buttons["statementReview.row.1"]
        XCTAssertTrue(giyim.waitForExistence(timeout: 5), "second row not found")
        if giyim.isSelected { giyim.tap() }
        XCTAssertFalse(giyim.isSelected)
        XCTAssertTrue(scrollToStatementTotal(in: app), "statement total toggle not reachable")
        XCTAssertNotEqual(breakdown.label, before, "breakdown must change when a row is unselected")
    }

    /// Ekstre toplamı seçiliyken Ekle sayfayı kapatır (taksitler ve toplam birlikte kaydedilir).
    @MainActor
    func testStatementReviewSaveWithStatementTotalClosesSheet() throws {
        let app = launchHome(extraArguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ui-statement-review"])
        XCTAssertTrue(element("statementReview.title", in: app).waitForExistence(timeout: 10), "review screen not shown")
        let save = app.buttons["statementReview.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Add button not found")
        XCTAssertTrue(save.isEnabled, "Add must be enabled")
        save.tap()
        XCTAssertTrue(app.buttons["home.add"].waitForExistence(timeout: 10), "sheet must close after saving")
    }
}
