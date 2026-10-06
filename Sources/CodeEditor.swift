import AppKit
import SwiftUI

enum EditorSyntax {
    case json
    case sql

    func tokenize(_ source: String) -> [EditorSyntaxToken] {
        switch self {
        case .json:
            return JSONSyntaxHighlighter.tokenize(source)
        case .sql:
            return SQLSyntaxHighlighter.tokenize(source)
        }
    }
}

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var syntax: EditorSyntax = .json

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 4
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]

        scrollView.documentView = textView
        context.coordinator.attach(textView: textView, scrollView: scrollView)
        context.coordinator.scheduleTokenization()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        if textView.string != text {
            let selection = textView.selectedRanges
            context.coordinator.isProgrammaticUpdate = true
            textView.string = text
            context.coordinator.isProgrammaticUpdate = false
            let textLength = (text as NSString).length
            let safeSelection = selection.map { rangeValue -> NSValue in
                let range = rangeValue.rangeValue
                let location = min(range.location, textLength)
                let length = min(range.length, textLength - location)
                return NSValue(range: NSRange(location: location, length: length))
            }
            textView.selectedRanges = safeSelection.isEmpty
                ? [NSValue(range: NSRange(location: textLength, length: 0))]
                : safeSelection
            context.coordinator.scheduleTokenization()
        } else {
            context.coordinator.applyVisibleHighlight()
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        var isProgrammaticUpdate = false

        private weak var textView: NSTextView?
        private weak var scrollView: NSScrollView?
        private var scrollObserver: NSObjectProtocol?
        private var pendingTokenization: DispatchWorkItem?
        private var pendingBindingUpdate: DispatchWorkItem?
        private var generation = 0
        private var tokenizedGeneration = -1
        private var tokens: [EditorSyntaxToken] = []

        init(parent: CodeEditor) {
            self.parent = parent
        }

        func attach(textView: NSTextView, scrollView: NSScrollView) {
            self.textView = textView
            self.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.applyVisibleHighlight()
            }
        }

        func detach() {
            pendingTokenization?.cancel()
            pendingBindingUpdate?.cancel()
            if let textView, parent.text != textView.string {
                parent.text = textView.string
            }
            if let textView {
                EditorFindAction.clear(textView)
            }
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
            scrollObserver = nil
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate, let textView else {
                return
            }

            if textView.textStorage?.length ?? 0 < 100_000 {
                parent.text = textView.string
            } else {
                scheduleBindingUpdate()
            }
            textView.typingAttributes = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]
            scheduleTokenization()
        }

        func textDidBeginEditing(_ notification: Notification) {
            if let textView {
                EditorFindAction.activate(textView)
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            pendingBindingUpdate?.cancel()
            if let textView, parent.text != textView.string {
                parent.text = textView.string
            }
        }

        private func scheduleBindingUpdate() {
            pendingBindingUpdate?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, let textView = self.textView else {
                    return
                }
                self.parent.text = textView.string
            }
            pendingBindingUpdate = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }

        func scheduleTokenization() {
            guard textView != nil else {
                return
            }

            pendingTokenization?.cancel()
            generation += 1
            let currentGeneration = generation

            let workItem = DispatchWorkItem { [weak self] in
                guard let self,
                      self.generation == currentGeneration,
                      let snapshot = self.textView?.string else {
                    return
                }
                let syntax = self.parent.syntax
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let newTokens = syntax.tokenize(snapshot)
                    DispatchQueue.main.async { [weak self] in
                        guard let self,
                              self.generation == currentGeneration else {
                            return
                        }
                        self.tokenizedGeneration = currentGeneration
                        self.tokens = newTokens
                        self.applyVisibleHighlight()
                    }
                }
            }

            pendingTokenization = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
        }

        func applyVisibleHighlight() {
            guard let textView,
                  let scrollView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return
            }

            let textLength = textView.textStorage?.length ?? 0
            guard textLength > 0 else {
                return
            }

            let glyphRange = layoutManager.glyphRange(
                forBoundingRect: scrollView.contentView.bounds,
                in: textContainer
            )
            let visibleRange = layoutManager.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            )
            let buffer = 2_000
            let start = max(0, visibleRange.location - buffer)
            let end = min(textLength, NSMaxRange(visibleRange) + buffer)
            guard end > start else {
                return
            }

            let targetRange = NSRange(location: start, length: end - start)
            guard tokenizedGeneration == generation else {
                return
            }

            layoutManager.addTemporaryAttribute(
                .foregroundColor,
                value: NSColor.labelColor,
                forCharacterRange: targetRange
            )

            var index = firstTokenIndex(overlapping: targetRange)
            while index < tokens.count {
                let token = tokens[index]
                if token.range.location >= end {
                    break
                }
                let intersection = NSIntersectionRange(token.range, targetRange)
                if intersection.length > 0 {
                    layoutManager.addTemporaryAttribute(
                        .foregroundColor,
                        value: token.kind.color,
                        forCharacterRange: intersection
                    )
                }
                index += 1
            }
        }

        private func firstTokenIndex(overlapping range: NSRange) -> Int {
            var lowerBound = 0
            var upperBound = tokens.count
            while lowerBound < upperBound {
                let middle = (lowerBound + upperBound) / 2
                if NSMaxRange(tokens[middle].range) < range.location {
                    lowerBound = middle + 1
                } else {
                    upperBound = middle
                }
            }
            return lowerBound
        }
    }
}

enum EditorFindAction {
    private static weak var activeTextView: NSTextView?

    static func activate(_ textView: NSTextView) {
        activeTextView = textView
    }

    static func clear(_ textView: NSTextView) {
        if activeTextView === textView {
            activeTextView = nil
        }
    }

    static func deactivate() {
        activeTextView = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    static func show() {
        let focusedTextView = NSApp.keyWindow?.firstResponder as? NSTextView
        guard let textView = focusedTextView ?? activeTextView else {
            NSSound.beep()
            return
        }

        textView.window?.makeFirstResponder(textView)
        let menuItem = NSMenuItem()
        menuItem.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        textView.performFindPanelAction(menuItem)
    }
}

struct EditorSyntaxToken {
    let range: NSRange
    let kind: EditorSyntaxKind
}

enum EditorSyntaxKind: Equatable {
    case key
    case string
    case number
    case keyword
    case punctuation

    var color: NSColor {
        switch self {
        case .key:
            return .systemBlue
        case .string:
            return .systemGreen
        case .number:
            return .systemOrange
        case .keyword:
            return .systemPurple
        case .punctuation:
            return .secondaryLabelColor
        }
    }
}

enum JSONSyntaxHighlighter {
    static func tokenize(_ source: String) -> [EditorSyntaxToken] {
        let text = source as NSString
        let length = text.length
        var tokens: [EditorSyntaxToken] = []
        tokens.reserveCapacity(min(length / 5, 100_000))

        var index = 0
        while index < length {
            let character = text.character(at: index)

            if character == 34 {
                let start = index
                index += 1
                var escaped = false
                while index < length {
                    let next = text.character(at: index)
                    index += 1
                    if escaped {
                        escaped = false
                    } else if next == 92 {
                        escaped = true
                    } else if next == 34 {
                        break
                    }
                }

                var lookahead = index
                while lookahead < length, isWhitespace(text.character(at: lookahead)) {
                    lookahead += 1
                }
                let kind: EditorSyntaxKind = lookahead < length && text.character(at: lookahead) == 58
                    ? .key
                    : .string
                tokens.append(EditorSyntaxToken(range: NSRange(location: start, length: index - start), kind: kind))
                continue
            }

            if character == 45 || isDigit(character) {
                let start = index
                index += 1
                while index < length, isNumberCharacter(text.character(at: index)) {
                    index += 1
                }
                tokens.append(EditorSyntaxToken(range: NSRange(location: start, length: index - start), kind: .number))
                continue
            }

            if matches("true", in: text, at: index) {
                tokens.append(EditorSyntaxToken(range: NSRange(location: index, length: 4), kind: .keyword))
                index += 4
                continue
            }
            if matches("false", in: text, at: index) {
                tokens.append(EditorSyntaxToken(range: NSRange(location: index, length: 5), kind: .keyword))
                index += 5
                continue
            }
            if matches("null", in: text, at: index) {
                tokens.append(EditorSyntaxToken(range: NSRange(location: index, length: 4), kind: .keyword))
                index += 4
                continue
            }

            if character == 123 || character == 125 || character == 91 || character == 93 || character == 58 || character == 44 {
                tokens.append(EditorSyntaxToken(range: NSRange(location: index, length: 1), kind: .punctuation))
            }
            index += 1
        }

        return tokens
    }

    private static func matches(_ word: String, in text: NSString, at index: Int) -> Bool {
        let wordLength = (word as NSString).length
        guard index + wordLength <= text.length else {
            return false
        }
        return text.substring(with: NSRange(location: index, length: wordLength)) == word
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        character == 32 || character == 9 || character == 10 || character == 13
    }

    private static func isDigit(_ character: unichar) -> Bool {
        character >= 48 && character <= 57
    }

    private static func isNumberCharacter(_ character: unichar) -> Bool {
        isDigit(character) || character == 43 || character == 45 || character == 46 || character == 69 || character == 101
    }
}

enum SQLSyntaxHighlighter {
    static func tokenize(_ source: String) -> [EditorSyntaxToken] {
        var tokenizer = SQLTokenizer(source, strict: false)
        guard let tokens = try? tokenizer.tokenize() else {
            return []
        }
        var result: [EditorSyntaxToken] = []
        result.reserveCapacity(tokens.count)
        for token in tokens {
            guard let kind = kind(for: token) else {
                continue
            }
            result.append(EditorSyntaxToken(
                range: NSRange(location: token.utf16Location, length: token.utf16Length),
                kind: kind
            ))
        }
        return result
    }

    private static func kind(for token: SQLToken) -> EditorSyntaxKind? {
        switch token.kind {
        case .word:
            return SQLFormatter.isStylizedWord(token.text) ? .keyword : nil
        case .string:
            return .string
        case .quotedIdentifier, .parameter:
            return .key
        case .number:
            return .number
        case .lineComment, .blockComment, .openParen, .closeParen, .comma, .semicolon, .dot:
            return .punctuation
        case .doubleColon, .op:
            return nil
        }
    }
}
