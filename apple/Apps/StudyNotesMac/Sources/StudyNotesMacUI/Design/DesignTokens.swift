import AppKit
import StudyNotesKit
import StudyNotesKit
import SwiftUI

public enum SNColor {
    public static let onAccent = Color.white
    public static let white = adaptive(
        light: rgb(1, 1, 1),
        dark: rgb(0.105, 0.11, 0.125)
    )
    public static let ink = adaptive(
        light: rgb(0.114, 0.129, 0.161),
        dark: rgb(0.94, 0.945, 0.965)
    )
    public static let text = adaptive(
        light: rgb(0.306, 0.349, 0.412),
        dark: rgb(0.76, 0.78, 0.82)
    )
    public static let muted = adaptive(
        light: rgb(0.525, 0.565, 0.612),
        dark: rgb(0.58, 0.6, 0.64)
    )
    public static let border = adaptive(
        light: rgb(0.898, 0.902, 0.922),
        dark: rgb(0.23, 0.24, 0.27)
    )
    public static let nav = adaptive(
        light: rgb(0.969, 0.973, 0.980),
        dark: rgb(0.14, 0.15, 0.17)
    )
    public static let panel = adaptive(
        light: rgb(0.980, 0.984, 0.988),
        dark: rgb(0.125, 0.133, 0.15)
    )
    public static let blue = adaptive(
        light: rgb(0.2, 0.439, 1),
        dark: rgb(0.42, 0.62, 1)
    )
    public static let blueSoft = adaptive(
        light: rgb(0.941, 0.961, 1),
        dark: rgb(0.16, 0.22, 0.34)
    )
    public static let blueLine = adaptive(
        light: rgb(0.788, 0.847, 1),
        dark: rgb(0.31, 0.42, 0.62)
    )
    public static let yellow = adaptive(
        light: rgb(1, 0.969, 0.839),
        dark: rgb(0.3, 0.265, 0.15)
    )
    public static let yellowLine = adaptive(
        light: rgb(0.945, 0.847, 0.529),
        dark: rgb(0.63, 0.52, 0.22)
    )
    public static let green = adaptive(
        light: rgb(0, 0.706, 0.165),
        dark: rgb(0.28, 0.82, 0.43)
    )
    public static let greenSoft = adaptive(
        light: rgb(0.91, 1, 0.918),
        dark: rgb(0.13, 0.27, 0.18)
    )
    public static let red = adaptive(
        light: rgb(0.961, 0.247, 0.247),
        dark: rgb(1, 0.42, 0.42)
    )
    public static let redSoft = adaptive(
        light: rgb(1, 0.933, 0.933),
        dark: rgb(0.31, 0.15, 0.16)
    )
    public static let orange = adaptive(
        light: rgb(0.902, 0.494, 0.133),
        dark: rgb(1, 0.65, 0.26)
    )
    public static let orangeSoft = adaptive(
        light: rgb(1, 0.957, 0.902),
        dark: rgb(0.3, 0.22, 0.13)
    )
    public static let purpleSoft = adaptive(
        light: rgb(0.961, 0.949, 1),
        dark: rgb(0.24, 0.19, 0.31)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? dark
                    : light
            }
        )
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

public enum SNRadius {
    public static let small: CGFloat = 4
    public static let control: CGFloat = 6
    public static let panel: CGFloat = 7
    public static let maximum: CGFloat = 8
}

public enum SNMetric {
    public static let toolbarHeight: CGFloat = 56
    public static let sidebarWidth = CGFloat(WorkspacePreferences.defaultLibraryWidth)
    public static let materialListWidth = CGFloat(WorkspacePreferences.defaultMaterialsWidth)
    public static let studyPanelWidth = CGFloat(WorkspacePreferences.defaultStudyWidth)
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
