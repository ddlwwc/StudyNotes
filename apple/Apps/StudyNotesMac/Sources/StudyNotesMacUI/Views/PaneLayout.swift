import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkspacePaneDivider: View {
    let width: Double
    let range: ClosedRange<Double>
    let defaultWidth: Double
    let dragDirection: CGFloat
    let onChange: (Double) -> Void
    let onReset: () -> Void

    @State private var dragStartWidth: Double?
    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Color.clear

            Rectangle()
                .fill(isHovering || isDragging ? SNColor.blueLine : Color.clear)
                .frame(width: 1)
        }
            .frame(width: 7)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        isDragging = true
                        if dragStartWidth == nil {
                            dragStartWidth = width
                        }
                        let start = dragStartWidth ?? width
                        let next = start + Double(value.translation.width) * dragDirection
                        onChange(min(max(next, range.lowerBound), range.upperBound))
                    }
                    .onEnded { _ in
                        isDragging = false
                        dragStartWidth = nil
                    }
            )
            .onTapGesture(count: 2) {
                onReset()
            }
            .accessibilityHidden(true)
            .help("拖动调整宽度，双击恢复 \(Int(defaultWidth)) pt")
    }
}

struct PaneVisibilityButton: View {
    let title: String
    let systemImage: String
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isVisible ? SNColor.blue : SNColor.muted)
        .help(isVisible ? "收起\(title)" : "显示\(title)")
        .accessibilityLabel(isVisible ? "收起\(title)" : "显示\(title)")
    }
}

struct WorkspaceDropHighlight: ViewModifier {
    let isTargeted: Bool
    var isAllowed = true

    func body(content: Content) -> some View {
        content
            .background(
                isTargeted
                    ? (isAllowed ? SNColor.blueSoft.opacity(0.9) : SNColor.redSoft.opacity(0.9))
                    : Color.clear
            )
            .overlay {
                RoundedRectangle(cornerRadius: SNRadius.small)
                    .stroke(
                        isTargeted
                            ? (isAllowed ? SNColor.blue : SNColor.red)
                            : Color.clear,
                        lineWidth: 1.5
                    )
            }
    }
}

enum WorkspaceDragItemProvider {
    static func make(_ payload: WorkspaceDragPayload) -> NSItemProvider {
        guard let data = try? JSONEncoder().encode(payload) else {
            return NSItemProvider()
        }
        return NSItemProvider(
            item: data as NSData,
            typeIdentifier: UTType.json.identifier
        )
    }
}
