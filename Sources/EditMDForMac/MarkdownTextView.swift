import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let scrollTarget: MarkdownScrollTarget?
    let onLineSelected: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onLineSelected: onLineSelected)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.needsDisplay = true
        scrollView.needsDisplay = true

        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if textView.font != font {
            textView.font = font
        }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        if let scrollTarget, scrollTarget.source != .editor, context.coordinator.lastScrollTarget != scrollTarget {
            context.coordinator.lastScrollTarget = scrollTarget
            context.coordinator.scroll(to: scrollTarget, in: scrollView)
        }

        context.coordinator.onLineSelected = onLineSelected
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onLineSelected: (Int) -> Void
        weak var textView: NSTextView?
        var lastScrollTarget: MarkdownScrollTarget?
        private var lastSelectedLine: Int?

        init(text: Binding<String>, onLineSelected: @escaping (Int) -> Void) {
            _text = text
            self.onLineSelected = onLineSelected
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            publishSelectedLine(from: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            publishSelectedLine(from: textView)
        }

        func scroll(to target: MarkdownScrollTarget, in scrollView: NSScrollView) {
            performScroll(to: target, in: scrollView)
            DispatchQueue.main.async { [weak self] in
                self?.performScroll(to: target, in: scrollView)
            }
        }

        private func performScroll(to target: MarkdownScrollTarget, in scrollView: NSScrollView) {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer
            else { return }

            let clipWidth = scrollView.contentView.bounds.width
            if clipWidth > 0, abs(container.size.width - clipWidth) > 0.5 {
                container.size = NSSize(width: clipWidth, height: .greatestFiniteMagnitude)
            }

            layoutManager.ensureLayout(for: container)
            _ = layoutManager.glyphRange(for: container)

            guard layoutManager.numberOfGlyphs > 0 else {
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                return
            }

            let source = textView.string
            let nsString = source as NSString
            let startChar = min(characterOffset(forLine: target.line, in: source), nsString.length)
            let endCharRaw = characterOffset(forLine: target.endLine + 1, in: source)
            let endChar = min(max(endCharRaw, startChar + 1), nsString.length)

            let blockRange = NSRange(location: startChar, length: endChar - startChar)
            let glyphBlockRange = layoutManager.glyphRange(forCharacterRange: blockRange, actualCharacterRange: nil)

            let topY: CGFloat
            let blockHeight: CGFloat

            if glyphBlockRange.length > 0 {
                var rect = layoutManager.boundingRect(forGlyphRange: glyphBlockRange, in: container)
                rect.origin.y += textView.textContainerOrigin.y
                topY = rect.minY
                blockHeight = max(rect.height, 1)
            } else {
                let safeIndex = min(
                    layoutManager.glyphIndexForCharacter(at: startChar),
                    layoutManager.numberOfGlyphs - 1
                )
                var rect = layoutManager.lineFragmentRect(forGlyphAt: safeIndex, effectiveRange: nil)
                rect.origin.y += textView.textContainerOrigin.y
                topY = rect.minY
                blockHeight = max(rect.height, 1)
            }

            let anchorY = topY + CGFloat(target.fraction) * blockHeight
            let usedRect = layoutManager.usedRect(for: container)
            let docHeight = usedRect.height + textView.textContainerInset.height * 2
            let clipHeight = scrollView.contentView.bounds.height
            let maxY = max(0, docHeight - clipHeight)
            let targetY = max(0, min(maxY, anchorY - 120))

            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func characterOffset(forLine targetLine: Int, in source: String) -> Int {
            let nsString = source as NSString
            var currentLine = 0
            var location = 0

            while currentLine < targetLine && location < nsString.length {
                let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
                location = NSMaxRange(lineRange)
                currentLine += 1
            }

            return min(location, nsString.length)
        }

        private func publishSelectedLine(from textView: NSTextView) {
            let selectedLocation = textView.selectedRange().location
            let line = lineNumber(at: selectedLocation, in: textView.string)
            guard line != lastSelectedLine else { return }

            lastSelectedLine = line
            onLineSelected(line)
        }

        private func lineNumber(at location: Int, in source: String) -> Int {
            let nsString = source as NSString
            let cappedLocation = min(location, nsString.length)
            var line = 0
            var cursor = 0

            while cursor < cappedLocation {
                let lineRange = nsString.lineRange(for: NSRange(location: cursor, length: 0))
                let next = NSMaxRange(lineRange)
                guard next <= cappedLocation, next > cursor else { break }
                cursor = next
                line += 1
            }

            return line
        }
    }
}
