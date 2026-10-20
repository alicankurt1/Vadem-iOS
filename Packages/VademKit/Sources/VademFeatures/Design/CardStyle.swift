import Foundation
import SwiftUI

/// A card face preset: a 3×3 mesh gradient with readable white text.
public enum CardStyle: String, CaseIterable, Sendable {
    case night
    case ocean
    case emerald
    case sunset
    case lavender
    case graphite

    /// A deterministic style for a card until users can pick one.
    ///
    /// Derived from the UUID bytes (FNV-1a), so the same id gives the same style
    /// on every launch. `hashValue` is not used because it is seeded per process.
    public static func `default`(for id: UUID) -> CardStyle {
        // FNV-1a 64-bit: tüm 16 bayt karışır, sabit sürüm/varyant bitleri dağılımı bozmaz.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        withUnsafeBytes(of: id.uuid) { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash &*= 0x0000_0100_0000_01b3
            }
        }
        return allCases[Int(hash % UInt64(allCases.count))]
    }

    /// Display name, used in the gallery.
    public var name: String {
        rawValue.capitalized
    }

    /// Text and icon color on this face. Every mesh color has at least 4.5:1 contrast with it.
    public var foreground: Color { Color(hex: foregroundHex) }

    /// The nine mesh colors, row by row (top-left to bottom-right).
    public var meshColors: [Color] {
        meshHexes.map(Color.init(hex:))
    }

    /// The nine mesh colors as `0xRRGGBB`, row by row; the data behind ``meshColors``.
    /// Text on the face is ``foreground`` (white), so ``foregroundHex`` is its value.
    var meshHexes: [UInt32] {
        // Tüm tonların beyazla kontrastı ≥ 4.5:1 (WCAG AA, normal metin) olacak şekilde seçildi.
        switch self {
        case .night:
            [0x0F172A, 0x1E1B4B, 0x172554, 0x312E81, 0x1E3A8A, 0x3730A3, 0x0B1120, 0x1E1B4B, 0x4338CA]
        case .ocean:
            [0x0C4A6E, 0x075985, 0x0E7490, 0x1E3A8A, 0x0369A1, 0x155E75, 0x172554, 0x0C4A6E, 0x115E59]
        case .emerald:
            [0x064E3B, 0x065F46, 0x047857, 0x134E4A, 0x0F766E, 0x065F46, 0x022C22, 0x064E3B, 0x115E59]
        case .sunset:
            [0x7C2D12, 0x9A3412, 0x9F1239, 0x881337, 0xC2410C, 0xBE123C, 0x4C0519, 0x7C2D12, 0x9D174D]
        case .lavender:
            [0x4C1D95, 0x5B21B6, 0x6D28D9, 0x581C87, 0x7C3AED, 0x86198F, 0x3B0764, 0x4C1D95, 0x701A75]
        case .graphite:
            [0x18181B, 0x27272A, 0x1F2937, 0x3F3F46, 0x374151, 0x52525B, 0x111827, 0x27272A, 0x334155]
        }
    }

    /// ``foreground`` as `0xRRGGBB`, for contrast checks against ``meshHexes``.
    var foregroundHex: UInt32 { 0xFFFFFF }
}

extension Color {
    // 0xRRGGBB biçiminden sRGB renk.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
