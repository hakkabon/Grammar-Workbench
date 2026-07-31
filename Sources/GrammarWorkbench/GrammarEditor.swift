import SwiftUI
import AppKit

struct GrammarQuickFix: Identifiable, Equatable {
    let id: String
    let title: String
    let replacementRange: Range<Int>
    let replacement: String

    func applying(to source: String) -> String {
        guard replacementRange.lowerBound >= 0,
              replacementRange.upperBound <= source.count,
              let lower = source.index(source.startIndex, offsetBy: replacementRange.lowerBound, limitedBy: source.endIndex),
              let upper = source.index(source.startIndex, offsetBy: replacementRange.upperBound, limitedBy: source.endIndex) else {
            return source
        }
        var result = source
        result.replaceSubrange(lower..<upper, with: replacement)
        return result
    }
}

enum GrammarEditorIntelligence {
    static func completions(for result: GrammarFrontEndResult) -> [String] {
        let directives = ["%start", "%token", "%skip", "%left", "%right", "%nonassoc", "%expect"]
        return Array(Set(directives + (result.grammar?.nonterminals ?? []) + (result.grammar?.terminals ?? []))).sorted()
    }

    static func quickFixes(for diagnostic: GrammarDiagnostic, source: String) -> [GrammarQuickFix] {
        if diagnostic.code == "undefined-symbol",
           diagnostic.range.start.offset < diagnostic.range.end.offset,
           diagnostic.range.end.offset <= source.count,
           let start = source.index(source.startIndex, offsetBy: diagnostic.range.start.offset, limitedBy: source.endIndex),
           let end = source.index(source.startIndex, offsetBy: diagnostic.range.end.offset, limitedBy: source.endIndex) {
            let symbol = String(source[start..<end])
            return [.init(
                id: "declare-token-\(symbol)",
                title: "Declare ‘\(symbol)’ with %token",
                replacementRange: 0..<0,
                replacement: "%token \(symbol)\n"
            )]
        }
        if diagnostic.message.hasPrefix("Expected ‘;’") {
            let offset = min(diagnostic.range.start.offset, source.count)
            return [.init(id: "insert-semicolon-\(offset)", title: "Insert missing ‘;’", replacementRange: offset..<offset, replacement: ";")]
        }
        if diagnostic.message.hasPrefix("Expected ‘:’ after nonterminal") {
            let offset = min(diagnostic.range.start.offset, source.count)
            return [.init(id: "insert-colon-\(offset)", title: "Insert missing ‘:’", replacementRange: offset..<offset, replacement: ": ")]
        }
        if diagnostic.message.hasPrefix("Unknown directive") {
            let range = diagnostic.range.start.offset..<diagnostic.range.end.offset
            return ["%start", "%token", "%skip", "%left", "%right", "%nonassoc", "%expect"].map {
                .init(id: "replace-directive-\($0)", title: "Replace with \($0)", replacementRange: range, replacement: $0)
            }
        }
        return []
    }
}

struct GrammarSourceEditor: NSViewRepresentable {
    @Binding var text: String
    let diagnostics: [GrammarDiagnostic]
    let selectedRange: SourceRange?
    let completions: [String]
    let isEditable: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView

        let ruler = GrammarLineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.completions = completions
        context.coordinator.applyDecorations(diagnostics: diagnostics, selectedRange: selectedRange)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.parentText = $text
        context.coordinator.completions = completions
        textView.isEditable = isEditable
        if textView.string != text {
            context.coordinator.isApplyingUpdate = true
            textView.string = text
            context.coordinator.isApplyingUpdate = false
        }
        context.coordinator.applyDecorations(diagnostics: diagnostics, selectedRange: selectedRange)
        context.coordinator.ruler?.needsDisplay = true
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parentText: Binding<String>
        weak var textView: NSTextView?
        weak var ruler: GrammarLineNumberRulerView?
        var completions: [String] = []
        var isApplyingUpdate = false

        init(text: Binding<String>) {
            self.parentText = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingUpdate, let textView else { return }
            parentText.wrappedValue = textView.string
            ruler?.needsDisplay = true
        }

        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            let partial = (textView.string as NSString).substring(with: charRange)
            return completions.filter {
                partial.isEmpty || $0.range(of: partial, options: [.anchored, .caseInsensitive]) != nil
            }
        }

        func applyDecorations(diagnostics: [GrammarDiagnostic], selectedRange: SourceRange?) {
            guard let textView, let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.textColor
            ], range: fullRange)
            apply(pattern: #"(?m)(//|#).*$"#, color: .systemGray, to: storage)
            apply(pattern: #"%[A-Za-z]+"#, color: .systemPurple, fontWeight: .semibold, to: storage)
            apply(pattern: #"'(?:\\.|[^'])*'|"(?:\\.|[^"])*""#, color: .systemRed, to: storage)
            apply(pattern: #"(?m)^[ \t]*([A-Za-z_][A-Za-z0-9_′]*)[ \t]*:"#,
                  color: .systemBlue, fontWeight: .semibold, captureGroup: 1, to: storage)
            apply(pattern: #"[:|;]"#, color: .systemOrange, fontWeight: .bold, to: storage)

            for diagnostic in diagnostics {
                var range = nsRange(diagnostic.range, in: textView.string)
                guard range.location != NSNotFound else { continue }
                if range.length == 0, range.location > 0 {
                    range = NSRange(location: range.location - 1, length: 1)
                }
                guard range.length > 0 else { continue }
                storage.addAttributes([
                    .underlineStyle: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.thick.rawValue,
                    .underlineColor: diagnostic.severity == .error ? NSColor.systemRed : NSColor.systemOrange
                ], range: range)
            }
            if let selectedRange {
                let range = nsRange(selectedRange, in: textView.string)
                if range.location != NSNotFound {
                    storage.addAttribute(.backgroundColor, value: NSColor.selectedContentBackgroundColor.withAlphaComponent(0.28), range: range)
                    textView.scrollRangeToVisible(range)
                }
            }
            storage.endEditing()
        }

        private func apply(
            pattern: String,
            color: NSColor,
            fontWeight: NSFont.Weight? = nil,
            captureGroup: Int = 0,
            to storage: NSTextStorage
        ) {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
            let range = NSRange(location: 0, length: storage.length)
            for match in expression.matches(in: storage.string, range: range) {
                let matchRange = match.range(at: captureGroup)
                guard matchRange.location != NSNotFound else { continue }
                storage.addAttribute(.foregroundColor, value: color, range: matchRange)
                if let fontWeight {
                    storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: fontWeight), range: matchRange)
                }
            }
        }

        private func nsRange(_ sourceRange: SourceRange, in source: String) -> NSRange {
            guard sourceRange.start.offset <= source.count,
                  sourceRange.end.offset <= source.count,
                  let start = source.index(source.startIndex, offsetBy: sourceRange.start.offset, limitedBy: source.endIndex),
                  let end = source.index(source.startIndex, offsetBy: sourceRange.end.offset, limitedBy: source.endIndex) else {
                return NSRange(location: NSNotFound, length: 0)
            }
            return NSRange(start..<end, in: source)
        }
    }
}

final class GrammarLineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 42
        NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSText.didChangeNotification, object: textView)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func redraw() {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let scrollView else { return }
        NSColor.windowBackgroundColor.setFill()
        rect.fill()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let lineHeight = textView.layoutManager?.defaultLineHeight(for: textView.font ?? font) ?? 15
        let visible = scrollView.contentView.bounds
        let inset = textView.textContainerInset.height
        let firstLine = max(0, Int((visible.minY - inset) / lineHeight))
        let totalLines = max(1, textView.string.reduce(1) { $1 == "\n" ? $0 + 1 : $0 })
        let visibleCount = Int(visible.height / lineHeight) + 2
        for line in firstLine..<min(totalLines, firstLine + visibleCount) {
            let value = "\(line + 1)" as NSString
            let size = value.size(withAttributes: attributes)
            let point = NSPoint(x: ruleThickness - size.width - 7, y: inset + CGFloat(line) * lineHeight - visible.minY)
            value.draw(at: point, withAttributes: attributes)
        }
    }
}
