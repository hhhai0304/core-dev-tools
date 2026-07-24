import AppKit
import SwiftUI

struct SelectableDiffComparisonView: NSViewRepresentable {
    let lines: [JSONSideBySideLine]
    let selectedDifferenceID: Int?
    let selectedLineID: Int?

    func makeNSView(context: Context) -> DiffComparisonScrollContainer {
        let view = DiffComparisonScrollContainer()
        view.update(
            lines: lines,
            selectedDifferenceID: selectedDifferenceID,
            selectedLineID: selectedLineID
        )
        return view
    }

    func updateNSView(_ view: DiffComparisonScrollContainer, context: Context) {
        view.update(
            lines: lines,
            selectedDifferenceID: selectedDifferenceID,
            selectedLineID: selectedLineID
        )
    }
}

final class DiffComparisonScrollContainer: NSView {
    private let scrollView = NSScrollView()
    private let comparisonView = DiffComparisonDocumentView()
    private var selectedLineID: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = comparisonView
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        comparisonView.updateViewportSize(scrollView.contentSize)
    }

    func update(
        lines: [JSONSideBySideLine],
        selectedDifferenceID: Int?,
        selectedLineID: Int?
    ) {
        comparisonView.update(lines: lines, selectedDifferenceID: selectedDifferenceID)

        let shouldScroll = self.selectedLineID != selectedLineID
        self.selectedLineID = selectedLineID
        guard shouldScroll, let selectedLineID else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.scrollToLine(selectedLineID)
        }
    }

    private func scrollToLine(_ lineID: Int) {
        layoutSubtreeIfNeeded()
        guard let target = comparisonView.rect(forLineID: lineID) else {
            return
        }

        let visibleHeight = scrollView.contentView.bounds.height
        let maximumY = max(0, comparisonView.frame.height - visibleHeight)
        let targetY = min(maximumY, max(0, target.midY - visibleHeight / 2))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

final class DiffComparisonDocumentView: NSView {
    private enum Side {
        case left
        case right
    }

    private static let gutterWidth: CGFloat = 46
    private static let dividerWidth: CGFloat = 1
    private static let rowPadding: CGFloat = 10
    private static let textFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

    private let leftTextView = NSTextView()
    private let rightTextView = NSTextView()
    private var lines: [JSONSideBySideLine] = []
    private var leftRanges: [NSRange] = []
    private var rightRanges: [NSRange] = []
    private var rowOffsets: [CGFloat] = []
    private var rowHeights: [CGFloat] = []
    private var selectedDifferenceID: Int?
    private var viewportSize = NSSize.zero

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure(leftTextView)
        configure(rightTextView)
        addSubview(leftTextView)
        addSubview(rightTextView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(lines: [JSONSideBySideLine], selectedDifferenceID: Int?) {
        let contentChanged = self.lines != lines
        let selectionChanged = self.selectedDifferenceID != selectedDifferenceID
        self.selectedDifferenceID = selectedDifferenceID

        if contentChanged {
            self.lines = lines
            replaceTextContents()
            rebuildLayout()
        } else if selectionChanged {
            needsDisplay = true
        }
    }

    func updateViewportSize(_ size: NSSize) {
        guard abs(viewportSize.width - size.width) > 0.5 ||
                abs(viewportSize.height - size.height) > 0.5 else {
            return
        }
        viewportSize = size
        rebuildLayout()
    }

    func rect(forLineID lineID: Int) -> NSRect? {
        guard let index = lines.firstIndex(where: { $0.id == lineID }),
              rowOffsets.indices.contains(index),
              rowHeights.indices.contains(index) else {
            return nil
        }
        return NSRect(
            x: 0,
            y: rowOffsets[index],
            width: bounds.width,
            height: rowHeights[index]
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        let halfWidth = (bounds.width - Self.dividerWidth) / 2
        for index in lines.indices where rowOffsets.indices.contains(index) && rowHeights.indices.contains(index) {
            let rowRect = NSRect(
                x: 0,
                y: rowOffsets[index],
                width: bounds.width,
                height: rowHeights[index]
            )
            guard rowRect.intersects(dirtyRect) else {
                continue
            }

            fillBackground(
                for: lines[index].status,
                side: .left,
                rect: NSRect(x: 0, y: rowRect.minY, width: halfWidth, height: rowRect.height)
            )
            fillBackground(
                for: lines[index].status,
                side: .right,
                rect: NSRect(
                    x: halfWidth + Self.dividerWidth,
                    y: rowRect.minY,
                    width: halfWidth,
                    height: rowRect.height
                )
            )
            drawLineNumber(lines[index].leftLineNumber, x: 0, rowRect: rowRect)
            drawLineNumber(
                lines[index].rightLineNumber,
                x: halfWidth + Self.dividerWidth,
                rowRect: rowRect
            )

            if lines[index].differenceID == selectedDifferenceID {
                NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
                let outline = rowRect.insetBy(dx: 0.5, dy: 0.5)
                NSBezierPath(rect: outline).stroke()
            }
        }

        NSColor.separatorColor.setFill()
        NSRect(x: halfWidth, y: dirtyRect.minY, width: Self.dividerWidth, height: dirtyRect.height).fill()
        NSRect(x: Self.gutterWidth - 1, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
        NSRect(
            x: halfWidth + Self.dividerWidth + Self.gutterWidth - 1,
            y: dirtyRect.minY,
            width: 1,
            height: dirtyRect.height
        ).fill()
    }

    private func configure(_ textView: NSTextView) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.font = Self.textFont
        textView.textContainerInset = NSSize(width: 8, height: 5)
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.layoutManager?.allowsNonContiguousLayout = false
    }

    private func replaceTextContents() {
        let left = attributedText(for: .left)
        let right = attributedText(for: .right)
        leftRanges = left.ranges
        rightRanges = right.ranges
        leftTextView.textStorage?.setAttributedString(left.value)
        rightTextView.textStorage?.setAttributedString(right.value)
    }

    private func attributedText(for side: Side) -> (value: NSAttributedString, ranges: [NSRange]) {
        let output = NSMutableAttributedString()
        var ranges: [NSRange] = []
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.textFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle(spacing: Self.rowPadding),
        ]

        for line in lines {
            let text = side == .left ? line.leftText : line.rightText
            let start = output.length
            output.append(NSAttributedString(string: (text ?? "") + "\n", attributes: attributes))
            ranges.append(NSRange(location: start, length: output.length - start))
        }
        return (output, ranges)
    }

    private func rebuildLayout() {
        guard viewportSize.width > 0 else {
            return
        }

        let halfWidth = (viewportSize.width - Self.dividerWidth) / 2
        let textWidth = max(1, halfWidth - Self.gutterWidth)
        let provisionalHeight = max(viewportSize.height, 1)
        leftTextView.frame = NSRect(
            x: Self.gutterWidth,
            y: 0,
            width: textWidth,
            height: provisionalHeight
        )
        rightTextView.frame = NSRect(
            x: halfWidth + Self.dividerWidth + Self.gutterWidth,
            y: 0,
            width: textWidth,
            height: provisionalHeight
        )
        leftTextView.textContainer?.containerSize = NSSize(
            width: textWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        rightTextView.textContainer?.containerSize = NSSize(
            width: textWidth,
            height: CGFloat.greatestFiniteMagnitude
        )

        resetParagraphSpacing(in: leftTextView, ranges: leftRanges)
        resetParagraphSpacing(in: rightTextView, ranges: rightRanges)
        ensureLayout(leftTextView)
        ensureLayout(rightTextView)

        let leftHeights = measuredTextHeights(in: leftTextView, ranges: leftRanges)
        let rightHeights = measuredTextHeights(in: rightTextView, ranges: rightRanges)
        rowHeights = lines.indices.map { index in
            max(leftHeights[index], rightHeights[index]) + Self.rowPadding
        }

        applyAlignedSpacing(
            to: leftTextView,
            ranges: leftRanges,
            measuredHeights: leftHeights
        )
        applyAlignedSpacing(
            to: rightTextView,
            ranges: rightRanges,
            measuredHeights: rightHeights
        )
        ensureLayout(leftTextView)
        ensureLayout(rightTextView)

        rowOffsets = []
        rowOffsets.reserveCapacity(rowHeights.count)
        var offset: CGFloat = 0
        for height in rowHeights {
            rowOffsets.append(offset)
            offset += height
        }

        let contentHeight = max(viewportSize.height, ceil(offset))
        frame = NSRect(x: 0, y: 0, width: viewportSize.width, height: contentHeight)
        leftTextView.frame.size.height = contentHeight
        rightTextView.frame.size.height = contentHeight
        needsDisplay = true
    }

    private func resetParagraphSpacing(in textView: NSTextView, ranges: [NSRange]) {
        guard let storage = textView.textStorage else {
            return
        }
        storage.beginEditing()
        for range in ranges {
            storage.addAttribute(
                .paragraphStyle,
                value: paragraphStyle(spacing: Self.rowPadding),
                range: range
            )
        }
        storage.endEditing()
    }

    private func applyAlignedSpacing(
        to textView: NSTextView,
        ranges: [NSRange],
        measuredHeights: [CGFloat]
    ) {
        guard let storage = textView.textStorage else {
            return
        }
        storage.beginEditing()
        for index in ranges.indices {
            let spacing = max(
                Self.rowPadding,
                rowHeights[index] - measuredHeights[index]
            )
            storage.addAttribute(
                .paragraphStyle,
                value: paragraphStyle(spacing: spacing),
                range: ranges[index]
            )
        }
        storage.endEditing()
    }

    private func measuredTextHeights(
        in textView: NSTextView,
        ranges: [NSRange]
    ) -> [CGFloat] {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return Array(repeating: Self.textFont.defaultLineHeight, count: ranges.count)
        }

        return ranges.map { range in
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            return max(Self.textFont.defaultLineHeight, ceil(rect.height))
        }
    }

    private func ensureLayout(_ textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }
        layoutManager.ensureLayout(for: textContainer)
    }

    private func paragraphStyle(spacing: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byCharWrapping
        style.minimumLineHeight = Self.textFont.defaultLineHeight
        style.paragraphSpacing = spacing
        return style
    }

    private func fillBackground(for status: JSONDiffStatus, side: Side, rect: NSRect) {
        let color: NSColor?
        switch status {
        case .unchanged:
            color = nil
        case .changed:
            color = NSColor.systemOrange.withAlphaComponent(0.15)
        case .added:
            color = NSColor.systemGreen.withAlphaComponent(side == .right ? 0.18 : 0.04)
        case .removed:
            color = NSColor.systemRed.withAlphaComponent(side == .left ? 0.18 : 0.04)
        }
        color?.setFill()
        if color != nil {
            rect.fill()
        }
    }

    private func drawLineNumber(_ number: Int?, x: CGFloat, rowRect: NSRect) {
        guard let number else {
            return
        }
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.numberFont,
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: style,
        ]
        NSString(string: String(number)).draw(
            in: NSRect(
                x: x + 3,
                y: rowRect.minY + 6,
                width: Self.gutterWidth - 11,
                height: Self.numberFont.defaultLineHeight + 2
            ),
            withAttributes: attributes
        )
    }
}

private extension NSFont {
    var defaultLineHeight: CGFloat {
        ceil(ascender - descender + leading)
    }
}
