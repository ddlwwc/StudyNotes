import SwiftUI

enum SNColor {
    static let page = Color(hex: 0xF2F3F5)
    static let nav = Color(hex: 0xF7F8FA)
    static let soft = Color(hex: 0xFAFBFC)
    static let border = Color(hex: 0xE5E6EB)
    static let borderStrong = Color(hex: 0xD9DCE2)
    static let text = Color(hex: 0x4E5969)
    static let ink = Color(hex: 0x1F2329)
    static let muted = Color(hex: 0x86909C)
    static let primary = Color(hex: 0x3370FF)
    static let primarySoft = Color(hex: 0xEEF4FF)
    static let green = Color(hex: 0x1F9D61)
    static let greenSoft = Color(hex: 0xEDF9F3)
    static let amber = Color(hex: 0xF6C453)
    static let amberSoft = Color(hex: 0xFFF8E7)
    static let amberInk = Color(hex: 0x8B6B14)
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
            .background(Color.white)
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
