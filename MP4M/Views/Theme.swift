import SwiftUI

// MP4M カラーパレット (X68000 CRT モニター風)
extension Color {
    static let mp4mBackground = Color(red: 0.02, green: 0.02, blue: 0.04)
    static let mp4mText       = Color(red: 0.80, green: 0.90, blue: 0.80)
    static let mp4mBright     = Color(red: 0.20, green: 1.00, blue: 0.40)
    static let mp4mDim        = Color(red: 0.10, green: 0.30, blue: 0.15)
    static let mp4mPeak       = Color(red: 0.90, green: 0.80, blue: 0.20)
    static let mp4mBorder     = Color(red: 0.15, green: 0.25, blue: 0.15)
    static let mp4mCyan       = Color(red: 0.20, green: 0.90, blue: 0.90)
    static let mp4mAmber      = Color(red: 1.00, green: 0.60, blue: 0.10)
    static let mp4mSelected   = Color(red: 0.05, green: 0.20, blue: 0.10)
}

// ドットフォント (KH-Dot-Kodenmachou-16) / フォールバックは SF Mono
extension Font {
    private static let dotFontName = "KH-Dot-Kodenmachou-16-Ki"

    static let mp4mTitle = Font.custom(dotFontName, size: 21).bold()
    static let mp4mText  = Font.custom(dotFontName, size: 18)
    static let mp4mMono  = Font.custom(dotFontName, size: 18)
    static let mp4mSmall = Font.custom(dotFontName, size: 15)
    static let mp4mTiny  = Font.custom(dotFontName, size: 14)
}
