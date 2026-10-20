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
    func testGalleryScreen() throws {
        // Galeri uzun bir ekran; başlık, çipler, tutarlar ve kartlar ayrı görüntülerde yakalanır (#33).
        try capture(
            screen: "gallery",
            launchArguments: ["-ui-gallery"],
            sections: [
                .top,
                .scrolled(to: "gallery.chips", named: "chips"),
                .scrolled(to: "gallery.amounts", named: "amounts"),
                .scrolled(to: "gallery.cards", named: "cards"),
                // Bir ekrana ~3 kart sığar; altı kart yüzünün hepsi en az bir görüntüde olmalı.
                // Graphite son kart; AX5'te iri metinle de görünsün diye ayrıca yakalanır.
                .scrolled(to: "gallery.card.night", named: "cards-2"),
                .scrolled(to: "gallery.card.sunset", named: "cards-3"),
                .scrolled(to: "gallery.card.graphite", named: "cards-4"),
            ]
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
        let show: @MainActor (XCUIApplication) -> Bool

        /// Açılışta görünen kısım.
        static var top: Section { Section(name: "") { _ in true } }

        /// Kimliği (accessibilityIdentifier) ya da etiketi `marker` olan öğeyi ekranın üst kısmına
        /// (yüksekliğin ~%15'i) getirir. Sadece "görünür" olunca durmak yetmiyordu: tek kaydırma birden
        /// fazla başlığı görünür yapınca farklı bölümler aynı görüntüyü veriyordu (#33).
        static func scrolled(to marker: String, named name: String) -> Section {
            Section(name: name) { app in
                let element = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier == %@ OR label == %@", marker, marker))
                    .firstMatch
                let window = app.windows.firstMatch.frame
                let target = window.minY + window.height * 0.15

                for _ in 0..<20 {
                    guard element.exists else {
                        app.swipeUp()
                        continue
                    }
                    let distance = element.frame.minY - target
                    if abs(distance) < window.height * 0.05 { break }
                    // Öğeyi parmakla tutup hedef yüksekliğe sürükle; tek seferde ekranın en fazla yarısı.
                    let step = max(-window.height * 0.5, min(window.height * 0.5, distance))
                    let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                    let to = from.withOffset(CGVector(dx: 0, dy: -step))
                    from.press(forDuration: 0.05, thenDragTo: to)
                }
                // İçerik sonuna gelindiyse öğe hedefe çıkamayabilir; görünür olması yeter.
                return element.exists && element.isHittable
            }
        }
    }

    /// Uygulamayı her varyantta açar; `navigate` ile (uygulama, varyant) ekrana gider; her bölüm için
    /// görüntü alır, görünümü doğrular ve erişilebilirlik denetimini koşar.
    /// Bir varyantta denetim hata verse bile sonraki bölüm ve varyantlara devam eder.
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

            for section in sections {
                let shot = section.name.isEmpty ? screen : "\(screen)-\(section.name)"
                let name = "\(shot)__\(variant.name)"

                guard section.show(app) else {
                    XCTFail("[ui-check] \(name): section '\(section.name)' could not be scrolled into view")
                    continue
                }

                // Kaydırma göstergesi gibi kısa animasyonlar bitmeden denetim zaman aşımına uğruyordu (#33).
                let screenshot = Self.settledScreenshot(of: app)
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)

                // Görünüm gerçekten uygulandı mı? Script görünüm verdiyse arka plan parlaklığına bakılır.
                if let expected = Self.activeAppearance {
                    assertAppearance(of: screenshot, is: expected, name: name)
                }

                // Her sorun ayrı bir test hatası olur. Denetimin kendisi hata verirse (ör. zaman aşımı)
                // raporlanır ve döngü devam eder; önceden bu durumda kalan varyantlar hiç yakalanmıyordu.
                do {
                    try app.performAccessibilityAudit { issue in
                        let element = issue.element.map { "'\($0.label)'" } ?? "screen"
                        XCTFail("[a11y] \(name): \(issue.compactDescription) — \(element)")
                        return true
                    }
                } catch {
                    XCTFail("[a11y] \(name): audit did not complete — \(error.localizedDescription)")
                }
            }
        }
    }

    /// Ekran durana kadar (art arda iki görüntü aynı olana kadar, en fazla ~3 sn) bekler ve son görüntüyü döner.
    @MainActor
    private static func settledScreenshot(of app: XCUIApplication) -> XCUIScreenshot {
        var previous = app.screenshot()
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.3)
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
