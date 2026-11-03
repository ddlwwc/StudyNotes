import Foundation

public enum ReadingTheme: String, Codable, Equatable, Sendable {
    case system
    case light
    case dark
}

/// Device-local typography and appearance for long-form reading.
public struct ReadingPreferences: Codable, Equatable, Sendable {
    public static let fontSizeRange = 12.0...24.0
    public static let lineWidthRange = 420.0...900.0
    public static let lineHeightRange = 1.4...2.2

    public static let defaultFontSize = 16.0
    public static let defaultLineWidth = 648.0
    public static let defaultLineHeight = 1.82
    public static let defaultCodeFont = "SFMono-Regular"

    public var theme: ReadingTheme
    /// Prose font size in points.
    public var fontSize: Double {
        didSet {
            fontSize = Self.clamped(
                fontSize,
                to: Self.fontSizeRange,
                fallback: Self.defaultFontSize
            )
        }
    }
    /// Maximum prose width in points.
    public var lineWidth: Double {
        didSet {
            lineWidth = Self.clamped(
                lineWidth,
                to: Self.lineWidthRange,
                fallback: Self.defaultLineWidth
            )
        }
    }
    /// Line height as a multiple of the prose font size.
    public var lineHeight: Double {
        didSet {
            lineHeight = Self.clamped(
                lineHeight,
                to: Self.lineHeightRange,
                fallback: Self.defaultLineHeight
            )
        }
    }
    public var codeFont: String {
        didSet {
            codeFont = Self.normalizedCodeFont(codeFont)
        }
    }

    public init(
        theme: ReadingTheme = .system,
        fontSize: Double = defaultFontSize,
        lineWidth: Double = defaultLineWidth,
        lineHeight: Double = defaultLineHeight,
        codeFont: String = defaultCodeFont
    ) {
        self.theme = theme
        self.fontSize = Self.clamped(
            fontSize,
            to: Self.fontSizeRange,
            fallback: Self.defaultFontSize
        )
        self.lineWidth = Self.clamped(
            lineWidth,
            to: Self.lineWidthRange,
            fallback: Self.defaultLineWidth
        )
        self.lineHeight = Self.clamped(
            lineHeight,
            to: Self.lineHeightRange,
            fallback: Self.defaultLineHeight
        )
        self.codeFont = Self.normalizedCodeFont(codeFont)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            theme: try container.decodeIfPresent(
                ReadingTheme.self,
                forKey: .theme
            ) ?? .system,
            fontSize: try container.decodeIfPresent(
                Double.self,
                forKey: .fontSize
            ) ?? Self.defaultFontSize,
            lineWidth: try container.decodeIfPresent(
                Double.self,
                forKey: .lineWidth
            ) ?? Self.defaultLineWidth,
            lineHeight: try container.decodeIfPresent(
                Double.self,
                forKey: .lineHeight
            ) ?? Self.defaultLineHeight,
            codeFont: try container.decodeIfPresent(
                String.self,
                forKey: .codeFont
            ) ?? Self.defaultCodeFont
        )
    }

    private static func clamped(
        _ value: Double,
        to range: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        guard value.isFinite else {
            return fallback
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func normalizedCodeFont(_ font: String) -> String {
        let trimmed = font.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultCodeFont : trimmed
    }
}
