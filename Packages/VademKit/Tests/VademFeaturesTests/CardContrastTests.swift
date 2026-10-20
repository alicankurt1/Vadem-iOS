import Foundation
import Testing
@testable import VademFeatures

@Suite("Card face contrast")
struct CardContrastTests {

    @Test("Every style has a 3×3 mesh")
    func meshSize() {
        for style in CardStyle.allCases {
            #expect(style.meshHexes.count == 9, "\(style): expected 9 mesh colors")
        }
    }

    // Metin kartın her noktasında okunmalı: 9 mesh renginin her biri ön plan rengine karşı
    // WCAG 2.x normal metin eşiğini (4,5:1) geçmeli. Hesap uygulamadan bağımsız, burada yapılır.
    @Test("Foreground text meets WCAG AA (4.5:1) on every mesh color", arguments: CardStyle.allCases)
    func foregroundContrast(style: CardStyle) {
        for (index, hex) in style.meshHexes.enumerated() {
            let ratio = Self.contrast(hex, style.foregroundHex)
            #expect(
                ratio >= 4.5,
                "\(style) mesh[\(index)] \(String(format: "%06X", hex)): contrast \(String(format: "%.2f", ratio)) < 4.5"
            )
        }
    }

    // Denetim, metnin gerçekten çizildiği rengi ölçer (#36): başlık ve alt başlığın altındaki
    // bandın her durağı metin rengine karşı en az 5:1 olmalı. WCAG eşiği 4,5:1; 4,5'e yakın
    // değerler denetimde parçadan parçaya geçip kalabildiği için 0,5 pay bırakılır.
    // Ortalama değil, her durak tek tek ölçülür. Oran burada bağımsız hesaplanır.
    static let textBandMinimumContrast = 5.0

    @Test("Card title and subtitle have at least 5:1 contrast on every text band stop", arguments: CardStyle.allCases)
    func textBackgroundContrast(style: CardStyle) {
        for (index, hex) in style.textBackgroundHexes.enumerated() {
            let ratio = Self.contrast(hex, style.foregroundHex)
            #expect(
                ratio >= Self.textBandMinimumContrast,
                "\(style) band[\(index)] \(String(format: "%06X", hex)) vs foreground \(String(format: "%06X", style.foregroundHex)): contrast \(String(format: "%.2f", ratio)) < 5.0"
            )
        }
    }

    // Bant boş olursa yukarıdaki döngü hiçbir şey ölçmeden geçer. Bant, metnin oturduğu
    // alt mesh satırından (3 renk, soldan sağa) boyanır; kart yüzüyle uyumu da buna bağlı.
    @Test("Text band uses the mesh's bottom row, left to right", arguments: CardStyle.allCases)
    func textBandIsBottomRow(style: CardStyle) throws {
        try #require(style.meshHexes.count == 9, "\(style): expected a 3×3 mesh")
        #expect(style.textBackgroundHexes.count == 3, "\(style): expected 3 band colors")
        #expect(
            style.textBackgroundHexes == [style.meshHexes[6], style.meshHexes[7], style.meshHexes[8]],
            "\(style): band colors are not the mesh's bottom row"
        )
    }

    // Değer `0xRRGGBB` aralığında olmalı; fazladan bit (ör. alfa) hesabı sessizce bozar.
    @Test("Text background is a plain 24-bit RGB value", arguments: CardStyle.allCases)
    func textBackgroundRange(style: CardStyle) {
        for hex in style.textBackgroundHexes {
            #expect(hex <= 0xFFFFFF, "\(style): text background has bits above 0xFFFFFF")
        }
        #expect(style.foregroundHex <= 0xFFFFFF, "\(style): foreground has bits above 0xFFFFFF")
    }

    // Hesaplayıcının kendisi bilinen değerlerle doğrulanır; yanlış bir formül testi boşa düşürmesin.
    @Test("Contrast helper matches known WCAG values", arguments: [
        (UInt32(0x000000), UInt32(0xFFFFFF), 21.0),
        (UInt32(0xFFFFFF), UInt32(0xFFFFFF), 1.0),
        (UInt32(0x777777), UInt32(0xFFFFFF), 4.48),
        (UInt32(0x767676), UInt32(0xFFFFFF), 4.54),
    ])
    func helper(a: UInt32, b: UInt32, expected: Double) {
        #expect(abs(Self.contrast(a, b) - expected) < 0.01)
    }

    // MARK: - WCAG 2.x

    /// sRGB kanalını (0...255) doğrusal değere çevirir.
    static func linear(_ channel: UInt32) -> Double {
        let c = Double(channel) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// `0xRRGGBB` renginin bağıl parlaklığı.
    static func luminance(_ hex: UInt32) -> Double {
        let r = linear((hex >> 16) & 0xFF)
        let g = linear((hex >> 8) & 0xFF)
        let b = linear(hex & 0xFF)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// İki renk arasındaki kontrast oranı (1...21).
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
