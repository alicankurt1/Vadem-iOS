import XCTest

// UI kontrol adımı için deterministik yakalama: her ekran, her görünüm varyantında
// ekran görüntüsü alır ve Apple'ın erişilebilirlik denetimini koşar.
// Kararı bu testler değil, ekran görüntülerini değerlendiren UI kontrol agent'ı verir;
// erişilebilirlik denetimi ise test hatası olarak raporlanır.
//
// Açık/koyu mod test içinden değil, `scripts/ui-check.sh` tarafından `simctl ui … appearance`
// ile ayarlanır (`XCUIDevice.appearance` bu ortamda uygulanmıyordu). Script hangi görünümün
// aktif olduğunu `UI_CHECK_APPEARANCE` ortam değişkeniyle bildirir.
final class UICheckTests: XCTestCase {

    enum Appearance: String {
        case light, dark
    }

    /// Bir görünüm varyantı: açık/koyu mod ve Dynamic Type boyutu.
    struct Variant {
        let name: String
        let appearance: Appearance
        let contentSize: String
    }

    static let allVariants: [Variant] = [
        Variant(name: "light-default", appearance: .light, contentSize: "UICTContentSizeCategoryL"),
        Variant(name: "dark-default", appearance: .dark, contentSize: "UICTContentSizeCategoryL"),
        Variant(name: "light-AX5", appearance: .light, contentSize: "UICTContentSizeCategoryAccessibilityXXXL"),
    ]

    /// Script'in ayarladığı görünüm; Xcode'dan elle koşulunca `nil`.
    static var activeAppearance: Appearance? {
        ProcessInfo.processInfo.environment["UI_CHECK_APPEARANCE"].flatMap(Appearance.init(rawValue:))
    }

    /// Bu koşuda yakalanacak varyantlar: script bir varyant verdiyse (paralel simülatörler, #148) yalnızca o,
    /// yoksa bir görünüm verdiyse sadece onunkiler.
    static var variants: [Variant] {
        let environment = ProcessInfo.processInfo.environment
        if let name = environment["UI_CHECK_VARIANT"], !name.isEmpty {
            return allVariants.filter { $0.name == name }
        }
        guard let active = activeAppearance else { return allVariants }
        return allVariants.filter { $0.appearance == active }
    }

    /// Koyu görünümde erişilebilirlik denetimi atlanır (görüntü ve görünüm kontrolü kalır): denetim bölüm başına ~6 sn,
    /// koyu geçişin yarısı; kontrast bulguları zaten not ve token oranları birim testlerde (#148).
    /// `UI_CHECK_DARK_AUDIT=1` koyuda da çalıştırır.
    static func auditsRun(for variant: Variant) -> Bool {
        variant.appearance == .light || ProcessInfo.processInfo.environment["UI_CHECK_DARK_AUDIT"] == "1"
    }

    override func setUpWithError() throws {
        // Bir varyant hata verse de diğerlerinin görüntüsü alınsın.
        continueAfterFailure = true
    }

    @MainActor
    func testRootScreen() throws {
        try capture(screen: "root") { app, variant in
            // Kök ekran açılışta görünür; gezinme gerekmez. Sürüm artık Home'da yok (#154).
            Self.assertNoVersionLabel(in: app, name: "root__\(variant.name)")
        }
    }

    @MainActor
    func testHomeScreen() throws {
        // Ana ekran sabit örnek veriyle açılır (bugün: 12 Ekim 2026); toplam, kart alt toplamları ve liste ayrı parçalarda.
        try capture(
            screen: "home",
            launchArguments: ["-ui-sample-data"],
            sections: [
                .top,
                .scrolled(to: "home.upcoming", named: "upcoming"),
                .scrolled(to: "home.calendar", named: "calendar"),
                .scrolled(to: "home.cards", named: "cards"),
                .scrolled(to: "home.list", named: "list"),
            ]
        ) { app, variant in
            XCTAssertTrue(
                app.staticTexts["home.month"].waitForExistence(timeout: 5),
                "[ui-check] home__\(variant.name): month title not found"
            )
        }
    }

    @MainActor
    func testHomeSelectedDay() throws {
        // Seçili gün (#91, #204): örnek veri 12 Ekim 2026'da Ekim ayında açılır; 15 Ekim (Shopping kartı vadesi)
        // bu ayda ödemesi olan bir gündür. Seçili günün listesi "By card" başlığından önce gelir.
        try capture(
            screen: "home-selected-day",
            launchArguments: ["-ui-sample-data"],
            sections: [
                .scrolled(to: "home.calendar", named: "calendar"),
                .scrolled(to: "home.list", named: "list"),
                .scrolled(to: "home.cards", named: "cards"),
            ]
        ) { app, variant in
            let day = app.descendants(matching: .any)["home.calendar.day.15"]
            // Büyük metinde takvim ekranın altında kalır; görünene kadar kaydırılır.
            var attempts = 0
            while !(day.exists && day.isHittable) && attempts < 12 {
                app.swipeUp()
                attempts += 1
            }
            XCTAssertTrue(
                day.exists,
                "[ui-check] home-selected-day__\(variant.name): day 15 not found"
            )
            day.tap()
        }
    }

    @MainActor
    func testAddInstallmentForm() throws {
        // Boş ekleme formu (#62): örnek veriyle açılır, kartlar listelenir.
        try capture(
            screen: "add-installment",
            launchArguments: ["-ui-sample-data", "-ui-add-form"],
            sections: [.top, .scrolled(to: "addInstallment.firstMonth", named: "first-month")]
        ) { app, variant in
            XCTAssertTrue(
                app.textFields["addInstallment.title"].waitForExistence(timeout: 5),
                "[ui-check] add-installment__\(variant.name): title field not found"
            )
            XCTAssertTrue(
                app.buttons["addInstallment.save"].exists,
                "[ui-check] add-installment__\(variant.name): save button not found"
            )
            XCTAssertFalse(
                app.buttons["addInstallment.save"].isEnabled,
                "[ui-check] add-installment__\(variant.name): save must be disabled while the form is empty"
            )
        }
    }

    @MainActor
    func testAddInstallmentFormNoCard() throws {
        // Kartsız durum (#155): kart seçilmediğinde ödeme günü alanı görünür.
        try capture(
            screen: "add-installment-no-card",
            launchArguments: ["-ui-sample-data", "-ui-add-form"],
            sections: [.top, .scrolled(to: "addInstallment.firstMonth", named: "first-month")]
        ) { app, variant in
            XCTAssertTrue(
                app.textFields["addInstallment.title"].waitForExistence(timeout: 5),
                "[ui-check] add-installment-no-card__\(variant.name): title field not found"
            )
            XCTAssertTrue(
                app.descendants(matching: .any)["addInstallment.paymentDay"].waitForExistence(timeout: 5),
                "[ui-check] add-installment-no-card__\(variant.name): payment day field not found"
            )
        }
    }

    @MainActor
    func testAddInstallmentFormWithCard() throws {
        // Kart seçilince ödeme günü alanı kaybolur (vade günü karttan gelir).
        try capture(
            screen: "add-installment-with-card",
            launchArguments: ["-ui-sample-data", "-ui-add-form"],
            sections: [.top]
        ) { app, variant in
            let row = app.descendants(matching: .any)["addInstallment.card"]
            XCTAssertTrue(
                row.waitForExistence(timeout: 5),
                "[ui-check] add-installment-with-card__\(variant.name): card row not found"
            )
            row.tap()
            let option = app.descendants(matching: .any)["addInstallment.option.1"]
            XCTAssertTrue(
                option.waitForExistence(timeout: 5),
                "[ui-check] add-installment-with-card__\(variant.name): first card option not found"
            )
            option.tap()
            XCTAssertTrue(
                app.textFields["addInstallment.title"].waitForExistence(timeout: 5),
                "[ui-check] add-installment-with-card__\(variant.name): form did not return after choosing a card"
            )
            XCTAssertFalse(
                app.descendants(matching: .any)["addInstallment.paymentDay"].exists,
                "[ui-check] add-installment-with-card__\(variant.name): payment day must be hidden with a card"
            )
        }
    }

    @MainActor
    func testDayPickerSheet() throws {
        // #203: gün seçici sayfası (tekerlek + Bitti); AX5'te kırpılmamalı. Sayfa açık kalır, tek bölüm yakalanır.
        try capture(
            screen: "day-picker",
            launchArguments: ["-ui-sample-data", "-ui-add-form"],
            sections: [.top]
        ) { app, variant in
            let row = app.descendants(matching: .any)["addInstallment.paymentDay"]
            XCTAssertTrue(
                row.waitForExistence(timeout: 5),
                "[ui-check] day-picker__\(variant.name): payment day row not found"
            )
            row.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["addInstallment.paymentDay.sheet"].waitForExistence(timeout: 5),
                "[ui-check] day-picker__\(variant.name): day picker sheet not shown"
            )
            XCTAssertTrue(
                app.pickerWheels.firstMatch.waitForExistence(timeout: 5),
                "[ui-check] day-picker__\(variant.name): wheel not found"
            )
        }
    }

    // MARK: Türkçe yakalamalar (#136)
    // Aynı ekranlar Türkçe arayüz ve yerel ayarla açılır; açık modda varsayılan ve AX5 metin boyutu
    // yakalanır. Kesilen/taşan metin erişilebilirlik denetimi ve ekran görüntülerinde görünür.

    private static let turkish = ["-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"]

    @MainActor
    func testHomeScreenTurkish() throws {
        try capture(
            screen: "home-tr",
            launchArguments: ["-ui-sample-data"] + Self.turkish,
            sections: [
                .top,
                .scrolled(to: "home.upcoming", named: "upcoming"),
                .scrolled(to: "home.calendar", named: "calendar"),
                .scrolled(to: "home.cards", named: "cards"),
                .scrolled(to: "home.list", named: "list"),
            ]
        ) { app, variant in
            XCTAssertTrue(
                app.staticTexts["home.month"].waitForExistence(timeout: 5),
                "[ui-check] home-tr__\(variant.name): month title not found"
            )
        }
    }

    @MainActor
    func testAddInstallmentFormTurkish() throws {
        try capture(
            screen: "add-installment-tr",
            launchArguments: ["-ui-sample-data", "-ui-add-form"] + Self.turkish,
            sections: [.top, .scrolled(to: "addInstallment.firstMonth", named: "first-month")]
        ) { app, variant in
            XCTAssertTrue(
                app.textFields["addInstallment.title"].waitForExistence(timeout: 5),
                "[ui-check] add-installment-tr__\(variant.name): title field not found"
            )
        }
    }

    @MainActor
    func testAddSubscriptionFormTurkish() throws {
        try capture(
            screen: "add-subscription-tr",
            launchArguments: ["-ui-sample-data", "-ui-add-subscription"] + Self.turkish,
            sections: [.top, .scrolled(to: "addSubscription.card", named: "card")]
        ) { app, variant in
            XCTAssertTrue(
                app.textFields["addSubscription.title"].waitForExistence(timeout: 5),
                "[ui-check] add-subscription-tr__\(variant.name): title field not found"
            )
        }
    }

    @MainActor
    func testAnalyticsScreenTurkish() throws {
        try capture(
            screen: "analytics-tr",
            launchArguments: ["-ui-sample-data", "-ui-analytics"] + Self.turkish,
            sections: [
                .top,
                .scrolled(to: "analytics.breakdown", named: "donut"),
                .scrolled(to: "analytics.insight", named: "insight"),
            ]
        )
    }

    @MainActor
    func testSettingsScreenTurkish() throws {
        try capture(
            screen: "settings-tr",
            launchArguments: ["-ui-sample-data", "-ui-settings"] + Self.turkish,
            sections: [.top]
        ) { app, variant in
            Self.assertSettingsVersionLabel(in: app, name: "settings-tr__\(variant.name)")
        }
    }

    @MainActor
    func testAssistantEmptyTurkish() throws {
        try capture(
            screen: "assistant-empty-tr",
            launchArguments: ["-ui-sample-data", "-ui-scripted-assistant", "-ui-assistant"] + Self.turkish,
            sections: [.top]
        )
    }

    @MainActor
    func testAddCardFormTurkish() throws {
        // Türkçe boş kart formu (en uzun Türkçe metinler).
        try capture(
            screen: "add-card-tr",
            launchArguments: ["-ui-sample-data", "-ui-add-card-form"] + Self.turkish,
            sections: [.top]
        ) { app, variant in
            XCTAssertTrue(
                app.textFields["addCard.name"].waitForExistence(timeout: 5),
                "[ui-check] add-card-tr__\(variant.name): name field not found"
            )
        }
    }

    @MainActor
    func testEditCardInUseErrorTurkish() throws {
        // Türkçe: kullanımdaki kartı silme onayı sonrası ret mesajı.
        try capture(
            screen: "edit-card-in-use-tr",
            launchArguments: ["-ui-sample-data", "-ui-edit-card"] + Self.turkish,
            sections: [.top]
        ) { app, variant in
            let delete = revealDelete(prefix: "addCard", in: app)
            XCTAssertTrue(delete.exists, "[ui-check] edit-card-in-use-tr__\(variant.name): delete button not found")
            delete.tap()
            let confirm = app.buttons["addCard.delete.confirm"].firstMatch
            XCTAssertTrue(
                confirm.waitForExistence(timeout: 5),
                "[ui-check] edit-card-in-use-tr__\(variant.name): confirmation not shown"
            )
            confirm.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["addCard.failure"].waitForExistence(timeout: 5),
                "[ui-check] edit-card-in-use-tr__\(variant.name): in-use message not shown"
            )
        }
    }

    @MainActor
    func testAddInstallmentCardList() throws {
        // Kart seçim listesi (itme ekranı): formdaki kart satırına dokunarak açılır.
        try capture(
            screen: "add-installment-card-list",
            launchArguments: ["-ui-sample-data", "-ui-add-form"],
            sections: [.top]
        ) { app, variant in
            let row = app.descendants(matching: .any)["addInstallment.card"]
            XCTAssertTrue(
                row.waitForExistence(timeout: 5),
                "[ui-check] add-installment-card-list__\(variant.name): card row not found"
            )
            row.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["addInstallment.option.0"].waitForExistence(timeout: 5),
                "[ui-check] add-installment-card-list__\(variant.name): first option not found"
            )
        }
    }

    @MainActor
    func testAddInstallmentMonthList() throws {
        // İlk ay seçim listesi (itme ekranı).
        try capture(
            screen: "add-installment-month-list",
            launchArguments: ["-ui-sample-data", "-ui-add-form"],
            sections: [.top]
        ) { app, variant in
            let row = app.descendants(matching: .any)["addInstallment.firstMonth"]
            XCTAssertTrue(
                row.waitForExistence(timeout: 5),
                "[ui-check] add-installment-month-list__\(variant.name): first month row not found"
            )
            if !row.isHittable {
                app.swipeUp()
            }
            row.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["addInstallment.option.0"].waitForExistence(timeout: 5),
                "[ui-check] add-installment-month-list__\(variant.name): first option not found"
            )
        }
    }

    @MainActor
    func testAddInstallmentFormErrors() throws {
        // Tüm hataları gösteren form: her geçersiz alanın altında hata metni olmalı.
        try capture(
            screen: "add-installment-errors",
            launchArguments: ["-ui-sample-data", "-ui-add-form", "-ui-add-form-errors"],
            sections: [.top, .scrolled(to: "addInstallment.amount", named: "amount")]
        ) { app, variant in
            XCTAssertTrue(
                app.staticTexts["addInstallment.title.error"].waitForExistence(timeout: 5),
                "[ui-check] add-installment-errors__\(variant.name): title error not found"
            )
            XCTAssertFalse(
                app.buttons["addInstallment.save"].isEnabled,
                "[ui-check] add-installment-errors__\(variant.name): save must be disabled"
            )
        }
    }

    @MainActor
    func testAddSubscriptionForm() throws {
        // Boş abonelik formu (#66): Kaydet kapalı olmalı.
        try capture(
            screen: "add-subscription",
            launchArguments: ["-ui-sample-data", "-ui-add-subscription"],
            sections: [.top, .scrolled(to: "addSubscription.card", named: "card")]
        ) { app, variant in
            XCTAssertTrue(
                app.textFields["addSubscription.title"].waitForExistence(timeout: 5),
                "[ui-check] add-subscription__\(variant.name): title field not found"
            )
            XCTAssertFalse(
                app.buttons["addSubscription.save"].isEnabled,
                "[ui-check] add-subscription__\(variant.name): save must be disabled while the form is empty"
            )
        }
    }

    @MainActor
    func testAddSubscriptionCardList() throws {
        // Kart seçim listesi (itme ekranı).
        try capture(
            screen: "add-subscription-card-list",
            launchArguments: ["-ui-sample-data", "-ui-add-subscription"],
            sections: [.top]
        ) { app, variant in
            let row = app.descendants(matching: .any)["addSubscription.card"]
            XCTAssertTrue(
                row.waitForExistence(timeout: 5),
                "[ui-check] add-subscription-card-list__\(variant.name): card row not found"
            )
            row.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["addSubscription.option.0"].waitForExistence(timeout: 5),
                "[ui-check] add-subscription-card-list__\(variant.name): first option not found"
            )
        }
    }

    @MainActor
    func testAnalyticsScreen() throws {
        // Grafik ekranı doğrudan açılır: üstte özet kartı ve 12 çubuk, aşağıda halka grafik, açıklama ve son taksit içgörüsü.
        try capture(
            screen: "analytics",
            launchArguments: ["-ui-sample-data", "-ui-analytics"],
            sections: [
                .top,
                .scrolled(to: "analytics.breakdown", named: "donut"),
                .scrolled(to: "analytics.legend", named: "legend"),
                .scrolled(to: "analytics.insight", named: "insight"),
            ]
        )
    }

    @MainActor
    func testAssistantEmpty() throws {
        // Sohbet boş: salt okunur açıklaması, öneri çipleri, giriş ve dipnot.
        try capture(
            screen: "assistant-empty",
            launchArguments: ["-ui-sample-data", "-ui-scripted-assistant", "-ui-assistant"],
            sections: [.top]
        )
    }

    @MainActor
    func testAssistantChat() throws {
        // Bir çipe dokunulur; soru ve betiklenmiş cevap görünür.
        try capture(
            screen: "assistant-chat",
            launchArguments: ["-ui-sample-data", "-ui-scripted-assistant", "-ui-assistant"],
            sections: [.top],
            navigate: { app, variant in
                let chip = app.buttons["assistant.suggestion.0"]
                XCTAssertTrue(chip.waitForExistence(timeout: 10), "[ui-check] assistant-chat__\(variant.name): chip not found")
                chip.tap()
                XCTAssertTrue(
                    app.descendants(matching: .any)["assistant.message.1"].waitForExistence(timeout: 10),
                    "[ui-check] assistant-chat__\(variant.name): reply not found"
                )
            }
        )
    }

    @MainActor
    func testAssistantUnavailable() throws {
        // Model kapalı: sohbet yerine açıklama görünür.
        try capture(
            screen: "assistant-unavailable",
            launchArguments: ["-ui-sample-data", "-ui-assistant-unavailable", "-ui-assistant"],
            sections: [.top]
        )
    }

    @MainActor
    func testSettingsScreen() throws {
        try capture(
            screen: "settings",
            launchArguments: ["-ui-sample-data", "-ui-settings"],
            sections: [.top]
        ) { app, variant in
            Self.assertSettingsVersionLabel(in: app, name: "settings__\(variant.name)")
        }
    }

    @MainActor
    func testPrivacyPolicyScreen() throws {
        // Uzun metin: üstten başlar, son bölümün başlığına kaydırılır (6 bölüm: 0...5).
        try capture(
            screen: "privacy-policy",
            launchArguments: ["-ui-sample-data", "-ui-privacy-policy"],
            sections: [
                .top,
                .scrolled(to: "privacy.policy.section.2", named: "middle"),
                .scrolled(to: "privacy.policy.section.5", named: "last"),
            ]
        )
    }

    @MainActor
    func testCardsScreen() throws {
        // Kartlar listesi; AX5'te uzar, son kartın işaretçisine kaydırılır.
        try capture(
            screen: "cards",
            launchArguments: ["-ui-sample-data", "-ui-card-list"],
            sections: [.top, .scrolled(to: "cards.row.2", named: "last")]
        )
    }

    @MainActor
    func testCardsScreenEmpty() throws {
        // Boş durum: açıklama ve kart ekleme düğmesi.
        try capture(
            screen: "cards-empty",
            launchArguments: ["-ui-sample-data", "-ui-card-list-empty"],
            sections: [.top]
        )
    }

    @MainActor
    func testSettingsDenied() throws {
        // İzin reddedilmiş: açıklama ve sistem Ayarları düğmesi görünür.
        try capture(
            screen: "settings-denied",
            launchArguments: ["-ui-sample-data", "-ui-settings-denied"],
            sections: [.top]
        )
    }

    @MainActor
    func testSettingsTimingList() throws {
        // Zamanlama seçim listesi (itme ekranı).
        try capture(
            screen: "settings-timing-list",
            launchArguments: ["-ui-sample-data", "-ui-settings"],
            sections: [.top]
        ) { app, variant in
            let row = app.descendants(matching: .any)["settings.timing"]
            XCTAssertTrue(
                row.waitForExistence(timeout: 5),
                "[ui-check] settings-timing-list__\(variant.name): timing row not found"
            )
            if !row.isHittable { app.swipeUp() }
            row.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["settings.timing.option.0"].waitForExistence(timeout: 5),
                "[ui-check] settings-timing-list__\(variant.name): first option not found"
            )
        }
    }

    @MainActor
    func testAddSubscriptionPeriodList() throws {
        // Yenileme sıklığı seçim listesi (itme ekranı).
        try capture(
            screen: "add-subscription-period-list",
            launchArguments: ["-ui-sample-data", "-ui-add-subscription"],
            sections: [.top]
        ) { app, variant in
            let row = app.descendants(matching: .any)["addSubscription.period"]
            XCTAssertTrue(
                row.waitForExistence(timeout: 5),
                "[ui-check] add-subscription-period-list__\(variant.name): period row not found"
            )
            if !row.isHittable { app.swipeUp() }
            row.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["addSubscription.option.0"].waitForExistence(timeout: 5),
                "[ui-check] add-subscription-period-list__\(variant.name): first option not found"
            )
        }
    }

    @MainActor
    func testAddSubscriptionMonthList() throws {
        // İlk ödeme ayı seçim listesi (itme ekranı).
        try capture(
            screen: "add-subscription-month-list",
            launchArguments: ["-ui-sample-data", "-ui-add-subscription"],
            sections: [.top]
        ) { app, variant in
            let row = app.descendants(matching: .any)["addSubscription.firstMonth"]
            // AX5'te satır kaydırılana kadar oluşmaz (lazy liste): önce kaydır, sonra doğrula.
            var attempts = 0
            while !row.exists && attempts < 5 {
                app.swipeUp()
                attempts += 1
            }
            XCTAssertTrue(
                row.waitForExistence(timeout: 5),
                "[ui-check] add-subscription-month-list__\(variant.name): first month row not found"
            )
            if !row.isHittable { app.swipeUp() }
            row.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["addSubscription.option.0"].waitForExistence(timeout: 5),
                "[ui-check] add-subscription-month-list__\(variant.name): first option not found"
            )
        }
    }

    @MainActor
    func testAddSubscriptionFormErrors() throws {
        // Tüm hataları gösteren form: başlık ve tutar hatası görünmeli, Kaydet kapalı kalmalı.
        try capture(
            screen: "add-subscription-errors",
            launchArguments: ["-ui-sample-data", "-ui-add-subscription", "-ui-add-subscription-errors"],
            sections: [.top, .scrolled(to: "addSubscription.amount", named: "amount")]
        ) { app, variant in
            XCTAssertTrue(
                app.staticTexts["addSubscription.title.error"].waitForExistence(timeout: 5),
                "[ui-check] add-subscription-errors__\(variant.name): title error not found"
            )
            XCTAssertFalse(
                app.buttons["addSubscription.save"].isEnabled,
                "[ui-check] add-subscription-errors__\(variant.name): save must be disabled"
            )
        }
    }

    @MainActor
    func testAddCardForm() throws {
        // Boş kart formu (#65): örnek veriyle açılır, Kaydet kapalı olmalı.
        try capture(
            screen: "add-card",
            launchArguments: ["-ui-sample-data", "-ui-add-card-form"],
            sections: [.top]
        ) { app, variant in
            XCTAssertTrue(
                app.textFields["addCard.name"].waitForExistence(timeout: 5),
                "[ui-check] add-card__\(variant.name): name field not found"
            )
            XCTAssertTrue(
                app.textFields["addCard.statementDay"].exists && app.textFields["addCard.dueDay"].exists,
                "[ui-check] add-card__\(variant.name): day fields not found"
            )
            XCTAssertFalse(
                app.buttons["addCard.save"].isEnabled,
                "[ui-check] add-card__\(variant.name): save must be disabled while the form is empty"
            )
        }
    }

    @MainActor
    func testAddCardFormErrors() throws {
        // Tüm hataları gösteren kart formu: Kaydet kapalı kalmalı.
        try capture(
            screen: "add-card-errors",
            launchArguments: ["-ui-sample-data", "-ui-add-card-form", "-ui-add-card-form-errors"],
            sections: [.top]
        ) { app, variant in
            XCTAssertTrue(
                app.textFields["addCard.name"].waitForExistence(timeout: 5),
                "[ui-check] add-card-errors__\(variant.name): name field not found"
            )
            XCTAssertFalse(
                app.buttons["addCard.save"].isEnabled,
                "[ui-check] add-card-errors__\(variant.name): save must be disabled"
            )
        }
    }

    // MARK: Düzenleme ve silme (#67)

    /// Silme düğmesi görünene dek formu yukarı kaydırır (en çok 6 kez); düğmeyi döndürür.
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
    func testEditInstallmentForm() throws {
        // Dolu taksit formu: değerler hazır, Kaydet açık; silme bölümü ayrı parçada.
        try capture(
            screen: "edit-installment",
            launchArguments: ["-ui-sample-data", "-ui-edit-installment"],
            sections: [.top, .scrolled(to: "addInstallment.delete", named: "delete")]
        ) { app, variant in
            XCTAssertTrue(
                app.textFields["addInstallment.title"].waitForExistence(timeout: 5),
                "[ui-check] edit-installment__\(variant.name): title field not found"
            )
            XCTAssertTrue(
                app.buttons["addInstallment.save"].isEnabled,
                "[ui-check] edit-installment__\(variant.name): save must be enabled with the saved values"
            )
        }
    }

    @MainActor
    func testEditInstallmentDeleteConfirmation() throws {
        // Silme onayı açık.
        try capture(
            screen: "edit-installment-confirm",
            launchArguments: ["-ui-sample-data", "-ui-edit-installment"],
            sections: [.top]
        ) { app, variant in
            let delete = revealDelete(prefix: "addInstallment", in: app)
            XCTAssertTrue(delete.exists, "[ui-check] edit-installment-confirm__\(variant.name): delete button not found")
            delete.tap()
            XCTAssertTrue(
                app.buttons["addInstallment.delete.confirm"].firstMatch.waitForExistence(timeout: 5),
                "[ui-check] edit-installment-confirm__\(variant.name): confirmation not shown"
            )
        }
    }

    @MainActor
    func testEditSubscriptionForm() throws {
        // Dolu abonelik formu.
        try capture(
            screen: "edit-subscription",
            launchArguments: ["-ui-sample-data", "-ui-edit-subscription"],
            sections: [.top, .scrolled(to: "addSubscription.delete", named: "delete")]
        ) { app, variant in
            XCTAssertTrue(
                app.textFields["addSubscription.title"].waitForExistence(timeout: 5),
                "[ui-check] edit-subscription__\(variant.name): title field not found"
            )
            XCTAssertTrue(
                app.buttons["addSubscription.save"].isEnabled,
                "[ui-check] edit-subscription__\(variant.name): save must be enabled with the saved values"
            )
        }
    }

    @MainActor
    func testEditSubscriptionDeleteConfirmation() throws {
        // Abonelik silme onayı açık.
        try capture(
            screen: "edit-subscription-confirm",
            launchArguments: ["-ui-sample-data", "-ui-edit-subscription"],
            sections: [.top]
        ) { app, variant in
            let delete = revealDelete(prefix: "addSubscription", in: app)
            XCTAssertTrue(delete.exists, "[ui-check] edit-subscription-confirm__\(variant.name): delete button not found")
            delete.tap()
            XCTAssertTrue(
                app.buttons["addSubscription.delete.confirm"].firstMatch.waitForExistence(timeout: 5),
                "[ui-check] edit-subscription-confirm__\(variant.name): confirmation not shown"
            )
        }
    }

    @MainActor
    func testEditCardForm() throws {
        // Dolu kart formu.
        try capture(
            screen: "edit-card",
            launchArguments: ["-ui-sample-data", "-ui-edit-card"],
            sections: [.top, .scrolled(to: "addCard.delete", named: "delete")]
        ) { app, variant in
            XCTAssertTrue(
                app.textFields["addCard.name"].waitForExistence(timeout: 5),
                "[ui-check] edit-card__\(variant.name): name field not found"
            )
            XCTAssertTrue(
                app.buttons["addCard.save"].isEnabled,
                "[ui-check] edit-card__\(variant.name): save must be enabled with the saved values"
            )
        }
    }

    @MainActor
    func testEditCardDeleteConfirmation() throws {
        // Kart silme onayı açık.
        try capture(
            screen: "edit-card-confirm",
            launchArguments: ["-ui-sample-data", "-ui-edit-card"],
            sections: [.top]
        ) { app, variant in
            let delete = revealDelete(prefix: "addCard", in: app)
            XCTAssertTrue(delete.exists, "[ui-check] edit-card-confirm__\(variant.name): delete button not found")
            delete.tap()
            XCTAssertTrue(
                app.buttons["addCard.delete.confirm"].firstMatch.waitForExistence(timeout: 5),
                "[ui-check] edit-card-confirm__\(variant.name): confirmation not shown"
            )
        }
    }

    @MainActor
    func testEditCardInUseError() throws {
        // Örnek veride kart kullanımda: silme onaylanınca ret mesajı görünür.
        try capture(
            screen: "edit-card-in-use",
            launchArguments: ["-ui-sample-data", "-ui-edit-card"],
            sections: [.top]
        ) { app, variant in
            let delete = revealDelete(prefix: "addCard", in: app)
            XCTAssertTrue(delete.exists, "[ui-check] edit-card-in-use__\(variant.name): delete button not found")
            delete.tap()
            let confirm = app.buttons["addCard.delete.confirm"].firstMatch
            XCTAssertTrue(
                confirm.waitForExistence(timeout: 5),
                "[ui-check] edit-card-in-use__\(variant.name): confirmation not shown"
            )
            confirm.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["addCard.failure"].waitForExistence(timeout: 5),
                "[ui-check] edit-card-in-use__\(variant.name): in-use message not shown"
            )
        }
    }

    @MainActor
    func testGalleryScreen() throws {
        // Galeri uzun bir ekran; başlık, çipler ve tutarlar ayrı görüntülerde yakalanır (#33).
        // Kart yüzleri testGalleryCards'ta: tek testte 9 parça × 3 varyant 3 dk sınırını aşıyordu.
        try capture(
            screen: "gallery",
            launchArguments: ["-ui-gallery"],
            sections: [
                .top,
                .scrolled(to: "gallery.chips", named: "chips"),
                .scrolled(to: "gallery.amounts", named: "amounts"),
            ]
        ) { app, variant in
            XCTAssertTrue(
                Self.galleryTitle(in: app).waitForExistence(timeout: 5),
                "[ui-check] gallery__\(variant.name): 'Design gallery' title not found"
            )
        }
    }

    @MainActor
    func testGalleryCards() throws {
        // Her kart yüzü kendi parçasında en üste kaydırılır; AX5'te de hiçbir yüz atlanmaz (#36).
        // Altı yüz × 3 varyant tek testte 3 dk sınırını aşıyordu; ikiye bölündü (#142).
        try captureGalleryCards(["night", "ocean", "emerald"])
    }

    @MainActor
    func testGalleryCardsWarm() throws {
        try captureGalleryCards(["sunset", "lavender", "graphite"])
    }

    /// Ekran adı "gallery" kalır: görüntü adları (gallery-card-<yüz>) değişmez.
    @MainActor
    private func captureGalleryCards(_ faces: [String]) throws {
        let cardParts: [Section] = faces.map {
            .scrolled(to: "gallery.card.\($0)", named: "card-\($0)")
        }
        try capture(
            screen: "gallery",
            launchArguments: ["-ui-gallery", "-ui-gallery-cards-only"],
            sections: cardParts
        ) { app, variant in
            XCTAssertTrue(
                Self.galleryTitle(in: app).waitForExistence(timeout: 5),
                "[ui-check] gallery__\(variant.name): 'Design gallery' title not found"
            )
        }
    }

    // MARK: Ekleme akışı kabuğu (#188)

    @MainActor
    func testAddFlowSheet() throws {
        // Home'daki Add sayfası: üç büyük seçenek.
        try capture(
            screen: "add-sheet",
            launchArguments: ["-ui-sample-data", "-ui-add-sheet"],
            sections: [.top, .scrolled(to: "add.sheet.payment", named: "payment")]
        ) { app, variant in
            for kind in ["installment", "subscription", "payment"] {
                XCTAssertTrue(
                    app.descendants(matching: .any)["add.sheet.\(kind)"].waitForExistence(timeout: 5),
                    "[ui-check] add-sheet__\(variant.name): \(kind) option not found"
                )
            }
        }
    }

    @MainActor
    func testAddFlowPaymentPlaceholder() throws {
        // Ödeme seçilince sayfanın içinde tek seferlik akışın tutar adımı (akış kabuğu: ilerleme, geri, kapat).
        try capture(
            screen: "add-payment",
            launchArguments: ["-ui-sample-data", "-ui-add-sheet"],
            sections: [.top]
        ) { app, variant in
            let payment = app.descendants(matching: .any)["add.sheet.payment"]
            XCTAssertTrue(payment.waitForExistence(timeout: 5), "[ui-check] add-payment__\(variant.name): payment option not found")
            payment.tap()
            XCTAssertTrue(
                app.buttons["keypad.digit.1"].waitForExistence(timeout: 5),
                "[ui-check] add-payment__\(variant.name): one-time flow amount step not found"
            )
        }
    }

    @MainActor
    func testAddFlowKeypadStep() throws {
        // Büyük tutar tuş takımı: Devam kapalı (tutar yok).
        try capture(
            screen: "add-flow-keypad",
            launchArguments: ["-ui-sample-data", "-ui-add-flow-keypad"],
            sections: [.top]
        ) { app, variant in
            XCTAssertTrue(
                app.descendants(matching: .any)["keypad.display"].waitForExistence(timeout: 5),
                "[ui-check] add-flow-keypad__\(variant.name): keypad display not found"
            )
            XCTAssertFalse(app.buttons["flow.continue"].isEnabled, "[ui-check] add-flow-keypad__\(variant.name): continue must be disabled without an amount")
        }
    }

    @MainActor
    func testAddFlowKeypadTyped() throws {
        // Tutar yazılmış tuş takımı: Devam açık.
        try capture(
            screen: "add-flow-keypad-typed",
            launchArguments: ["-ui-sample-data", "-ui-add-flow-keypad"],
            sections: [.top]
        ) { app, variant in
            let one = app.buttons["keypad.digit.1"]
            XCTAssertTrue(one.waitForExistence(timeout: 5), "[ui-check] add-flow-keypad-typed__\(variant.name): key 1 not found")
            one.tap()
            app.buttons["keypad.digit.4"].tap()
            app.buttons["keypad.digit.9"].tap()
            app.buttons["keypad.digit.9"].tap()
            app.buttons["keypad.separator"].tap()
            app.buttons["keypad.digit.9"].tap()
            XCTAssertTrue(app.buttons["flow.continue"].isEnabled, "[ui-check] add-flow-keypad-typed__\(variant.name): continue must be enabled")
        }
    }

    @MainActor
    func testAddFlowChipsStep() throws {
        // Seçim çipleri adımı (seçili çip yok).
        try capture(
            screen: "add-flow-chips",
            launchArguments: ["-ui-sample-data", "-ui-add-flow-chips"],
            sections: [.top]
        ) { app, variant in
            XCTAssertTrue(
                app.descendants(matching: .any)["flow.period.chip.0"].waitForExistence(timeout: 5),
                "[ui-check] add-flow-chips__\(variant.name): first chip not found"
            )
        }
    }

    @MainActor
    func testAddFlowCardPickerStep() throws {
        // Kart seçimi adımı: kartlar, görünür "Kart yok" ve "+ Yeni kart"; parçalar kendi işaretçilerinde.
        try capture(
            screen: "add-flow-card",
            launchArguments: ["-ui-sample-data", "-ui-add-flow-card"],
            sections: [.top, .scrolled(to: "cardPicker.newCard", named: "new-card")]
        ) { app, variant in
            XCTAssertTrue(
                app.descendants(matching: .any)["cardPicker.noCard"].waitForExistence(timeout: 5),
                "[ui-check] add-flow-card__\(variant.name): 'No card' row not found"
            )
            XCTAssertTrue(
                app.descendants(matching: .any)["cardPicker.newCard"].exists,
                "[ui-check] add-flow-card__\(variant.name): 'New card' row not found"
            )
        }
    }

    @MainActor
    func testAddFlowSheetTurkish() throws {
        try capture(
            screen: "add-sheet-tr",
            launchArguments: ["-ui-sample-data", "-ui-add-sheet", "-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"],
            sections: [.top]
        ) { app, variant in
            XCTAssertTrue(
                app.descendants(matching: .any)["add.sheet.installment"].waitForExistence(timeout: 5),
                "[ui-check] add-sheet-tr__\(variant.name): installment option not found"
            )
        }
    }

    // MARK: Taksit hızlı adımları (#189)

    /// Hızlı taksit akışını `depth` adım ilerletir (0: tutar, 1: sayı, 2: kart, 3: ilk ay, 4: başlık, 5: özet).
    /// Yalnızca dokunuşla ilerler; uygulamayı kapatıp açmaz. Bulunamayan öğe hata olarak raporlanır.
    @MainActor
    private func advanceInstallmentFlow(to depth: Int, screen: String, app: XCUIApplication, variant: Variant) {
        func find(_ identifier: String, _ step: String) -> XCUIElement? {
            let element = app.descendants(matching: .any)[identifier]
            guard element.waitForExistence(timeout: 10) else {
                XCTFail("[ui-check] \(screen)__\(variant.name): \(step) not found (\(identifier))")
                return nil
            }
            return element
        }
        guard find("keypad.display", "amount step") != nil else { return }
        guard depth > 0 else { return }
        for digit in ["1", "2", "0", "0"] { app.buttons["keypad.digit.\(digit)"].tap() }
        app.buttons["flow.continue"].tap()
        guard depth > 1 else { return }
        guard let count = find("addInstallmentFlow.count.chip.1", "count chip") else { return }
        count.tap()
        guard depth > 2 else { return }
        guard let noCard = find("cardPicker.noCard", "'No card' row") else { return }
        noCard.tap()
        guard depth > 3 else { return }
        guard let month = find("addInstallmentFlow.month.chip.0", "first month chip") else { return }
        month.tap()
        guard depth > 4 else { return }
        guard let skip = find("addInstallmentFlow.skip", "title Skip") else { return }
        skip.tap()
    }

    private static let installmentFlowArguments = ["-ui-sample-data", "-ui-add-installment-flow"]

    @MainActor
    func testInstallmentFlowAmountStep() throws {
        // 1. adım: tutar tuş takımı, tutar yazılmış (Devam açık).
        try capture(
            screen: "installment-flow-amount",
            launchArguments: Self.installmentFlowArguments,
            sections: [.top]
        ) { app, variant in
            self.advanceInstallmentFlow(to: 0, screen: "installment-flow-amount", app: app, variant: variant)
            for digit in ["1", "2", "0", "0"] { app.buttons["keypad.digit.\(digit)"].tap() }
            XCTAssertTrue(app.buttons["flow.continue"].isEnabled, "[ui-check] installment-flow-amount__\(variant.name): continue must be enabled")
        }
    }

    @MainActor
    func testInstallmentFlowCountStep() throws {
        // 2. adım: taksit sayısı çipleri.
        try capture(
            screen: "installment-flow-count",
            launchArguments: Self.installmentFlowArguments,
            sections: [.top]
        ) { app, variant in
            self.advanceInstallmentFlow(to: 1, screen: "installment-flow-count", app: app, variant: variant)
            XCTAssertTrue(
                app.descendants(matching: .any)["addInstallmentFlow.count.chip.0"].waitForExistence(timeout: 10),
                "[ui-check] installment-flow-count__\(variant.name): count chips not found"
            )
        }
    }

    @MainActor
    func testInstallmentFlowCardStep() throws {
        // 3. adım: kart seçimi; "Yeni kart" kendi parçasında.
        try capture(
            screen: "installment-flow-card",
            launchArguments: Self.installmentFlowArguments,
            sections: [.top, .scrolled(to: "cardPicker.newCard", named: "new-card")]
        ) { app, variant in
            self.advanceInstallmentFlow(to: 2, screen: "installment-flow-card", app: app, variant: variant)
            XCTAssertTrue(
                app.descendants(matching: .any)["cardPicker.noCard"].waitForExistence(timeout: 10),
                "[ui-check] installment-flow-card__\(variant.name): card step not found"
            )
        }
    }

    @MainActor
    func testInstallmentFlowFirstMonthStep() throws {
        // 4. adım: ilk vade ayı çipleri.
        try capture(
            screen: "installment-flow-month",
            launchArguments: Self.installmentFlowArguments,
            sections: [.top]
        ) { app, variant in
            self.advanceInstallmentFlow(to: 3, screen: "installment-flow-month", app: app, variant: variant)
            XCTAssertTrue(
                app.descendants(matching: .any)["addInstallmentFlow.month.chip.0"].waitForExistence(timeout: 10),
                "[ui-check] installment-flow-month__\(variant.name): month chips not found"
            )
        }
    }

    @MainActor
    func testInstallmentFlowTitleStep() throws {
        // 5. adım: isteğe bağlı başlık (alan, hızlı çipler, Atla).
        try capture(
            screen: "installment-flow-title",
            launchArguments: Self.installmentFlowArguments,
            sections: [.top, .scrolled(to: "addInstallmentFlow.skip", named: "skip")]
        ) { app, variant in
            self.advanceInstallmentFlow(to: 4, screen: "installment-flow-title", app: app, variant: variant)
            XCTAssertTrue(
                app.descendants(matching: .any)["addInstallmentFlow.titleField"].waitForExistence(timeout: 10),
                "[ui-check] installment-flow-title__\(variant.name): title field not found"
            )
        }
    }

    @MainActor
    func testInstallmentFlowSummaryStep() throws {
        // 6. adım: özet; ödeme günü ve Değiştir bağlantısı, Kaydet kendi parçasında.
        try capture(
            screen: "installment-flow-summary",
            launchArguments: Self.installmentFlowArguments,
            sections: [.top, .scrolled(to: "addInstallmentFlow.save", named: "save")]
        ) { app, variant in
            self.advanceInstallmentFlow(to: 5, screen: "installment-flow-summary", app: app, variant: variant)
            XCTAssertTrue(
                app.descendants(matching: .any)["addInstallmentFlow.save"].waitForExistence(timeout: 10),
                "[ui-check] installment-flow-summary__\(variant.name): Save not found"
            )
            XCTAssertTrue(
                app.descendants(matching: .any)["addInstallmentFlow.changePaymentDay"].exists,
                "[ui-check] installment-flow-summary__\(variant.name): Change link not found"
            )
        }
    }

    @MainActor
    func testInstallmentFlowSummaryTurkish() throws {
        // Türkçe özet: uzun metinler sarılır, kırpılmaz.
        try capture(
            screen: "installment-flow-summary-tr",
            launchArguments: Self.installmentFlowArguments + Self.turkish,
            sections: [.top]
        ) { app, variant in
            self.advanceInstallmentFlow(to: 5, screen: "installment-flow-summary-tr", app: app, variant: variant)
            XCTAssertTrue(
                app.descendants(matching: .any)["addInstallmentFlow.save"].waitForExistence(timeout: 10),
                "[ui-check] installment-flow-summary-tr__\(variant.name): Save not found"
            )
        }
    }

    @MainActor
    func testGalleryDesign() throws {
        // Hero, satırlar ve hap düğmeler kendi parçalarında yakalanır (#82); ayrı test, 3 dk sınırı için.
        try capture(
            screen: "gallery",
            launchArguments: ["-ui-gallery"],
            sections: [
                .scrolled(to: "gallery.hero", named: "hero"),
                .scrolled(to: "gallery.rows", named: "rows"),
                .scrolled(to: "gallery.pills", named: "pills"),
            ]
        ) { app, variant in
            XCTAssertTrue(
                Self.galleryTitle(in: app).waitForExistence(timeout: 5),
                "[ui-check] gallery__\(variant.name): 'Design gallery' title not found"
            )
        }
    }

    /// Sürüm etiketi sorgusu: "Version x.y" / "Sürüm x.y".
    @MainActor
    private static func versionTexts(in app: XCUIApplication) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Version ", "Sürüm "))
    }

    /// Home'da sürüm metni olmamalı (#154); başlık gezinme çubuğunda görünür kalır.
    @MainActor
    private static func assertNoVersionLabel(in app: XCUIApplication, name: String) {
        let title = app.staticTexts["Vadem"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "[ui-check] \(name): 'Vadem' title not found")
        XCTAssertEqual(
            versionTexts(in: app).count, 0,
            "[ui-check] \(name): Home must not show a version text"
        )
    }

    /// Ayarlar'da sürüm etiketi "Version x.y.z" biçiminde ve tam eşleşmeli (#154).
    @MainActor
    private static func assertSettingsVersionLabel(in app: XCUIApplication, name: String) {
        let version = versionTexts(in: app).firstMatch
        guard version.waitForExistence(timeout: 5) else {
            XCTFail("[ui-check] \(name): version label ('Version …' / 'Sürüm …') not found in Settings")
            return
        }
        let label = version.label
        XCTAssertNotNil(
            label.wholeMatch(of: /(Version|Sürüm) [0-9]+(\.[0-9]+)*/),
            "[ui-check] \(name): version label '\(label)' does not match ^(Version|Sürüm) [0-9]+(\\.[0-9]+)*$"
        )
    }

    /// Galeri başlığı; cihaz dili Türkçe olabilir (#136), bu yüzden iki dilde de aranır.
    @MainActor
    static func galleryTitle(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Design gallery", "Tasarım galerisi"])).firstMatch
    }

    // MARK: - Helpers

    /// Her yakalamada gönderilen açılış argümanları. `-ui-static-motion`: uygulama sürekli
    /// animasyonları (ör. kart mesh kayması) durdurur; yoksa uygulama boşa düşmez ve
    /// erişilebilirlik denetimi zaman aşımına uğrar (#33).
    static let commonLaunchArguments = ["-ui-static-motion"]

    /// Ekranın görüntüsü alınacak bir bölümü. Uzun ekranlar birden fazla bölümle yakalanır.
    struct Section {
        let name: String
        /// Bölümü ekrana getirir; başarılıysa `nil`, değilse nedenini döner.
        let reach: @MainActor (XCUIApplication) -> String?

        /// Açılışta görünen kısım.
        static var top: Section { Section(name: "") { _ in nil } }

        /// Kimliği (accessibilityIdentifier) ya da etiketi `marker` olan öğeyi ekranın üst kısmına
        /// (yüksekliğin ~%15'i, ama her zaman navigasyon çubuğunun altına) getirir. Sadece "görünür" olunca
        /// durmak yetmiyordu: tek kaydırma birden fazla başlığı görünür yapınca bölümler aynı görüntüyü
        /// veriyordu (#33). Hedef büyük başlıklı çubuğun altında kalınca öğe dokunulamaz sayılıyordu (#37).
        static func scrolled(to marker: String, named name: String) -> Section {
            Section(name: name) { app in
                let element = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier == %@ OR label == %@", marker, marker))
                    .firstMatch
                let window = app.windows.firstMatch.frame
                var target = window.minY
                var previousMinY: CGFloat?
                var attempts = 0
                var dragX: CGFloat = 0.5
                var trail: [Int] = []

                for _ in 0..<12 {
                    attempts += 1
                    guard element.exists else {
                        app.swipeUp(velocity: .fast)
                        continue
                    }
                    // Büyük başlık kaydırınca küçülür; çubuğun alt kenarı her adımda yeniden okunur.
                    target = max(window.minY + window.height * 0.15, barBottom(in: app) + 8)
                    let minY = element.frame.minY
                    trail.append(Int(minY))
                    let distance = minY - target
                    // Hedef bir bant: çubuğun hemen altından ekranın yarısına kadar. Dar tolerans (%5)
                    // sürüklemeyi ileri geri salındırıyordu; her sürükleme ~3 sn sürüyor (#37).
                    if minY >= target - 8, minY <= target + window.height * 0.35 { break }
                    // İçerik sonu: öğe artık yer değiştirmiyor, daha fazla sürüklemek boşa zaman.
                    // Ama önce sürüklemeyi kenar boşluğundan dene: AX5'te büyüyen grafik/kart ortadaki
                    // sürüklemeyi kendisi yakalayıp içeriği kaydırmıyordu (#142).
                    if let previousMinY, abs(previousMinY - minY) < 1 {
                        if dragX < 0.5 { break }
                        dragX = 0.03
                    }
                    previousMinY = minY
                    // Öğeyi parmakla tutup hedef bandın ortasına sürükle; tek seferde ekranın en fazla yarısı.
                    // İçerik sürüklenenden fazla kayıyor (büyük başlık daralıp genişliyor, az da olsa
                    // momentum); bu yüzden adım kısaltılır ve sonda beklenir (#37).
                    let wanted = (distance - window.height * 0.15) * 0.75
                    // Hedef çok uzaktaysa (AX5'te galeri kartları ~6000 pt aşağıda) adım büyür ve hızlanır;
                    // 12 deneme ve ~430 pt'lik adımlar yetmiyordu (#142). Yakında yine kısa, hassas adım.
                    let far = distance > window.height * 1.5
                    let maxStep = window.height * (far ? 0.8 : 0.5)
                    let step = max(-maxStep, min(maxStep, wanted))
                    let from = app.coordinate(withNormalizedOffset: CGVector(dx: dragX, dy: step > 0 ? 0.8 : 0.3))
                    let to = from.withOffset(CGVector(dx: 0, dy: -step))
                    from.press(forDuration: 0.05, thenDragTo: to, withVelocity: far ? .fast : .default, thenHoldForDuration: 0.2)
                }

                // İçerik sonuna gelindiyse öğe hedefe çıkamayabilir; çubuğun altında görünür olması yeter.
                let bar = barBottom(in: app)
                let frame = element.exists ? element.frame : .zero
                if element.exists, element.isHittable, frame.midY > bar, frame.minY < window.maxY { return nil }
                return "marker '\(marker)' not reached after \(attempts) attempts — exists: \(element.exists), "
                    + "hittable: \(element.exists && element.isHittable), marker frame: \(frame), "
                    + "bar bottom: \(bar), target y: \(target), minY trail: \(trail)"
            }
        }
    }

    /// Navigasyon çubuğunun alt kenarı (durum çubuğu bunun üstünde kalır); çubuk yoksa durum çubuğunun
    /// alt kenarı, o da yoksa pencerenin üstü. Çubuksuz ekranlarda durum çubuğunun arkasına kayan
    /// öğeler "görünür" sayılıp denetimde yanlış hata veriyordu.
    @MainActor
    static func barBottom(in app: XCUIApplication) -> CGFloat {
        let bar = app.navigationBars.firstMatch
        if bar.exists { return bar.frame.maxY }
        let windowTop = app.windows.firstMatch.frame.minY
        // Durum çubuğu uygulamanın ağacında yok; springboard'un ağacında.
        let statusBar = XCUIApplication(bundleIdentifier: "com.apple.springboard").statusBars.firstMatch
        return statusBar.exists ? max(windowTop, statusBar.frame.maxY) : windowTop
    }

    /// Uygulamayı her varyantta açar; `navigate` ile (uygulama, varyant) ekrana gider; her bölüm için
    /// görüntü alır, görünümü doğrular ve erişilebilirlik denetimini koşar.
    /// Bir varyantta denetim hata verse bile sonraki bölüm ve varyantlara devam eder.
    /// Hata sayılmayan gözlemler (`notes` eki) script tarafından ayrıca listelenir.
    @MainActor
    private func capture(
        screen: String,
        launchArguments: [String] = [],
        sections: [Section] = [.top],
        navigate: (XCUIApplication, Variant) -> Void = { _, _ in }
    ) throws {
        for variant in Self.variants {
            // Süre ölçümü: `[ui-time]` satırları script tarafından özetlenir (#148).
            var times: [String] = []
            func timed<T>(_ label: String, _ work: () throws -> T) rethrows -> T {
                let start = Date()
                defer { times.append("[ui-time] \(screen)__\(variant.name) \(label) \(String(format: "%.1f", Date().timeIntervalSince(start)))") }
                return try work()
            }

            let app = XCUIApplication()
            app.launchArguments += Self.commonLaunchArguments + launchArguments
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", variant.contentSize]
            timed("launch") { app.launch() }
            defer { app.terminate() }
            timed("navigate") { navigate(app, variant) }

            var notes: [String] = []
            var previous: (name: String, png: Data)?

            for section in sections {
                let shot = section.name.isEmpty ? screen : "\(screen)-\(section.name)"
                let name = "\(shot)__\(variant.name)"

                if let reason = timed("reach:\(section.name.isEmpty ? "top" : section.name)", { section.reach(app) }) {
                    XCTFail("[ui-check] \(name): section '\(section.name)' could not be scrolled into view — \(reason)")
                    continue
                }

                // Kaydırma göstergesi gibi kısa animasyonlar bitmeden denetim zaman aşımına uğruyordu (#33).
                let screenshot = timed("settle") { Self.settledScreenshot(of: app) }
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)

                // Aynı görüntü: kaydırma içerik sonuna takıldı, bu bölüm yeni bir şey göstermiyor (#37).
                let png = screenshot.pngRepresentation
                if let previous, previous.png == png {
                    notes.append("[ui-note] \(name) equals \(previous.name) — marker not reached (end of content?)")
                }
                previous = (name, png)

                // Görünüm gerçekten uygulandı mı? Script görünüm verdiyse arka plan parlaklığına bakılır.
                if let expected = Self.activeAppearance {
                    assertAppearance(of: screenshot, is: expected, name: name)
                }

                // Çubuğun altında ya da ekran dışında kalan öğeler çubuğa karşı ölçülüyor; bunlar
                // hata değil, "tam görünmüyor" notu olarak ayrı raporlanır (#37).
                let window = app.windows.firstMatch.frame
                let bar = Self.barBottom(in: app)
                let visible = CGRect(x: window.minX, y: bar, width: window.width, height: window.maxY - bar)
                    .insetBy(dx: -1, dy: -1)

                // Her sorun ayrı bir test hatası olur. Denetimin kendisi hata verirse (ör. zaman aşımı)
                // raporlanır ve döngü devam eder; önceden bu durumda kalan varyantlar hiç yakalanmıyordu.
                guard Self.auditsRun(for: variant) else { continue }
                do {
                    let findings = try timed("audit:\(section.name.isEmpty ? "top" : section.name)") { try Self.audit(app) }
                    // Apple'ın kontrast ölçümü gradyan ve yarı saydam zeminlerde koşudan koşuya değişiyor (#59):
                    // renkleri sağlam öğeler bile bazen geçemiyor. Bu yüzden kontrast bulguları hata değil not
                    // olur; token çiftlerinin oranını `TokenContrastTests`, kart yüzlerini `CardContrastTests`
                    // hesapla doğrular. Bulgu durulduktan sonra bir kez daha ölçülür: iki denemede de çıkan
                    // `[a11y-contrast]`, yalnızca birinde çıkan `[a11y-flaky]` olur.
                    var retried: Set<String> = []
                    if findings.contains(where: \.isContrast) {
                        _ = Self.settledScreenshot(of: app)
                        retried = Set(try Self.audit(app).filter(\.isContrast).map(\.key))
                    }
                    // Elementsiz kontrast bulgusu (`SwiftUI.AccessibilityNode`) bir çerçeve vermez. Durum çubuğunun
                    // altına kayan içerik varsa bulgu oradan gelir; o içeriğin etiketleri nota yazılır.
                    let underStatusBar = findings.contains { $0.isContrast && !$0.hasElement }
                        ? Self.labelsUnderStatusBar(in: app) : []
                    // Sistem alert'inin etiketleri (başlık, mesaj) uygulamanın yazı tipine bağlı değil: denetim bunları
                    // "Dynamic Type kısmen desteklenmiyor" diye işaretliyor ama düzeltilemez. Alert açıkken, alert
                    // çerçevesindeki (ya da elementsiz) Dynamic Type bulguları hata değil not olur.
                    let alert = app.alerts.firstMatch
                    let alertFrame: CGRect? = alert.exists ? alert.frame : nil
                    for finding in findings {
                        if let alertFrame, finding.isDynamicType, finding.frame.map({ alertFrame.insetBy(dx: -1, dy: -1).contains($0) }) ?? true {
                            notes.append("[a11y-system] \(name): \(finding.text) (system alert)")
                        } else if finding.isDynamicType, let frame = finding.frame, frame.minY > window.minY + window.height * 0.6 {
                            // Tembel `Form` listesinde alt kısımdaki satırlar, denetim yazıyı büyütürken ekran dışına
                            // itilip yeniden kullanıldığı için "kısmen desteklenmiyor" diye işaretleniyor; aynı satır
                            // üstteyken geçiyor (#67 / #74). Bu yüzden not olur; yazı tipi ölçeklenmesi `AX5` görüntüsünde
                            // gözle ve satırın `Text` + metin stili kullanmasıyla doğrulanır.
                            notes.append("[a11y-lazy] \(name): \(finding.text) (lower part of a lazy list)")
                        } else if finding.isContrast {
                            let tag = retried.contains(finding.key) ? "[a11y-contrast]" : "[a11y-flaky]"
                            let detail = finding.hasElement || underStatusBar.isEmpty
                                ? "" : " (content under the status bar: \(underStatusBar.joined(separator: ", ")))"
                            notes.append("\(tag) \(name): \(finding.text)\(detail)")
                        } else if let frame = finding.frame, !frame.isEmpty, !visible.contains(frame) {
                            notes.append("[a11y-hidden] \(name): \(finding.text) (not fully visible)")
                        } else {
                            XCTFail("[a11y] \(name): \(finding.text)")
                        }
                    }
                } catch {
                    XCTFail("[a11y] \(name): audit did not complete — \(error.localizedDescription)")
                }
            }

            let timing = XCTAttachment(string: times.joined(separator: "\n"))
            timing.name = "timing-\(screen)__\(variant.name)"
            timing.lifetime = .keepAlways
            add(timing)

            if !notes.isEmpty {
                let attachment = XCTAttachment(string: notes.joined(separator: "\n"))
                attachment.name = "notes-\(screen)__\(variant.name)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    /// Denetimin tek bir bulgusu. `text` raporda görünen satırdır: elementli bulgularda etiket ve çerçeve,
    /// elementsizlerde denetimin ayrıntı metni de yazılır ki ekrandaki yeri bulunabilsin (#59).
    private struct AuditFinding {
        let text: String
        let key: String
        let frame: CGRect?
        let isContrast: Bool
        let isDynamicType: Bool
        var hasElement: Bool { frame != nil }
    }

    /// Denetimi koşar ve bulguları hata saymadan toplar.
    @MainActor
    private static func audit(_ app: XCUIApplication) throws -> [AuditFinding] {
        var findings: [AuditFinding] = []
        try app.performAccessibilityAudit { issue in
            let frame = issue.element?.frame
            let text: String
            if let element = issue.element {
                let box = element.frame
                text = "\(issue.compactDescription) — '\(element.label)' frame \(box.integral.debugDescription)"
            } else {
                text = "\(issue.compactDescription) — screen (\(issue.detailedDescription))"
            }
            let key = issue.element.map { "\($0.label)@\($0.frame.integral)" } ?? "screen:\(issue.detailedDescription)"
            findings.append(AuditFinding(
                text: text, key: "\(issue.auditType.rawValue)|\(key)", frame: frame,
                isContrast: issue.auditType == .contrast,
                isDynamicType: issue.auditType == .dynamicType
            ))
            return true
        }
        return findings
    }

    /// Durum çubuğu bandına taşan metinlerin etiketleri (elementsiz kontrast bulgularını açıklamak için).
    @MainActor
    private static func labelsUnderStatusBar(in app: XCUIApplication) -> [String] {
        let window = app.windows.firstMatch.frame
        let statusBar = app.statusBars.firstMatch
        let height = statusBar.exists && !statusBar.frame.isEmpty ? statusBar.frame.maxY - window.minY : 54
        let band = CGRect(x: window.minX, y: window.minY, width: window.width, height: height)
        // Tek bir `snapshot()` ile ağaç bellekte gezilir; öğe öğe sorgu AX5'te bölüm başına ~60 sn sürüyordu.
        guard let root = try? app.snapshot() else { return [] }
        let types: Set<XCUIElement.ElementType> = [.staticText, .button, .cell, .other]
        var labels: [String] = []
        func visit(_ node: any XCUIElementSnapshot) {
            if types.contains(node.elementType), !node.label.isEmpty, !node.frame.isEmpty,
               node.frame.intersects(band), node.frame.height < 100 {
                labels.append("'\(node.label)'")
            }
            node.children.forEach(visit)
        }
        visit(root)
        return Array(NSOrderedSet(array: labels)) as? [String] ?? labels
    }

    /// Ekran durana kadar (art arda iki görüntü aynı olana kadar, en fazla ~1,5 sn) bekler ve son görüntüyü döner.
    /// Önceki 0,3 sn × 10 adım koşuyu uzatıyordu (#37).
    @MainActor
    private static func settledScreenshot(of app: XCUIApplication) -> XCUIScreenshot {
        var previous = app.screenshot()
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.15)
            let current = app.screenshot()
            if current.pngRepresentation == previous.pngRepresentation { return current }
            previous = current
        }
        return previous
    }

    /// Sol kenar boşluğundaki (4 pt) birkaç pikselin medyan parlaklığıyla açık/koyu modu doğrular.
    /// Önceden ekranın ortasından tek piksel örnekleniyordu; büyük yazıda bu nokta içeriğe denk geliyordu (#33).
    @MainActor
    private func assertAppearance(of screenshot: XCUIScreenshot, is expected: Appearance, name: String) {
        guard let image = screenshot.image.cgImage else {
            XCTFail("[ui-check] \(name): screenshot could not be read")
            return
        }
        let x = Int(4 * screenshot.image.scale)
        let samples = [0.25, 0.4, 0.55, 0.7, 0.85].compactMap {
            Self.brightness(of: image, x: x, y: Int(Double(image.height) * $0))
        }
        guard !samples.isEmpty else {
            XCTFail("[ui-check] \(name): screenshot could not be read")
            return
        }
        let brightness = samples.sorted()[samples.count / 2]
        let actual: Appearance = brightness < 0.5 ? .dark : .light
        XCTAssertEqual(
            actual, expected,
            "[ui-check] \(name): expected \(expected) appearance, background brightness is \(String(format: "%.2f", brightness))"
        )
    }

    /// Tek bir pikselin 0...1 aralığında ortalama parlaklığı.
    private static func brightness(of image: CGImage, x: Int, y: Int) -> Double? {
        guard let pixelImage = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(pixelImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return (Double(rgba[0]) + Double(rgba[1]) + Double(rgba[2])) / (3 * 255)
    }

    // MARK: - Abonelik hızlı adımları (#190)

    @MainActor
    func testAddSubscriptionFlowAmount() throws {
        try capture(
            screen: "add-subscription-flow-amount",
            launchArguments: ["-ui-sample-data", "-ui-add-subscription-flow-amount"],
            sections: [.top]
        ) { app, variant in
            XCTAssertTrue(
                app.buttons["keypad.digit.1"].waitForExistence(timeout: 5),
                "[ui-check] add-subscription-flow-amount__\(variant.name): keypad not found"
            )
            XCTAssertFalse(
                app.buttons["flow.continue"].isEnabled,
                "[ui-check] add-subscription-flow-amount__\(variant.name): continue must be disabled without an amount"
            )
        }
    }

    @MainActor
    func testAddSubscriptionFlowPeriod() throws {
        try capture(
            screen: "add-subscription-flow-period",
            launchArguments: ["-ui-sample-data", "-ui-add-subscription-flow-period"],
            sections: [.top]
        ) { app, variant in
            XCTAssertTrue(
                app.descendants(matching: .any)["subscriptionFlow.period.chip.0"].waitForExistence(timeout: 5),
                "[ui-check] add-subscription-flow-period__\(variant.name): first period chip not found"
            )
        }
    }

    @MainActor
    func testAddSubscriptionFlowCard() throws {
        try capture(
            screen: "add-subscription-flow-card",
            launchArguments: ["-ui-sample-data", "-ui-add-subscription-flow-card"],
            sections: [.top, .scrolled(to: "cardPicker.newCard", named: "new-card")]
        ) { app, variant in
            XCTAssertTrue(
                app.descendants(matching: .any)["cardPicker.noCard"].waitForExistence(timeout: 5),
                "[ui-check] add-subscription-flow-card__\(variant.name): 'No card' row not found"
            )
            XCTAssertTrue(
                app.descendants(matching: .any)["cardPicker.newCard"].exists,
                "[ui-check] add-subscription-flow-card__\(variant.name): 'New card' row not found"
            )
        }
    }

    @MainActor
    func testAddSubscriptionFlowTitle() throws {
        try capture(
            screen: "add-subscription-flow-title",
            launchArguments: ["-ui-sample-data", "-ui-add-subscription-flow-title"],
            sections: [.top, .scrolled(to: "subscriptionFlow.skip", named: "skip")]
        ) { app, variant in
            XCTAssertTrue(
                app.descendants(matching: .any)["subscriptionFlow.title.chip.0"].waitForExistence(timeout: 5),
                "[ui-check] add-subscription-flow-title__\(variant.name): first title chip not found"
            )
            XCTAssertTrue(
                app.descendants(matching: .any)["subscriptionFlow.skip"].exists,
                "[ui-check] add-subscription-flow-title__\(variant.name): Skip button not found"
            )
        }
    }

    @MainActor
    func testAddSubscriptionFlowSummary() throws {
        try capture(
            screen: "add-subscription-flow-summary",
            launchArguments: ["-ui-sample-data", "-ui-add-subscription-flow-summary"],
            sections: [.top, .scrolled(to: "subscriptionFlow.save", named: "save")]
        ) { app, variant in
            XCTAssertTrue(
                app.descendants(matching: .any)["subscriptionFlow.summary"].waitForExistence(timeout: 5),
                "[ui-check] add-subscription-flow-summary__\(variant.name): summary not found"
            )
            XCTAssertTrue(
                app.buttons["subscriptionFlow.save"].isEnabled,
                "[ui-check] add-subscription-flow-summary__\(variant.name): save must be enabled with the sample amount"
            )
        }
    }

    @MainActor
    func testAddOneTimeFlowAmount() throws {
        try capture(
            screen: "add-onetime-flow-amount",
            launchArguments: ["-ui-sample-data", "-ui-add-onetime-flow-amount"],
            sections: [.top]
        ) { app, variant in
            XCTAssertTrue(
                app.buttons["keypad.digit.1"].waitForExistence(timeout: 5),
                "[ui-check] add-onetime-flow-amount__\(variant.name): keypad not found"
            )
            XCTAssertFalse(
                app.buttons["flow.continue"].isEnabled,
                "[ui-check] add-onetime-flow-amount__\(variant.name): continue must be disabled without an amount"
            )
        }
    }

    @MainActor
    func testAddOneTimeFlowDate() throws {
        try capture(
            screen: "add-onetime-flow-date",
            launchArguments: ["-ui-sample-data", "-ui-add-onetime-flow-date"],
            sections: [.top]
        ) { app, variant in
            for index in 0..<3 {
                XCTAssertTrue(
                    app.descendants(matching: .any)["oneTimeFlow.date.chip.\(index)"].waitForExistence(timeout: 5),
                    "[ui-check] add-onetime-flow-date__\(variant.name): date chip \(index) not found"
                )
            }
        }
    }

    @MainActor
    func testAddOneTimeFlowCard() throws {
        try capture(
            screen: "add-onetime-flow-card",
            launchArguments: ["-ui-sample-data", "-ui-add-onetime-flow-card"],
            sections: [.top, .scrolled(to: "cardPicker.newCard", named: "new-card")]
        ) { app, variant in
            XCTAssertTrue(
                app.descendants(matching: .any)["cardPicker.noCard"].waitForExistence(timeout: 5),
                "[ui-check] add-onetime-flow-card__\(variant.name): 'No card' row not found"
            )
            XCTAssertTrue(
                app.descendants(matching: .any)["cardPicker.newCard"].exists,
                "[ui-check] add-onetime-flow-card__\(variant.name): 'New card' row not found"
            )
        }
    }

    @MainActor
    func testAddOneTimeFlowTitle() throws {
        try capture(
            screen: "add-onetime-flow-title",
            launchArguments: ["-ui-sample-data", "-ui-add-onetime-flow-title"],
            sections: [.top, .scrolled(to: "oneTimeFlow.skip", named: "skip")]
        ) { app, variant in
            XCTAssertTrue(
                app.descendants(matching: .any)["oneTimeFlow.title.chip.0"].waitForExistence(timeout: 5),
                "[ui-check] add-onetime-flow-title__\(variant.name): first title chip not found"
            )
            XCTAssertTrue(
                app.descendants(matching: .any)["oneTimeFlow.skip"].exists,
                "[ui-check] add-onetime-flow-title__\(variant.name): Skip button not found"
            )
        }
    }

    @MainActor
    func testAddOneTimeFlowSummary() throws {
        try capture(
            screen: "add-onetime-flow-summary",
            launchArguments: ["-ui-sample-data", "-ui-add-onetime-flow-summary"],
            sections: [.top, .scrolled(to: "oneTimeFlow.save", named: "save")]
        ) { app, variant in
            XCTAssertTrue(
                app.descendants(matching: .any)["oneTimeFlow.summary"].waitForExistence(timeout: 5),
                "[ui-check] add-onetime-flow-summary__\(variant.name): summary not found"
            )
            XCTAssertTrue(
                app.buttons["oneTimeFlow.save"].isEnabled,
                "[ui-check] add-onetime-flow-summary__\(variant.name): save must be enabled with the sample amount"
            )
        }
    }

    @MainActor
    func testEditOneTimePaymentForm() throws {
        // Dolu tek seferlik ödeme formu.
        try capture(
            screen: "edit-onetime",
            launchArguments: ["-ui-sample-data", "-ui-edit-onetime"],
            sections: [.top, .scrolled(to: "editOneTime.delete", named: "delete")]
        ) { app, variant in
            XCTAssertTrue(
                app.textFields["editOneTime.title"].waitForExistence(timeout: 5),
                "[ui-check] edit-onetime__\(variant.name): title field not found"
            )
            XCTAssertTrue(
                app.buttons["editOneTime.save"].isEnabled,
                "[ui-check] edit-onetime__\(variant.name): save must be enabled with the saved values"
            )
        }
    }

    @MainActor
    func testEditOneTimePaymentDeleteConfirmation() throws {
        // Tek seferlik ödeme silme onayı açık.
        try capture(
            screen: "edit-onetime-confirm",
            launchArguments: ["-ui-sample-data", "-ui-edit-onetime"],
            sections: [.top]
        ) { app, variant in
            let delete = revealDelete(prefix: "editOneTime", in: app)
            XCTAssertTrue(delete.exists, "[ui-check] edit-onetime-confirm__\(variant.name): delete button not found")
            delete.tap()
            XCTAssertTrue(
                app.buttons["editOneTime.delete.confirm"].firstMatch.waitForExistence(timeout: 5),
                "[ui-check] edit-onetime-confirm__\(variant.name): confirmation not shown"
            )
        }
    }
}
