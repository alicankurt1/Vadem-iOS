import Foundation
import Testing
@testable import VademFeatures

@Suite("Gallery add button label")
struct GalleryButtonLabelTests {

    static var label: String { DesignGalleryView.addButtonAccessibilityLabel }

    // Denetim "₺" içeren etiketleri işaretliyordu (#33 nit); etiket boş kalmamalı.
    @Test("Label is not empty")
    func notEmpty() {
        #expect(!Self.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("Label has no ₺ symbol")
    func noSymbol() {
        #expect(!Self.label.contains("₺"), "label: \(Self.label)")
    }

    // Tutar okunabilir biçimde, rakamlarla yer almalı: 100 (ör. "100" ya da "100,00").
    @Test("Label contains the amount 100 in digits")
    func containsAmount() {
        #expect(Self.label.contains("100"), "label: \(Self.label)")
        // "1.000" veya "10.000" gibi başka bir tutar olmamalı.
        #expect(!Self.label.contains("1.00"), "label: \(Self.label)")
        #expect(!Self.label.contains("1000"), "label: \(Self.label)")
    }

    // Düğmenin eylemi ("Add") ve para birimi okunur adıyla (lira) etikette kalmalı.
    @Test("Label keeps the action and names the currency in words")
    func actionAndCurrency() {
        #expect(Self.label.localizedCaseInsensitiveContains("add"), "label: \(Self.label)")
        #expect(Self.label.localizedCaseInsensitiveContains("lira"), "label: \(Self.label)")
    }
}
