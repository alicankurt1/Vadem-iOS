import SwiftUI
import Testing
@testable import VademFeatures

/// Serif başlık ve eyebrow bileşenlerinin biçimi (#211): tek vurgulu sözcük, vurgu yoksa düz metin,
/// başlığın tek parça kalması (VoiceOver tek başlık okur).
@Suite("Display title styling")
@MainActor
struct DisplayTitleTests {

    struct Case: Sendable, CustomTestStringConvertible {
        let title: String
        let accent: String?
        /// Vurgulu olması beklenen metin (yoksa nil).
        let expectedAccented: String?
        var testDescription: String { "\(title) / \(accent ?? "nil")" }
    }

    nonisolated static let cases: [Case] = [
        Case(title: "You pay ₺4.825,50", accent: "₺4.825,50", expectedAccented: "₺4.825,50"),
        Case(title: "Make it yours", accent: "yours", expectedAccented: "yours"),
        Case(title: "Your next 12 months", accent: "12 months", expectedAccented: "12 months"),
        Case(title: "Your cards at a glance", accent: "cards", expectedAccented: "cards"),
        Case(title: "Accent at start", accent: "Accent", expectedAccented: "Accent"),
        Case(title: "Whole", accent: "Whole", expectedAccented: "Whole"),
        // Yalnızca ilk geçiş vurgulanır.
        Case(title: "go go go", accent: "go", expectedAccented: "go"),
        // Vurgu yok, bulunamıyor ya da boş: düz metin.
        Case(title: "Plain title", accent: nil, expectedAccented: nil),
        Case(title: "Plain title", accent: "missing", expectedAccented: nil),
        Case(title: "Plain title", accent: "", expectedAccented: nil),
        Case(title: "", accent: "x", expectedAccented: nil),
        Case(title: "Plain title", accent: "plain", expectedAccented: nil),  // büyük/küçük harf duyarlı
    ]

    @Test("Styled text keeps the full title as one string", arguments: cases)
    func textUnchanged(_ c: Case) {
        let styled = DisplayTitle.styled(c.title, accent: c.accent)
        #expect(String(styled.characters) == c.title)
    }

    @Test("Only the accent phrase is styled", arguments: cases)
    func accentedPart(_ c: Case) {
        let styled = DisplayTitle.styled(c.title, accent: c.accent)
        var accented = ""
        var plain = ""
        for run in styled.runs {
            let text = String(styled[run.range].characters)
            if run.foregroundColor != nil || run.font != nil { accented += text } else { plain += text }
        }
        #expect(accented == (c.expectedAccented ?? ""))
        // Vurgusuz kısımlar, vurgu çıkarılınca kalan metindir.
        var rest = c.title
        if let expected = c.expectedAccented, let range = rest.range(of: expected) { rest.removeSubrange(range) }
        #expect(plain == rest)
    }

    @Test("Accent run is italic serif in the brand text color, the rest is untouched")
    func accentRunAttributes() throws {
        let styled = DisplayTitle.styled("Make it yours", accent: "yours")
        let runs = Array(styled.runs)
        #expect(runs.count == 2)
        #expect(runs[0].foregroundColor == nil && runs[0].font == nil)
        #expect(runs[1].foregroundColor == Color.vademBrand)
        #expect(runs[1].font == DisplayTitle.font.italic())
    }

    @Test("Accent in the middle gives three runs")
    func accentInMiddle() {
        let styled = DisplayTitle.styled("Your next 12 months now", accent: "12 months")
        #expect(styled.runs.count == 3)
    }

    @Test("Accent range is the first occurrence", arguments: [
        ("go go go", "go", 0),
        ("a go go", "go", 2),
        ("Your cards", "cards", 5),
    ])
    func accentRangeFirstOccurrence(title: String, accent: String, offset: Int) throws {
        let range = try #require(DisplayTitle.accentRange(in: title, accent: accent))
        #expect(title.distance(from: title.startIndex, to: range.lowerBound) == offset)
        #expect(title[range] == accent)
    }

    @Test("Accent range is nil for nil, empty or missing accent", arguments: [nil, "", "zzz"] as [String?])
    func accentRangeNil(accent: String?) {
        #expect(DisplayTitle.accentRange(in: "Plain title", accent: accent) == nil)
    }

    @Test("Title font is not a fixed size (scales with Dynamic Type)")
    func fontIsTextStyleBased() {
        #expect(DisplayTitle.font == Font.system(.largeTitle, design: .serif, weight: .semibold))
    }
}

@Suite("Glass surface")
@MainActor
struct GlassSurfaceTests {

    @Test("Tinted surface is nearly opaque so the foreground token keeps its contrast")
    func tintNearlyOpaque() {
        #expect(GlassSurfaceModifier<Capsule>.tintOpacity >= 0.85)
        #expect(GlassSurfaceModifier<Capsule>.tintOpacity <= 1)
    }

    @Test("Untinted surface is translucent but veiled enough to read text")
    func surfaceVeil() {
        let opacity = GlassSurfaceModifier<Capsule>.surfaceOpacity
        #expect(opacity > 0.5)
        #expect(opacity < 1)
    }
}
