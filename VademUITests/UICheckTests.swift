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

    /// Uygulamayı her varyantta açar, `navigate` ile (uygulama, varyant) ekrana gider, görüntü alır ve denetler.
    @MainActor
    private func capture(screen: String, navigate: (XCUIApplication, Variant) -> Void) throws {
        for variant in Self.variants {
            let name = "\(screen)__\(variant.name)"

            let app = XCUIApplication()
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", variant.contentSize]
            app.launch()
            navigate(app, variant)

            let screenshot = app.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)

            // Görünüm gerçekten uygulandı mı? Script görünüm verdiyse arka plan parlaklığına bakılır.
            if let expected = Self.activeAppearance {
                assertAppearance(of: screenshot, is: expected, name: name)
            }

            // Her sorun ayrı bir test hatası olur; mesajında ekran ve varyant yazar.
            try app.performAccessibilityAudit { issue in
                let element = issue.element.map { "'\($0.label)'" } ?? "screen"
                XCTFail("[a11y] \(name): \(issue.compactDescription) — \(element)")
                return true
            }

            app.terminate()
        }
    }

    /// Ekranın alt kısmından, durum çubuğu ve içerikten uzak bir pikselin parlaklığıyla
    /// açık/koyu modu doğrular. Saat gibi değişen öğelerden etkilenmez.
    private func assertAppearance(of screenshot: XCUIScreenshot, is expected: Appearance, name: String) {
        guard let image = screenshot.image.cgImage,
              let brightness = Self.brightness(of: image, x: image.width / 2, y: image.height * 9 / 10)
        else {
            XCTFail("[ui-check] \(name): screenshot could not be read")
            return
        }
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
