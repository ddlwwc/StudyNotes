import Foundation

/// Desktop and iPad workspace layout; iPhone uses `ReadingPreferences` only.
public struct WorkspacePreferences: Codable, Equatable, Sendable {
    public static let libraryWidthRange = 160.0...320.0
    public static let materialsWidthRange = 240.0...480.0
    public static let studyWidthRange = 220.0...420.0

    public static let defaultLibraryWidth = 184.0
    public static let defaultMaterialsWidth = 276.0
    public static let defaultStudyWidth = 260.0

    public var libraryWidth: Double {
        didSet {
            libraryWidth = Self.clamped(
                libraryWidth,
                to: Self.libraryWidthRange,
                fallback: Self.defaultLibraryWidth
            )
        }
    }
    public var materialsWidth: Double {
        didSet {
            materialsWidth = Self.clamped(
                materialsWidth,
                to: Self.materialsWidthRange,
                fallback: Self.defaultMaterialsWidth
            )
        }
    }
    public var studyWidth: Double {
        didSet {
            studyWidth = Self.clamped(
                studyWidth,
                to: Self.studyWidthRange,
                fallback: Self.defaultStudyWidth
            )
        }
    }
    public var isLibraryCollapsed: Bool
    public var isMaterialsCollapsed: Bool
    public var isStudyCollapsed: Bool

    public init(
        libraryWidth: Double = Self.defaultLibraryWidth,
        materialsWidth: Double = Self.defaultMaterialsWidth,
        studyWidth: Double = Self.defaultStudyWidth,
        isLibraryCollapsed: Bool = false,
        isMaterialsCollapsed: Bool = false,
        isStudyCollapsed: Bool = false
    ) {
        self.libraryWidth = Self.clamped(
            libraryWidth,
            to: Self.libraryWidthRange,
            fallback: Self.defaultLibraryWidth
        )
        self.materialsWidth = Self.clamped(
            materialsWidth,
            to: Self.materialsWidthRange,
            fallback: Self.defaultMaterialsWidth
        )
        self.studyWidth = Self.clamped(
            studyWidth,
            to: Self.studyWidthRange,
            fallback: Self.defaultStudyWidth
        )
        self.isLibraryCollapsed = isLibraryCollapsed
        self.isMaterialsCollapsed = isMaterialsCollapsed
        self.isStudyCollapsed = isStudyCollapsed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            libraryWidth: try container.decodeIfPresent(
                Double.self,
                forKey: .libraryWidth
            ) ?? Self.defaultLibraryWidth,
            materialsWidth: try container.decodeIfPresent(
                Double.self,
                forKey: .materialsWidth
            ) ?? Self.defaultMaterialsWidth,
            studyWidth: try container.decodeIfPresent(
                Double.self,
                forKey: .studyWidth
            ) ?? Self.defaultStudyWidth,
            isLibraryCollapsed: try container.decodeIfPresent(
                Bool.self,
                forKey: .isLibraryCollapsed
            ) ?? false,
            isMaterialsCollapsed: try container.decodeIfPresent(
                Bool.self,
                forKey: .isMaterialsCollapsed
            ) ?? false,
            isStudyCollapsed: try container.decodeIfPresent(
                Bool.self,
                forKey: .isStudyCollapsed
            ) ?? false
        )
    }

    public mutating func restoreDefaultWidths() {
        libraryWidth = Self.defaultLibraryWidth
        materialsWidth = Self.defaultMaterialsWidth
        studyWidth = Self.defaultStudyWidth
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
}
