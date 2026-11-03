#if os(iOS)
import SwiftUI
import UIKit
import StudyNotesIOSCore

struct ImageAnnotationCanvas: View {
    let contentURL: URL
    let annotations: [StudyAnnotation]
    @Binding var pendingRectangle: NormalizedRectangle?

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var rotation: Angle = .zero
    @State private var offset: CGSize = .zero
    @State private var dragStart = CGSize.zero
    @State private var isDrawingMode = false
    @State private var drawingStart: CGPoint?
    @State private var drawingCurrent: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let fitted = fittedSize(in: proxy.size)
            let imageRect = CGRect(
                x: (proxy.size.width - fitted.width) / 2,
                y: (proxy.size.height - fitted.height) / 2,
                width: fitted.width,
                height: fitted.height
            )

            ZStack {
                SNColor.nav.ignoresSafeArea()
                if let image {
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: fitted.width, height: fitted.height)
                        ForEach(annotations) { annotation in
                            if case let .imageRectangle(rectangle) = annotation.anchor {
                                Rectangle()
                                    .fill(SNColor.amber.opacity(0.2))
                                    .overlay {
                                        Rectangle()
                                            .stroke(SNColor.amber, lineWidth: 2)
                                    }
                                    .frame(
                                        width: fitted.width * rectangle.width,
                                        height: fitted.height * rectangle.height
                                    )
                                    .offset(
                                        x: fitted.width * rectangle.x,
                                        y: fitted.height * rectangle.y
                                    )
                            }
                        }
                        if let rectangle = draftRectangle {
                            Rectangle()
                                .fill(SNColor.primary.opacity(0.14))
                                .overlay {
                                    Rectangle()
                                        .stroke(
                                            SNColor.primary,
                                            style: StrokeStyle(
                                                lineWidth: 2,
                                                dash: [5, 4]
                                            )
                                        )
                                }
                                .frame(
                                    width: fitted.width * rectangle.width,
                                    height: fitted.height * rectangle.height
                                )
                                .offset(
                                    x: fitted.width * rectangle.x,
                                    y: fitted.height * rectangle.y
                                )
                        }
                    }
                    .frame(width: fitted.width, height: fitted.height)
                    .scaleEffect(scale)
                    .rotationEffect(rotation)
                    .offset(offset)
                    .position(x: imageRect.midX, y: imageRect.midY)
                    .gesture(
                        dragGesture(
                            fittedSize: fitted,
                            imageRect: imageRect
                        )
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(value, 1), 4)
                            }
                    )
                } else {
                    ProgressView()
                }
            }
            .overlay(alignment: .topTrailing) {
                controls
                    .padding(12)
            }
        }
        .task {
            image = UIImage(contentsOfFile: contentURL.path)
        }
    }

    private var draftRectangle: NormalizedRectangle? {
        guard let drawingStart, let drawingCurrent else {
            return pendingRectangle
        }
        return rectangle(from: drawingStart, to: drawingCurrent)
    }

    private var controls: some View {
        VStack(spacing: 7) {
            Button {
                isDrawingMode.toggle()
                pendingRectangle = nil
            } label: {
                Image(systemName: isDrawingMode ? "hand.draw.fill" : "rectangle.dashed")
                    .frame(width: 34, height: 34)
                    .background(
                        isDrawingMode
                            ? SNColor.primary
                            : Color.white.opacity(0.94)
                    )
                    .foregroundStyle(
                        isDrawingMode ? Color.white : SNColor.text
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel(isDrawingMode ? "退出框选" : "框选区域")

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    scale = 1
                    rotation = .zero
                    offset = .zero
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.94))
                    .foregroundStyle(SNColor.text)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("重置缩放与旋转")

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    rotation += .degrees(90)
                }
            } label: {
                Image(systemName: "rotate.right")
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.94))
                    .foregroundStyle(SNColor.text)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("旋转图片")
        }
        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
    }

    private func dragGesture(
        fittedSize: CGSize,
        imageRect: CGRect
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if isDrawingMode {
                    if drawingStart == nil {
                        drawingStart = value.startLocation
                    }
                    drawingCurrent = value.location
                } else if drawingStart == nil {
                    offset = CGSize(
                        width: dragStart.width + value.translation.width,
                        height: dragStart.height + value.translation.height
                    )
                }
            }
            .onEnded { value in
                if isDrawingMode {
                    let start = drawingStart ?? value.startLocation
                    let end = value.location
                    let screenRect = rectangle(from: start, to: end)
                    drawingStart = nil
                    drawingCurrent = nil
                    let localStart = inverseTransform(
                        start,
                        fittedSize: fittedSize,
                        imageRect: imageRect
                    )
                    let localEnd = inverseTransform(
                        end,
                        fittedSize: fittedSize,
                        imageRect: imageRect
                    )
                    let normalized = normalizedRectangle(
                        from: localStart,
                        to: localEnd,
                        fittedSize: fittedSize
                    )
                    if normalized.width > 0.015, normalized.height > 0.015 {
                        pendingRectangle = normalized
                    } else {
                        _ = screenRect
                    }
                } else {
                    dragStart = offset
                }
            }
    }

    private func fittedSize(in available: CGSize) -> CGSize {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            return available
        }
        let aspect = image.size.width / image.size.height
        if available.width / available.height > aspect {
            return CGSize(
                width: available.height * aspect,
                height: available.height
            )
        }
        return CGSize(
            width: available.width,
            height: available.width / aspect
        )
    }

    private func inverseTransform(
        _ point: CGPoint,
        fittedSize: CGSize,
        imageRect: CGRect
    ) -> CGPoint {
        let center = CGPoint(x: imageRect.midX, y: imageRect.midY)
        var x = point.x - center.x - offset.width
        var y = point.y - center.y - offset.height
        let radians = -rotation.radians
        let rotatedX = x * cos(radians) - y * sin(radians)
        let rotatedY = x * sin(radians) + y * cos(radians)
        x = rotatedX / scale
        y = rotatedY / scale
        return CGPoint(
            x: x + fittedSize.width / 2,
            y: y + fittedSize.height / 2
        )
    }

    private func normalizedRectangle(
        from start: CGPoint,
        to end: CGPoint,
        fittedSize: CGSize
    ) -> NormalizedRectangle {
        let minX = min(start.x, end.x) / fittedSize.width
        let minY = min(start.y, end.y) / fittedSize.height
        let width = abs(start.x - end.x) / fittedSize.width
        let height = abs(start.y - end.y) / fittedSize.height
        return NormalizedRectangle(
            x: Double(min(max(minX, 0), 1)),
            y: Double(min(max(minY, 0), 1)),
            width: Double(min(max(width, 0), 1)),
            height: Double(min(max(height, 0), 1))
        )
    }

    private func rectangle(
        from start: CGPoint,
        to end: CGPoint
    ) -> NormalizedRectangle {
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        return NormalizedRectangle(
            x: Double(minX),
            y: Double(minY),
            width: Double(abs(start.x - end.x)),
            height: Double(abs(start.y - end.y))
        )
    }
}
#endif
