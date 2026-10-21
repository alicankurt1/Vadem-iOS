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

    /// Bu koşuda yakalanacak varyantlar: script bir görünüm verdiyse sadece onunkiler.
    static var variants: [Variant] {
        guard let active = activeAppearance else { return allVariants }
        return allVariants.filter { $0.appearance == active }
    }

    override func setUpWithError() throws {
        // Bir varyant hata verse de diğerlerinin görüntüsü alınsın.
        continueAfterFailure = true
    }

    @MainActor
    func testRootScreen() throws {
        try capture(screen: "root") { app, variant in
            // Kök ekran açılışta görünür; gezinme gerekmez. Sürüm etiketi kontrolleri (#10).
            Self.assertVersionLabel(in: app, name: "root__\(variant.name)")
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
    func testGalleryScreen() throws {
        // Galeri uzun bir ekran; başlık, çipler, tutarlar ve kartlar ayrı görüntülerde yakalanır (#33).
        // Her kart yüzü kendi parçasında en üste kaydırılır; AX5'te de hiçbir yüz atlanmaz (#36).
        let cardParts: [Section] = ["night", "ocean", "emerald", "sunset", "lavender", "graphite"].map {
            .scrolled(to: "gallery.card.\($0)", named: "card-\($0)")
        }
        try capture(
            screen: "gallery",
            launchArguments: ["-ui-gallery"],
            sections: [
                .top,
                .scrolled(to: "gallery.chips", named: "chips"),
                .scrolled(to: "gallery.amounts", named: "amounts"),
            ] + cardParts
        ) { app, variant in
            XCTAssertTrue(
                app.staticTexts["Design gallery"].waitForExistence(timeout: 5),
                "[ui-check] gallery__\(variant.name): 'Design gallery' title not found"
            )
        }
    }

    /// Sürüm etiketi görünür, "Version x.y.z" biçiminde, dokunulabilir ve başlığın altında,
    /// başlıktan daha küçük olmalı (ikincil bilgi hiyerarşisi).
    @MainActor
    private static func assertVersionLabel(in app: XCUIApplication, name: String) {
        let title = app.staticTexts["Vadem"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "[ui-check] \(name): 'Vadem' title not found")

        let version = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Version ")).firstMatch
        guard version.waitForExistence(timeout: 5) else {
            XCTFail("[ui-check] \(name): version label ('Version …') not found")
            return
        }

        // Etiketin tamamı eşleşmeli; önek/sonek ("v", fazladan metin) kabul edilmez.
        let label = version.label
        XCTAssertNotNil(
            label.wholeMatch(of: /Version [0-9]+(\.[0-9]+)*/),
            "[ui-check] \(name): version label '\(label)' does not match ^Version [0-9]+(\\.[0-9]+)*$"
        )
        XCTAssertTrue(version.isHittable, "[ui-check] \(name): version label is not hittable")

        guard title.exists else { return }
        let titleFrame = title.frame
        let versionFrame = version.frame
        XCTAssertGreaterThanOrEqual(
            versionFrame.minY, titleFrame.maxY,
            "[ui-check] \(name): version label top (\(versionFrame.minY)) is above title bottom (\(titleFrame.maxY))"
        )
        XCTAssertLessThan(
            versionFrame.height, titleFrame.height,
            "[ui-check] \(name): version label height (\(versionFrame.height)) is not smaller than title height (\(titleFrame.height))"
        )
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

                for _ in 0..<12 {
                    attempts += 1
                    guard element.exists else {
                        app.swipeUp(velocity: .fast)
                        continue
                    }
                    // Büyük başlık kaydırınca küçülür; çubuğun alt kenarı her adımda yeniden okunur.
                    target = max(window.minY + window.height * 0.15, barBottom(in: app) + 8)
                    let minY = element.frame.minY
                    let distance = minY - target
                    // Hedef bir bant: çubuğun hemen altından ekranın yarısına kadar. Dar tolerans (%5)
                    // sürüklemeyi ileri geri salındırıyordu; her sürükleme ~3 sn sürüyor (#37).
                    if minY >= target - 8, minY <= target + window.height * 0.35 { break }
                    // İçerik sonu: öğe artık yer değiştirmiyor, daha fazla sürüklemek boşa zaman.
                    if let previousMinY, abs(previousMinY - minY) < 1 { break }
                    previousMinY = minY
                    // Öğeyi parmakla tutup hedef bandın ortasına sürükle; tek seferde ekranın en fazla yarısı.
                    // İçerik sürüklenenden fazla kayıyor (büyük başlık daralıp genişliyor, az da olsa
                    // momentum); bu yüzden adım kısaltılır ve sonda beklenir (#37).
                    let wanted = (distance - window.height * 0.15) * 0.75
                    let step = max(-window.height * 0.5, min(window.height * 0.5, wanted))
                    let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: step > 0 ? 0.8 : 0.3))
                    let to = from.withOffset(CGVector(dx: 0, dy: -step))
                    from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 0.2)
                }

                // İçerik sonuna gelindiyse öğe hedefe çıkamayabilir; çubuğun altında görünür olması yeter.
                let bar = barBottom(in: app)
                let frame = element.exists ? element.frame : .zero
                if element.exists, element.isHittable, frame.midY > bar, frame.minY < window.maxY { return nil }
                return "marker '\(marker)' not reached after \(attempts) attempts — exists: \(element.exists), "
                    + "hittable: \(element.exists && element.isHittable), marker frame: \(frame), "
                    + "bar bottom: \(bar), target y: \(target)"
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
            let app = XCUIApplication()
            app.launchArguments += Self.commonLaunchArguments + launchArguments
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", variant.contentSize]
            app.launch()
            defer { app.terminate() }
            navigate(app, variant)

            var notes: [String] = []
            var previous: (name: String, png: Data)?

            for section in sections {
                let shot = section.name.isEmpty ? screen : "\(screen)-\(section.name)"
                let name = "\(shot)__\(variant.name)"

                if let reason = section.reach(app) {
                    XCTFail("[ui-check] \(name): section '\(section.name)' could not be scrolled into view — \(reason)")
                    continue
                }

                // Kaydırma göstergesi gibi kısa animasyonlar bitmeden denetim zaman aşımına uğruyordu (#33).
                let screenshot = Self.settledScreenshot(of: app)
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
                do {
                    try app.performAccessibilityAudit { issue in
                        let element = issue.element.map { "'\($0.label)'" } ?? "screen"
                        if let frame = issue.element?.frame, !frame.isEmpty, !visible.contains(frame) {
                            notes.append("[a11y-hidden] \(name): \(issue.compactDescription) — \(element) (not fully visible)")
                        } else {
                            XCTFail("[a11y] \(name): \(issue.compactDescription) — \(element)")
                        }
                        return true
                    }
                } catch {
                    XCTFail("[a11y] \(name): audit did not complete — \(error.localizedDescription)")
                }
            }

            if !notes.isEmpty {
                let attachment = XCTAttachment(string: notes.joined(separator: "\n"))
                attachment.name = "notes-\(screen)__\(variant.name)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
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
}
