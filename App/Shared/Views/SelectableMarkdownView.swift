import SwiftUI
import StudyCore

#if canImport(UIKit)
import UIKit

struct RenderedMarkdownTextView: UIViewRepresentable {
    let layout: MarkdownLayout
    let markedRanges: [NSRange]
    @Binding var selectedRenderedRange: NSRange?
    var onTapMarkedRange: ((NSRange) -> Void)?
    var onTapOutside: (() -> Void)?
    var onVisibleNearestChange: ((NSRange?) -> Void)?

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = true
        view.alwaysBounceVertical = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 16, left: 14, bottom: 40, right: 14)
        view.textContainer.lineFragmentPadding = 0
        view.tintColor = .systemRed
        view.delegate = context.coordinator
        view.adjustsFontForContentSizeCategory = true

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        context.coordinator.attachedView = view
        context.coordinator.onVisibleNearestChange = onVisibleNearestChange
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTapMarkedRange = onTapMarkedRange
        coordinator.onTapOutside = onTapOutside
        coordinator.onVisibleNearestChange = onVisibleNearestChange
        coordinator.layout = layout
        coordinator.markedRanges = markedRanges

        let signature = AttributedMarkdown.signature(
            layout: layout,
            markedRanges: markedRanges
        )
        guard coordinator.lastSignature != signature else { return }
        coordinator.lastSignature = signature

        let built = AttributedMarkdown.build(layout: layout, markedRanges: markedRanges)
        coordinator.isApplyingContent = true
        view.attributedText = built
        coordinator.isApplyingContent = false
        coordinator.reportVisibleNearest()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selected: $selectedRenderedRange)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        @Binding var selected: NSRange?
        var onTapMarkedRange: ((NSRange) -> Void)?
        var onTapOutside: (() -> Void)?
        var onVisibleNearestChange: ((NSRange?) -> Void)?
        var layout: MarkdownLayout?
        var markedRanges: [NSRange] = []
        weak var attachedView: UITextView?
        var lastSignature: Int?
        var isApplyingContent = false
        private var lastReported: NSRange?

        func scrollTo(sourceRange: NSRange) {
            guard let textView = attachedView,
                  let layout,
                  let rendered = layout.renderedRange(forSource: sourceRange)
            else { return }
            let lm = textView.layoutManager
            let glyphRange = lm.glyphRange(forCharacterRange: rendered, actualCharacterRange: nil)
            var rect = lm.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)
            rect.origin.y += textView.textContainerInset.top
            rect.origin.x = 0
            rect.size.width = textView.bounds.width
            rect = rect.insetBy(dx: 0, dy: -80)
            textView.scrollRectToVisible(rect, animated: true)
        }

        func reportVisibleNearest() {
            guard let textView = attachedView, let layout else { return }
            let offset = textView.contentOffset.y + textView.bounds.height
            let lm = textView.layoutManager
            let inset = textView.textContainerInset

            var best: (range: NSRange, distance: CGFloat)?

            for source in markedRanges {
                guard let rendered = layout.renderedRange(forSource: source),
                      rendered.length > 0 else { continue }
                let glyphRange = lm.glyphRange(
                    forCharacterRange: rendered,
                    actualCharacterRange: nil
                )
                var rect = lm.boundingRect(
                    forGlyphRange: glyphRange,
                    in: textView.textContainer
                )
                rect.origin.y += inset.top
                rect.origin.x += inset.left

                let distance = abs(rect.maxY - offset)
                if best == nil || distance < best!.distance {
                    best = (source, distance)
                }
            }

            let result = best?.range
            if lastReported != result {
                lastReported = result
                onVisibleNearestChange?(result)
            }
        }

        init(selected: Binding<NSRange?>) {
            self._selected = selected
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingContent else { return }
            let range = textView.selectedRange
            selected = range.length > 0 ? range : nil
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            reportVisibleNearest()
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            reportVisibleNearest()
        }

        @available(iOS 16.0, *)
        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            return nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = attachedView,
                  let layout,
                  gesture.state == .ended,
                  textView.selectedRange.length == 0 else { return }

            let point = gesture.location(in: textView)
            let containerPoint = CGPoint(
                x: point.x - textView.textContainerInset.left,
                y: point.y - textView.textContainerInset.top
            )
            let lm = textView.layoutManager
            let index = lm.characterIndex(
                for: containerPoint,
                in: textView.textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )

            guard index != NSNotFound, index >= 0,
                  let rendered = layout.pieces.first(where: { piece in
                      piece.renderedRange.length > 0
                          && NSLocationInRange(index, piece.renderedRange)
                  }),
                  let source = layout.sourceRange(forRendered: rendered.renderedRange),
                  let hit = markedRanges.first(where: {
                      NSIntersectionRange($0, source).length > 0
                  })
            else {
                onTapOutside?()
                return
            }

            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTapMarkedRange?(hit)
        }
    }
}

enum AttributedMarkdown {
    static func signature(layout: MarkdownLayout, markedRanges: [NSRange]) -> Int {
        var hasher = Hasher()
        hasher.combine(layout.text)
        for range in markedRanges {
            hasher.combine(range.location)
            hasher.combine(range.length)
        }
        return hasher.finalize()
    }

    static func build(layout: MarkdownLayout, markedRanges: [NSRange]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: layout.text)
        let full = NSRange(location: 0, length: (layout.text as NSString).length)

        if full.length == 0 {
            return NSAttributedString(
                string: "这篇笔记还没有内容，点右上角「编辑」开始写。",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .footnote),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            )
        }

        result.addAttributes([
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
        ], range: full)

        for piece in layout.pieces {
            let range = piece.renderedRange
            guard range.length > 0, range.location + range.length <= full.length else { continue }

            switch piece.role {
            case let .heading(level):
                let size: CGFloat
                switch level {
                case 1: size = 26
                case 2: size = 22
                case 3: size = 19
                default: size = 17
                }
                result.addAttributes([
                    .font: UIFont.systemFont(ofSize: size, weight: .semibold),
                ], range: range)

            case let .bullet(indent):
                result.addAttribute(
                    .paragraphStyle,
                    value: paragraphStyle(indent: indent + 1, wrapIndent: 16),
                    range: range
                )

            case let .numbered(_, indent):
                result.addAttribute(
                    .paragraphStyle,
                    value: paragraphStyle(indent: indent + 1, wrapIndent: 16),
                    range: range
                )

            case .quote:
                result.addAttributes([
                    .foregroundColor: UIColor.secondaryLabel,
                ], range: range)

            case let .code(language):
                _ = language
                result.addAttributes([
                    .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .backgroundColor: UIColor.secondarySystemBackground,
                ], range: range)

            case .cardQuestion:
                result.addAttribute(
                    .font,
                    value: UIFont.preferredFont(forTextStyle: .body).semibold(),
                    range: range
                )

            case .cardAnswer:
                result.addAttributes([
                    .foregroundColor: UIColor.secondaryLabel,
                ], range: range)

            case .cardLabel:
                result.addAttributes([
                    .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: UIColor.systemBlue,
                ], range: range)

            case .divider:
                result.addAttribute(
                    .foregroundColor,
                    value: UIColor.tertiaryLabel,
                    range: range
                )

            case .paragraph:
                break
            }

            switch piece.emphasis {
            case .bold:
                result.addAttribute(
                    .font,
                    value: UIFont.preferredFont(forTextStyle: .body).semibold(),
                    range: range
                )
            case .italic:
                result.addAttribute(
                    .font,
                    value: UIFont.italicSystemFont(
                        ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize
                    ),
                    range: range
                )
            case .code:
                result.addAttributes([
                    .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .regular),
                    .foregroundColor: UIColor.systemPink,
                ], range: range)
            case .highlight:
                result.addAttributes([
                    .backgroundColor: UIColor.systemYellow.withAlphaComponent(0.3),
                ], range: range)
            case .none:
                break
            }
        }

        for sourceRange in markedRanges {
            guard let rendered = layout.renderedRange(forSource: sourceRange) else { continue }
            guard rendered.location + rendered.length <= full.length else { continue }
            result.addAttributes([
                .backgroundColor: UIColor.systemYellow.withAlphaComponent(0.35),
                .underlineStyle: 0,
            ], range: rendered)
        }

        return result
    }

    private static func paragraphStyle(indent: Int, wrapIndent: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = CGFloat(indent) * 12
        style.headIndent = CGFloat(indent) * 12 + wrapIndent
        return style
    }
}

private extension UIFont {
    func semibold() -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

#endif

#if canImport(AppKit) && !canImport(UIKit)
import AppKit

struct RenderedMarkdownTextView: NSViewRepresentable {
    let layout: MarkdownLayout
    let markedRanges: [NSRange]
    @Binding var selectedRenderedRange: NSRange?
    var onTapMarkedRange: ((NSRange) -> Void)?
    var onTapOutside: (() -> Void)?
    var onVisibleNearestChange: ((NSRange?) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 16)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.systemRed.withAlphaComponent(0.3),
        ]

        let tap = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleClick(_:))
        )
        textView.addGestureRecognizer(tap)

        context.coordinator.attachedView = textView
        scrollView.documentView = textView

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        context.coordinator.onVisibleNearestChange = onVisibleNearestChange
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTapMarkedRange = onTapMarkedRange
        coordinator.onTapOutside = onTapOutside
        coordinator.onVisibleNearestChange = onVisibleNearestChange
        coordinator.layout = layout
        coordinator.markedRanges = markedRanges
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let signature = AttributedMarkdownMac.signature(
            layout: layout,
            markedRanges: markedRanges
        )
        guard coordinator.lastSignature != signature else { return }
        coordinator.lastSignature = signature

        let built = AttributedMarkdownMac.build(layout: layout, markedRanges: markedRanges)
        coordinator.isApplyingContent = true
        textView.textStorage?.setAttributedString(built)
        coordinator.isApplyingContent = false
        coordinator.reportVisibleNearest()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selected: $selectedRenderedRange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var selected: NSRange?
        var onTapMarkedRange: ((NSRange) -> Void)?
        var onTapOutside: (() -> Void)?
        var onVisibleNearestChange: ((NSRange?) -> Void)?
        var layout: MarkdownLayout?
        var markedRanges: [NSRange] = []
        weak var attachedView: NSTextView?
        var lastSignature: Int?
        var isApplyingContent = false
        private var lastReported: NSRange?

        @objc func handleScroll() {
            reportVisibleNearest()
        }

        func scrollTo(sourceRange: NSRange) {
            guard let textView = attachedView,
                  let layout,
                  let lm = textView.layoutManager,
                  let container = textView.textContainer,
                  let rendered = layout.renderedRange(forSource: sourceRange)
            else { return }
            lm.ensureLayout(for: container)
            let glyphRange = lm.glyphRange(forCharacterRange: rendered, actualCharacterRange: nil)
            var rect = lm.boundingRect(forGlyphRange: glyphRange, in: container)
            rect.origin.y += textView.textContainerInset.height
            rect = rect.insetBy(dx: 0, dy: -80)
            textView.scrollToVisible(rect)
        }

        func reportVisibleNearest() {
            guard let textView = attachedView,
                  let layout,
                  let lm = textView.layoutManager,
                  let container = textView.textContainer,
                  let clip = textView.enclosingScrollView?.contentView else { return }

            lm.ensureLayout(for: container)
            let visibleBottom = clip.bounds.origin.y + clip.bounds.height
            var best: (range: NSRange, distance: CGFloat)?

            for source in markedRanges {
                guard let rendered = layout.renderedRange(forSource: source),
                      rendered.length > 0 else { continue }
                let glyphRange = lm.glyphRange(
                    forCharacterRange: rendered,
                    actualCharacterRange: nil
                )
                var rect = lm.boundingRect(forGlyphRange: glyphRange, in: container)
                rect.origin.y += textView.textContainerInset.height

                let distance = abs(rect.maxY - visibleBottom)
                if best == nil || distance < best!.distance {
                    best = (source, distance)
                }
            }

            let result = best?.range
            if lastReported != result {
                lastReported = result
                onVisibleNearestChange?(result)
            }
        }

        init(selected: Binding<NSRange?>) {
            self._selected = selected
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let textView = attachedView,
                  let layout,
                  gesture.state == .ended,
                  textView.selectedRange().length == 0 else { return }

            let point = gesture.location(in: textView)
            let index = textView.characterIndexForInsertion(at: point)

            guard index >= 0,
                  let rendered = layout.pieces.first(where: { piece in
                      piece.renderedRange.length > 0
                          && NSLocationInRange(index, piece.renderedRange)
                  }),
                  let source = layout.sourceRange(forRendered: rendered.renderedRange),
                  let hit = markedRanges.first(where: {
                      NSIntersectionRange($0, source).length > 0
                  })
            else {
                onTapOutside?()
                return
            }

            onTapMarkedRange?(hit)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingContent else { return }
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            selected = range.length > 0 ? range : nil
        }
    }
}

enum AttributedMarkdownMac {
    static func signature(layout: MarkdownLayout, markedRanges: [NSRange]) -> Int {
        var hasher = Hasher()
        hasher.combine(layout.text)
        for range in markedRanges {
            hasher.combine(range.location)
            hasher.combine(range.length)
        }
        return hasher.finalize()
    }

    static func build(layout: MarkdownLayout, markedRanges: [NSRange]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: layout.text)
        let full = NSRange(location: 0, length: (layout.text as NSString).length)

        if full.length == 0 {
            return NSAttributedString(
                string: "这篇笔记还没有内容，点「编辑」开始写。",
                attributes: [
                    .font: NSFont.preferredFont(forTextStyle: .footnote),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            )
        }

        result.addAttributes([
            .font: NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.labelColor,
        ], range: full)

        for piece in layout.pieces {
            let range = piece.renderedRange
            guard range.length > 0, range.location + range.length <= full.length else { continue }

            switch piece.role {
            case let .heading(level):
                let size: CGFloat
                switch level {
                case 1: size = 26
                case 2: size = 22
                case 3: size = 19
                default: size = 17
                }
                result.addAttribute(
                    .font,
                    value: NSFont.systemFont(ofSize: size, weight: .semibold),
                    range: range
                )
            case .quote:
                result.addAttribute(
                    .foregroundColor,
                    value: NSColor.secondaryLabelColor,
                    range: range
                )
            case .code:
                result.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .backgroundColor: NSColor.unemphasizedSelectedContentBackgroundColor,
                ], range: range)
            case .cardQuestion:
                result.addAttribute(
                    .font,
                    value: NSFont.systemFont(
                        ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize,
                        weight: .semibold
                    ),
                    range: range
                )
            case .cardAnswer:
                result.addAttribute(
                    .foregroundColor,
                    value: NSColor.secondaryLabelColor,
                    range: range
                )
            case .cardLabel:
                result.addAttributes([
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: NSColor.systemBlue,
                ], range: range)
            case .divider:
                result.addAttribute(
                    .foregroundColor,
                    value: NSColor.tertiaryLabelColor,
                    range: range
                )
            case .paragraph, .bullet, .numbered:
                break
            }

            switch piece.emphasis {
            case .bold:
                result.addAttribute(
                    .font,
                    value: NSFont.systemFont(
                        ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize,
                        weight: .semibold
                    ),
                    range: range
                )
            case .italic:
                result.addAttribute(
                    .font,
                    value: NSFontManager.shared.convert(
                        NSFont.preferredFont(forTextStyle: .body),
                        toHaveTrait: .italicFontMask
                    ),
                    range: range
                )
            case .code:
                result.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
                    .foregroundColor: NSColor.systemPink,
                ], range: range)
            case .highlight:
                result.addAttribute(
                    .backgroundColor,
                    value: NSColor.systemYellow.withAlphaComponent(0.3),
                    range: range
                )
            case .none:
                break
            }
        }

        for sourceRange in markedRanges {
            guard let rendered = layout.renderedRange(forSource: sourceRange) else { continue }
            guard rendered.location + rendered.length <= full.length else { continue }
            result.addAttribute(
                .backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.35),
                range: rendered
            )
        }

        return result
    }
}
#endif
