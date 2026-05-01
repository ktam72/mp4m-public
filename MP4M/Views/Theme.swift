import SwiftUI

// MMDSP カラーパレット (X68000 CRT モニター風)
extension Color {
    static let mmdspBackground = Color(red: 0.02, green: 0.02, blue: 0.04)
    static let mmdspText       = Color(red: 0.80, green: 0.90, blue: 0.80)
    static let mmdspBright     = Color(red: 0.20, green: 1.00, blue: 0.40)
    static let mmdspDim        = Color(red: 0.10, green: 0.30, blue: 0.15)
    static let mmdspPeak       = Color(red: 0.90, green: 0.80, blue: 0.20)
    static let mmdspBorder     = Color(red: 0.15, green: 0.25, blue: 0.15)
    static let mmdspCyan       = Color(red: 0.20, green: 0.90, blue: 0.90)
    static let mmdspAmber      = Color(red: 1.00, green: 0.60, blue: 0.10)
    static let mmdspSelected   = Color(red: 0.05, green: 0.20, blue: 0.10)
}

// ドットフォント (KH-Dot-Kodenmachou-16) / フォールバックは SF Mono
extension Font {
    private static let dotFontName = "KH-Dot-Kodenmachou-16-Ki"

    static let mmdspTitle = Font.custom(dotFontName, size: 14).bold()
    static let mmdspText  = Font.custom(dotFontName, size: 12)
    static let mmdspMono  = Font.custom(dotFontName, size: 12)
    static let mmdspSmall = Font.custom(dotFontName, size: 10)
    static let mmdspTiny  = Font.custom(dotFontName, size: 9)
}
