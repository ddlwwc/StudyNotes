import SwiftUI
#if os(iOS)
import UIKit
#endif

enum SNColor {
    static let page = adaptive(light: 0xF2F3F5, dark: 0x15161A)
    static let nav = adaptive(light: 0xF7F8FA, dark: 0x1E2025)
    static let soft = adaptive(light: 0xFAFBFC, dark: 0x24262C)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1B1D22)
    static let border = adaptive(light: 0xE5E6EB, dark: 0x343740)
    static let borderStrong = adaptive(light: 0xD9DCE2, dark: 0x454953)
    static let text = adaptive(light: 0x4E5969, dark: 0xC7CBD2)
    static let ink = adaptive(light: 0x1F2329, dark: 0xEDEFF2)
    static let muted = adaptive(light: 0x86909C, dark: 0x969BA5)
    static let primary = adaptive(light: 0x3370FF, dark: 0x77A0FF)
    static let primarySoft = adaptive(light: 0xEEF4FF, dark: 0x202D4A)
    static let green = adaptive(light: 0x1F9D61, dark: 0x55C98D)
    static let greenSoft = adaptive(light: 0xEDF9F3, dark: 0x183126)
    static let amber = adaptive(light: 0xF6C453, dark: 0xE8B94A)
    static let amberSoft = adaptive(light: 0xFFF8E7, dark: 0x362E19)
    static let amberInk = adaptive(light: 0x8B6B14, dark: 0xE8C66C)
    static let red = adaptive(light: 0xD92D20, dark: 0xFF746C)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
#if os(iOS)
        Color(
            uiColor: UIColor { traits in
                UIColor(
                    Color(
                        hex: traits.userInterfaceStyle == .dark
                            ? dark
                            : light
                    )
                )
            }
        )
#else
        Color(hex: light)
#endif
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct StatusPill: View {
    let text: String
    var color: Color = SNColor.muted
    var background: Color = SNColor.nav
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
            }
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(background)
        .clipShape(Capsule())
    }
}

struct CardSurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(SNColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(SNColor.border, lineWidth: 1)
            }
    }
}

struct SectionTitle: View {
    let title: String
    var detail: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SNColor.ink)
            if let detail {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(SNColor.muted)
                    .lineLimit(1)
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SNColor.primary)
            }
        }
    }
}
