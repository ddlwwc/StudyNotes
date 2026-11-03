import SwiftUI

public enum SNColor {
    public static let white = Color(red: 1.0, green: 1.0, blue: 1.0)
    public static let ink = Color(red: 0.114, green: 0.129, blue: 0.161)
    public static let text = Color(red: 0.306, green: 0.349, blue: 0.412)
    public static let muted = Color(red: 0.525, green: 0.565, blue: 0.612)
    public static let border = Color(red: 0.898, green: 0.902, blue: 0.922)
    public static let nav = Color(red: 0.969, green: 0.973, blue: 0.980)
    public static let panel = Color(red: 0.980, green: 0.984, blue: 0.988)
    public static let blue = Color(red: 0.200, green: 0.439, blue: 1.0)
    public static let blueSoft = Color(red: 0.941, green: 0.961, blue: 1.0)
    public static let blueLine = Color(red: 0.788, green: 0.847, blue: 1.0)
    public static let yellow = Color(red: 1.0, green: 0.969, blue: 0.839)
    public static let yellowLine = Color(red: 0.945, green: 0.847, blue: 0.529)
    public static let green = Color(red: 0.0, green: 0.706, blue: 0.165)
    public static let greenSoft = Color(red: 0.910, green: 1.0, blue: 0.918)
    public static let red = Color(red: 0.961, green: 0.247, blue: 0.247)
    public static let redSoft = Color(red: 1.0, green: 0.933, blue: 0.933)
    public static let orange = Color(red: 0.902, green: 0.494, blue: 0.133)
    public static let orangeSoft = Color(red: 1.0, green: 0.957, blue: 0.902)
    public static let purpleSoft = Color(red: 0.961, green: 0.949, blue: 1.0)
}

public enum SNRadius {
    public static let small: CGFloat = 4
    public static let control: CGFloat = 6
    public static let panel: CGFloat = 7
    public static let maximum: CGFloat = 8
}

public enum SNMetric {
    public static let toolbarHeight: CGFloat = 56
    public static let sidebarWidth: CGFloat = 184
    public static let materialListWidth: CGFloat = 276
    public static let studyPanelWidth: CGFloat = 260
    public static let minimumWindowWidth: CGFloat = 1_180
    public static let minimumWindowHeight: CGFloat = 760
    public static let readingContentWidth: CGFloat = 720
}

public extension Font {
    static func sn(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func snReading(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}
