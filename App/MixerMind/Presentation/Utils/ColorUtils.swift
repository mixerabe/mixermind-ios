import SwiftUI

extension Color {
    /// Parse a "#RRGGBB" hex string into a SwiftUI Color.
    static func fromHex(_ hex: String) -> Color {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let int = UInt64(h, radix: 16) else {
            return Color(red: 0.11, green: 0.10, blue: 0.16)
        }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
