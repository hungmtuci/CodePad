import AppKit
import SwiftUI

struct NativeCodeEditorView: NSViewRepresentable {
    let tabID: UUID
    let text: String
    let language: CodeLanguage
    let palette: EditorThemePalette
    let preferences: EditorPreferences
    let pendingCommand: (id: UUID, cmd: EditorActionCommand)?
    let onTextChange: (_ newText: String, _ isFromPaste: Bool) -> Void
    let onCursorChange: (_ line: Int, _ column: Int, _ selectedCount: Int) -> Void
    let onScrollFractionChange: (_ fraction: Double) -> Void
    let onOpenDroppedFile: (_ url: URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CodeEditorContainerNSView {
        let container = CodeEditorContainerNSView()
        container.configure(coordinator: context.coordinator, initialParent: self)
        return container
    }

    func updateNSView(_ nsView: CodeEditorContainerNSView, context: Context) {
        context.coordinator.parent = self
        nsView.sync(with: self, coordinator: context.coordinator)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeCodeEditorView
        weak var containerView: CodeEditorContainerNSView?
        var isProgrammaticUpdate = false
        var lastHandledCommandID: UUID?
        var lastTabID: UUID?
        var lastLanguage: CodeLanguage?
        var lastPalette: EditorThemePalette?
        var lastFontKey: String = ""
        var lastWordWrap: Bool?
        private var highlightWorkItem: DispatchWorkItem?

        init(parent: NativeCodeEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate,
                  let textView = notification.object as? CodeTextView else { return }

            let wasPaste = textView.consumeJustPastedFlag()
            let currentString = textView.string
            parent.onTextChange(currentString, wasPaste)

            // Never mutate textStorage attributes mid-IME composition (preserves Vietnamese Telex/VNI!)
            if !textView.hasMarkedText() {
                scheduleSyntaxHighlight(immediate: wasPaste)
            }
            containerView?.refreshGutterAndMinimap()
            reportCursorTelemetry(from: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? CodeTextView else { return }
            textView.needsDisplay = true
            containerView?.gutterView.needsDisplay = true
            reportCursorTelemetry(from: textView)
        }

        func scheduleSyntaxHighlight(immediate: Bool) {
            highlightWorkItem?.cancel()
            if immediate {
                containerView?.reapplySyntaxHighlighting()
                return
            }
            let item = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self, let tv = self.containerView?.textView, !tv.hasMarkedText() else { return }
                    self.containerView?.reapplySyntaxHighlighting()
                }
            }
            highlightWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: item)
        }

        func reportCursorTelemetry(from textView: NSTextView) {
            let sel = textView.selectedRange()
            let ns = textView.string as NSString
            let safeLoc = min(sel.location, ns.length)

            var line = 1
            var lastNewlineIdx = 0
            if safeLoc > 0 {
                var idx = 0
                while idx < safeLoc {
                    if ns.character(at: idx) == 10 {
                        line += 1
                        lastNewlineIdx = idx + 1
                    }
                    idx += 1
                }
            }
            let col = (safeLoc - lastNewlineIdx) + 1
            parent.onCursorChange(line, col, sel.length)
        }
    }
}

// MARK: - Container View (Gutter + ScrollView/TextView + Sublime Minimap)

@MainActor
final class CodeEditorContainerNSView: NSView {
    let gutterView = CodeLineNumberGutterView()
    let scrollView = NSScrollView()
    let minimapView = SublimeMinimapView()
    private(set) var textView: CodeTextView!
    private var textStorageRef: NSTextStorage!
    private var layoutManagerRef: NSLayoutManager!
    private var textContainerRef: NSTextContainer!

    private var gutterWidthConstraint: NSLayoutConstraint!
    private var minimapWidthConstraint: NSLayoutConstraint!
    private weak var coordinator: NativeCodeEditorView.Coordinator?

    private var regularFont: NSFont = .monospacedSystemFont(ofSize: 13.5, weight: .regular)
    private var boldFont: NSFont = .monospacedSystemFont(ofSize: 13.5, weight: .semibold)
    private var italicFont: NSFont = .monospacedSystemFont(ofSize: 13.5, weight: .regular)
    private var currentPalette: EditorThemePalette = EditorThemeID.monokaiPro.palette
    private var currentLanguage: CodeLanguage = .plainText
    private var currentParagraphStyle = NSMutableParagraphStyle()
    private var isWordWrapActive: Bool = true
    private var lastSyncedContentWidth: CGFloat = 0

    override var isOpaque: Bool { true }

    func configure(coordinator: NativeCodeEditorView.Coordinator, initialParent: NativeCodeEditorView) {
        self.coordinator = coordinator
        coordinator.containerView = self

        // CRITICAL on macOS 14+: NSView.clipsToBounds defaults to false!
        // Always enable clipsToBounds so custom draw(_:) never paints outside subview bounds.
        wantsLayer = true
        clipsToBounds = true
        gutterView.wantsLayer = true
        gutterView.clipsToBounds = true
        scrollView.wantsLayer = true
        scrollView.clipsToBounds = true
        minimapView.wantsLayer = true
        minimapView.clipsToBounds = true

        // Explicit TextKit 1 stack for rock-solid line metrics & zero flicker
        textStorageRef = NSTextStorage()
        layoutManagerRef = NSLayoutManager()
        textStorageRef.addLayoutManager(layoutManagerRef)

        textContainerRef = NSTextContainer(containerSize: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
        textContainerRef.lineFragmentPadding = 8
        textContainerRef.widthTracksTextView = true
        layoutManagerRef.addTextContainer(textContainerRef)

        textView = CodeTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), textContainer: textContainerRef)
        textView.minSize = NSSize(width: 120, height: 120)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.drawsBackground = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.textContainerInset = NSSize(width: 10, height: 14)
        textView.delegate = coordinator
        textView.onFileURLDropped = { [weak coordinator] url in
            coordinator?.parent.onOpenDroppedFile(url)
        }

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !initialParent.preferences.wordWrap
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.borderType = .noBorder
        scrollView.contentView.postsBoundsChangedNotifications = true

        gutterView.textView = textView
        gutterView.layoutManager = layoutManagerRef

        minimapView.onScrubToFraction = { [weak self] fraction in
            self?.scrollEditor(toFraction: fraction)
        }

        gutterView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        minimapView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(gutterView)
        addSubview(scrollView)
        addSubview(minimapView)

        gutterWidthConstraint = gutterView.widthAnchor.constraint(equalToConstant: 48)
        minimapWidthConstraint = minimapView.widthAnchor.constraint(equalToConstant: 76)

        NSLayoutConstraint.activate([
            gutterView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gutterView.topAnchor.constraint(equalTo: topAnchor),
            gutterView.bottomAnchor.constraint(equalTo: bottomAnchor),
            gutterWidthConstraint,

            scrollView.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.trailingAnchor.constraint(equalTo: minimapView.leadingAnchor),

            minimapView.trailingAnchor.constraint(equalTo: trailingAnchor),
            minimapView.topAnchor.constraint(equalTo: topAnchor),
            minimapView.bottomAnchor.constraint(equalTo: bottomAnchor),
            minimapWidthConstraint
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        sync(with: initialParent, coordinator: coordinator)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        scrollView.layoutSubtreeIfNeeded()
        syncTextViewWidthToScrollViewIfNeeded()
    }

    private func syncTextViewWidthToScrollViewIfNeeded() {
        let contentW = max(140, scrollView.contentSize.width)
        let contentH = max(140, scrollView.contentSize.height)
        textView.minSize = NSSize(width: contentW, height: contentH)

        if isWordWrapActive {
            if abs(contentW - lastSyncedContentWidth) > 0.5 || abs(textView.frame.width - contentW) > 0.5 {
                lastSyncedContentWidth = contentW
                var f = textView.frame
                f.size.width = contentW
                f.size.height = max(f.size.height, contentH)
                textView.frame = f
                textContainerRef.containerSize = NSSize(width: max(80, contentW - textView.textContainerInset.width * 2), height: .greatestFiniteMagnitude)
                layoutManagerRef.ensureLayout(for: textContainerRef)
                gutterView.needsDisplay = true
                updateMinimapViewportAndReportScroll()
            }
        } else {
            if textView.frame.width < contentW {
                var f = textView.frame
                f.size.width = contentW
                textView.frame = f
            }
        }
    }

    @objc private func clipViewBoundsDidChange(_ notification: Notification) {
        gutterView.needsDisplay = true
        updateMinimapViewportAndReportScroll()
    }

    private func updateMinimapViewportAndReportScroll() {
        let docHeight = max(1, textView.bounds.height)
        let visRect = scrollView.contentView.documentVisibleRect
        let maxScroll = max(1, docHeight - visRect.height)
        let frac = min(1.0, max(0.0, Double(visRect.minY / maxScroll)))
        minimapView.viewportStartFraction = CGFloat(min(1.0, max(0.0, visRect.minY / docHeight)))
        minimapView.viewportHeightFraction = CGFloat(min(1.0, max(0.05, visRect.height / docHeight)))
        minimapView.needsDisplay = true
        coordinator?.parent.onScrollFractionChange(frac)
    }

    private func scrollEditor(toFraction fraction: CGFloat) {
        let docHeight = textView.bounds.height
        let visHeight = scrollView.contentView.bounds.height
        guard docHeight > visHeight else { return }
        let targetY = max(0, min(docHeight - visHeight, fraction * docHeight - visHeight * 0.5))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        gutterView.needsDisplay = true
        updateMinimapViewportAndReportScroll()
    }

    func sync(with state: NativeCodeEditorView, coordinator: NativeCodeEditorView.Coordinator) {
        let prefs = state.preferences
        let fontKey = "\(prefs.fontFamily)-\(prefs.fontSize)"
        let tabChanged = (coordinator.lastTabID != state.tabID)
        let langChanged = (coordinator.lastLanguage != state.language)
        let paletteChanged = (coordinator.lastPalette != state.palette)
        let fontChanged = (coordinator.lastFontKey != fontKey)
        let wrapChanged = (coordinator.lastWordWrap != prefs.wordWrap)

        currentPalette = state.palette
        currentLanguage = state.language
        layer?.backgroundColor = state.palette.editorBackgroundNS.cgColor

        textView.tabWidth = prefs.tabWidth
        textView.useSpacesForTabs = prefs.useSpacesForTabs
        textView.activeLanguage = state.language
        textView.activeLineColor = state.palette.activeLineNS

        let targetGutterWidth: CGFloat = prefs.showLineNumbers ? computeGutterWidth(for: state.text) : 0
        if gutterWidthConstraint.constant != targetGutterWidth {
            gutterWidthConstraint.constant = targetGutterWidth
            gutterView.isHidden = !prefs.showLineNumbers
        }

        let targetMinimapWidth: CGFloat = prefs.showMinimap ? 76 : 0
        if minimapWidthConstraint.constant != targetMinimapWidth {
            minimapWidthConstraint.constant = targetMinimapWidth
            minimapView.isHidden = !prefs.showMinimap
        }

        if fontChanged {
            let sz = CGFloat(prefs.fontSize)
            regularFont = SyntaxHighlighter.resolveMonoFont(family: prefs.fontFamily, size: sz, weight: .regular, italic: false)
            boldFont = SyntaxHighlighter.resolveMonoFont(family: prefs.fontFamily, size: sz, weight: .semibold, italic: false)
            italicFont = SyntaxHighlighter.resolveMonoFont(family: prefs.fontFamily, size: sz, weight: .regular, italic: true)
            currentParagraphStyle = NSMutableParagraphStyle()
            currentParagraphStyle.lineSpacing = 3.0
            gutterView.font = SyntaxHighlighter.resolveMonoFont(family: prefs.fontFamily, size: max(10.5, sz - 2.0), weight: .regular, italic: false)
            coordinator.lastFontKey = fontKey
        }

        if wrapChanged {
            isWordWrapActive = prefs.wordWrap
            lastSyncedContentWidth = 0
            applyWordWrap(prefs.wordWrap)
            coordinator.lastWordWrap = prefs.wordWrap
        }

        if paletteChanged || fontChanged {
            scrollView.backgroundColor = state.palette.editorBackgroundNS
            textView.backgroundColor = state.palette.editorBackgroundNS
            textView.insertionPointColor = state.palette.caretNS
            textView.selectedTextAttributes = [
                .backgroundColor: state.palette.selectionNS
            ]
            textView.typingAttributes = [
                .font: regularFont,
                .foregroundColor: state.palette.plainTextNS,
                .paragraphStyle: currentParagraphStyle
            ]
            gutterView.palette = state.palette
            gutterView.needsDisplay = true
            minimapView.palette = state.palette
            minimapView.needsDisplay = true
            coordinator.lastPalette = state.palette
        }

        let needsTextSwap = (textView.string != state.text) && !textView.hasMarkedText()
        if needsTextSwap {
            coordinator.isProgrammaticUpdate = true
            let prevSel = textView.selectedRange()
            textView.string = state.text
            let newLen = (state.text as NSString).length
            let restoredLoc = tabChanged ? 0 : min(prevSel.location, newLen)
            textView.setSelectedRange(NSRange(location: restoredLoc, length: 0))
            if tabChanged {
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            coordinator.isProgrammaticUpdate = false
        }

        if tabChanged || needsTextSwap || langChanged || paletteChanged || fontChanged {
            if !textView.hasMarkedText() {
                reapplySyntaxHighlighting()
            }
            let wasFirstTabAttach = (coordinator.lastTabID == nil)
            coordinator.lastTabID = state.tabID
            coordinator.lastLanguage = state.language
            syncTextViewWidthToScrollViewIfNeeded()
            refreshGutterAndMinimap()
            coordinator.reportCursorTelemetry(from: textView)

            if tabChanged || wasFirstTabAttach {
                DispatchQueue.main.async { [weak self] in
                    guard let self, let win = self.window else { return }
                    if win.firstResponder === win || win.firstResponder == nil {
                        win.makeFirstResponder(self.textView)
                    }
                }
            }
        }

        if let pending = state.pendingCommand, pending.id != coordinator.lastHandledCommandID {
            coordinator.lastHandledCommandID = pending.id
            textView.performEditorCommand(pending.cmd)
        }
    }

    private func applyWordWrap(_ wrap: Bool) {
        scrollView.hasHorizontalScroller = !wrap
        let contentW = max(240, scrollView.contentSize.width)
        if wrap {
            textContainerRef.widthTracksTextView = true
            textContainerRef.containerSize = NSSize(width: contentW, height: .greatestFiniteMagnitude)
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            var f = textView.frame
            f.size.width = contentW
            textView.frame = f
        } else {
            textContainerRef.widthTracksTextView = false
            textContainerRef.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = [.width, .height]
        }
        textView.needsLayout = true
        textView.needsDisplay = true
    }

    private func computeGutterWidth(for text: String) -> CGFloat {
        var lines = 1
        for ch in text where ch == "\n" { lines += 1 }
        let digits = max(2, String(lines).count)
        return CGFloat(digits) * 8.5 + 28
    }

    func reapplySyntaxHighlighting() {
        let wasProg = coordinator?.isProgrammaticUpdate ?? false
        coordinator?.isProgrammaticUpdate = true
        SyntaxHighlighter.applyHighlighting(
            to: textStorageRef,
            language: currentLanguage,
            palette: currentPalette,
            regularFont: regularFont,
            boldFont: boldFont,
            italicFont: italicFont,
            paragraphStyle: currentParagraphStyle
        )
        textView.typingAttributes = [
            .font: regularFont,
            .foregroundColor: currentPalette.plainTextNS,
            .paragraphStyle: currentParagraphStyle
        ]
        coordinator?.isProgrammaticUpdate = wasProg
        textView.needsDisplay = true
        minimapView.updateSnapshot(from: textStorageRef, palette: currentPalette)
    }

    func refreshGutterAndMinimap() {
        if !gutterView.isHidden {
            let newW = computeGutterWidth(for: textView.string)
            if abs(gutterWidthConstraint.constant - newW) > 1 {
                gutterWidthConstraint.constant = newW
            }
            gutterView.needsDisplay = true
        }
        if !minimapView.isHidden {
            updateMinimapViewportAndReportScroll()
        }
    }
}

// MARK: - Sublime-Inspired Custom NSTextView

final class CodeTextView: NSTextView {
    var tabWidth: Int = 4
    var useSpacesForTabs: Bool = true
    var activeLanguage: CodeLanguage = .plainText
    var activeLineColor: NSColor = NSColor.white.withAlphaComponent(0.06)
    var onFileURLDropped: ((URL) -> Void)?

    private var didJustPasteFlag = false

    func consumeJustPastedFlag() -> Bool {
        let v = didJustPasteFlag
        didJustPasteFlag = false
        return v
    }

    override func drawBackground(in rect: NSRect) {
        let clipped = rect.intersection(bounds)
        guard !clipped.isEmpty else { return }
        super.drawBackground(in: clipped)

        // Draw subtle active cursor line highlight across full editor width
        guard let lm = layoutManager, let tc = textContainer else { return }
        let sel = selectedRange()
        guard sel.length == 0 else { return }
        let ns = string as NSString
        let origin = textContainerOrigin

        var lineRect: NSRect
        if ns.length == 0 {
            let h = (font?.pointSize ?? 14) * 1.45
            lineRect = NSRect(x: 0, y: origin.y, width: bounds.width, height: h)
        } else if sel.location == ns.length && ns.character(at: ns.length - 1) == 10 {
            let lastGlyph = lm.glyphIndexForCharacter(at: ns.length - 1)
            let prevRect = lm.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
            lineRect = NSRect(x: 0, y: origin.y + prevRect.maxY, width: bounds.width, height: prevRect.height)
        } else {
            let safeChar = min(sel.location, max(0, ns.length - 1))
            let glyphIdx = lm.glyphIndexForCharacter(at: safeChar)
            var frag = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
            if frag.height == 0 {
                frag = lm.extraLineFragmentRect
            }
            let _ = tc
            lineRect = NSRect(x: 0, y: origin.y + frag.minY - 1, width: bounds.width, height: max(18, frag.height + 2))
        }

        let targetFill = lineRect.intersection(clipped)
        if !targetFill.isEmpty {
            activeLineColor.setFill()
            targetFill.fill()
        }
    }

    override func paste(_ sender: Any?) {
        didJustPasteFlag = true
        super.pasteAsPlainText(sender)
    }

    override func insertNewline(_ sender: Any?) {
        if hasMarkedText() {
            super.insertNewline(sender)
            return
        }
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let lineUpToCursor = ns.substring(with: NSRange(location: lineRange.location, length: sel.location - lineRange.location))

        let leadingWhitespace = String(lineUpToCursor.prefix { $0 == " " || $0 == "\t" })
        let trimmedBefore = lineUpToCursor.trimmingCharacters(in: .whitespaces)
        let indentUnit = useSpacesForTabs ? String(repeating: " ", count: tabWidth) : "\t"

        let opensBlock = trimmedBefore.hasSuffix("{")
            || trimmedBefore.hasSuffix("[")
            || trimmedBefore.hasSuffix("(")
            || trimmedBefore.hasSuffix(":")

        let nextChar: String = (sel.upperBound < ns.length)
            ? ns.substring(with: NSRange(location: sel.upperBound, length: 1))
            : ""

        if opensBlock && (nextChar == "}" || nextChar == "]" || nextChar == ")") {
            let inner = "\n\(leadingWhitespace)\(indentUnit)"
            let closing = "\n\(leadingWhitespace)"
            insertText(inner + closing, replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location + (inner as NSString).length, length: 0))
            return
        }

        let extra = opensBlock ? indentUnit : ""
        insertText("\n\(leadingWhitespace)\(extra)", replacementRange: sel)
    }

    override func insertTab(_ sender: Any?) {
        if hasMarkedText() {
            super.insertTab(sender)
            return
        }
        let sel = selectedRange()
        let indentUnit = useSpacesForTabs ? String(repeating: " ", count: tabWidth) : "\t"
        if sel.length > 0 && (string as NSString).substring(with: sel).contains("\n") {
            indentSelectedLines(outdent: false)
        } else {
            insertText(indentUnit, replacementRange: sel)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        indentSelectedLines(outdent: true)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if !hasMarkedText(),
           let str = insertString as? String,
           str.count == 1,
           let closing = Self.autoPairMap[str] {
            let sel = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
            if sel.length > 0 {
                let ns = string as NSString
                let wrapped = "\(str)\(ns.substring(with: sel))\(closing)"
                super.insertText(wrapped, replacementRange: sel)
                setSelectedRange(NSRange(location: sel.location + 1, length: sel.length))
                return
            }
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    private static let autoPairMap: [String: String] = [
        "{": "}",
        "[": "]",
        "(": ")"
    ]

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let firstFile = urls.first {
            onFileURLDropped?(firstFile)
            return true
        }
        return super.performDragOperation(sender)
    }

    // MARK: - Sublime Editor Action Commands

    func performEditorCommand(_ cmd: EditorActionCommand) {
        window?.makeFirstResponder(self)
        switch cmd {
        case .toggleComment:
            toggleLineOrBlockComment()
        case .indentSelection:
            indentSelectedLines(outdent: false)
        case .outdentSelection:
            indentSelectedLines(outdent: true)
        case .duplicateLine:
            duplicateCurrentLineOrSelection()
        case let .jumpToLine(lineNumber):
            jumpToLine(lineNumber)
        case let .findNext(query, caseSensitive):
            findOccurrence(query: query, forward: true, caseSensitive: caseSensitive)
        case let .findPrevious(query, caseSensitive):
            findOccurrence(query: query, forward: false, caseSensitive: caseSensitive)
        case let .replaceCurrent(query, replacement, caseSensitive):
            replaceCurrentOccurrence(query: query, replacement: replacement, caseSensitive: caseSensitive)
        case let .replaceAll(query, replacement, caseSensitive):
            replaceAllOccurrences(query: query, replacement: replacement, caseSensitive: caseSensitive)
        }
    }

    private func indentSelectedLines(outdent: Bool) {
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: sel)
        let block = ns.substring(with: lineRange)
        let indentUnit = useSpacesForTabs ? String(repeating: " ", count: tabWidth) : "\t"

        let hasTrailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hasTrailingNewline && lines.last == "" {
            lines.removeLast()
        }

        let transformed = lines.map { line -> String in
            if outdent {
                if line.hasPrefix("\t") {
                    return String(line.dropFirst())
                }
                var spacesRemoved = 0
                var copy = line
                while spacesRemoved < tabWidth && copy.first == " " {
                    copy.removeFirst()
                    spacesRemoved += 1
                }
                return copy
            } else {
                return line.isEmpty ? line : indentUnit + line
            }
        }

        let result = transformed.joined(separator: "\n") + (hasTrailingNewline ? "\n" : "")
        if shouldChangeText(in: lineRange, replacementString: result) {
            replaceCharacters(in: lineRange, with: result)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: (result as NSString).length))
        }
    }

    private func toggleLineOrBlockComment() {
        let ns = string as NSString
        let sel = selectedRange()

        if let prefix = activeLanguage.lineCommentPrefix {
            let trimmedPrefix = prefix.trimmingCharacters(in: .whitespaces)
            let lineRange = ns.lineRange(for: sel)
            let block = ns.substring(with: lineRange)
            let hasTrailingNL = block.hasSuffix("\n")
            var lines = block.components(separatedBy: "\n")
            if hasTrailingNL && lines.last == "" { lines.removeLast() }

            let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let allCommented = !nonEmpty.isEmpty && nonEmpty.allSatisfy {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix(trimmedPrefix)
            }

            let updated = lines.map { line -> String in
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
                if allCommented {
                    if let r = line.range(of: prefix) {
                        var copy = line
                        copy.removeSubrange(r)
                        return copy
                    } else if let r2 = line.range(of: trimmedPrefix) {
                        var copy = line
                        copy.removeSubrange(r2)
                        return copy
                    }
                    return line
                } else {
                    return prefix + line
                }
            }

            let result = updated.joined(separator: "\n") + (hasTrailingNL ? "\n" : "")
            if shouldChangeText(in: lineRange, replacementString: result) {
                replaceCharacters(in: lineRange, with: result)
                didChangeText()
                setSelectedRange(NSRange(location: lineRange.location, length: (result as NSString).length))
            }
        } else if let pair = activeLanguage.blockCommentPair {
            let targetRange = sel.length > 0 ? sel : ns.lineRange(for: sel)
            let chunk = ns.substring(with: targetRange)
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            let result: String
            if trimmed.hasPrefix(pair.open.trimmingCharacters(in: .whitespaces)) && trimmed.hasSuffix(pair.close.trimmingCharacters(in: .whitespaces)) {
                result = chunk
                    .replacingOccurrences(of: pair.open, with: "")
                    .replacingOccurrences(of: pair.close, with: "")
                    .replacingOccurrences(of: pair.open.trimmingCharacters(in: .whitespaces), with: "")
                    .replacingOccurrences(of: pair.close.trimmingCharacters(in: .whitespaces), with: "")
            } else {
                result = "\(pair.open)\(chunk)\(pair.close)"
            }
            if shouldChangeText(in: targetRange, replacementString: result) {
                replaceCharacters(in: targetRange, with: result)
                didChangeText()
            }
        }
    }

    private func duplicateCurrentLineOrSelection() {
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: sel)
        let lineText = ns.substring(with: lineRange)
        let insertion = lineText.hasSuffix("\n") ? lineText : "\n" + lineText
        let insertAt = NSRange(location: lineRange.upperBound, length: 0)
        if shouldChangeText(in: insertAt, replacementString: insertion) {
            replaceCharacters(in: insertAt, with: insertion)
            didChangeText()
        }
    }

    private func jumpToLine(_ targetLine: Int) {
        let ns = string as NSString
        guard ns.length > 0 else { return }
        let clamped = max(1, targetLine)
        var currentLine = 1
        var charIndex = 0
        while charIndex < ns.length && currentLine < clamped {
            if ns.character(at: charIndex) == 10 {
                currentLine += 1
            }
            charIndex += 1
        }
        let range = NSRange(location: min(charIndex, ns.length), length: 0)
        setSelectedRange(range)
        scrollRangeToVisible(range)
    }

    private func findOccurrence(query: String, forward: Bool, caseSensitive: Bool) {
        guard !query.isEmpty else { return }
        let ns = string as NSString
        guard ns.length > 0 else { return }
        let baseOpts: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        let sel = selectedRange()

        let found: NSRange
        if forward {
            let start = min(sel.upperBound, ns.length)
            let firstTry = ns.range(of: query, options: baseOpts, range: NSRange(location: start, length: ns.length - start))
            found = firstTry.location != NSNotFound
                ? firstTry
                : ns.range(of: query, options: baseOpts, range: NSRange(location: 0, length: start))
        } else {
            let backOpts = baseOpts.union([.backwards])
            let end = sel.location
            let firstTry = ns.range(of: query, options: backOpts, range: NSRange(location: 0, length: end))
            found = firstTry.location != NSNotFound
                ? firstTry
                : ns.range(of: query, options: backOpts, range: NSRange(location: end, length: ns.length - end))
        }

        if found.location != NSNotFound {
            setSelectedRange(found)
            scrollRangeToVisible(found)
            showFindIndicator(for: found)
        }
    }

    private func replaceCurrentOccurrence(query: String, replacement: String, caseSensitive: Bool) {
        guard !query.isEmpty else { return }
        let ns = string as NSString
        let sel = selectedRange()
        if sel.length > 0 {
            let selectedStr = ns.substring(with: sel)
            let matches = caseSensitive
                ? (selectedStr == query)
                : (selectedStr.caseInsensitiveCompare(query) == .orderedSame)
            if matches, shouldChangeText(in: sel, replacementString: replacement) {
                replaceCharacters(in: sel, with: replacement)
                didChangeText()
            }
        }
        findOccurrence(query: query, forward: true, caseSensitive: caseSensitive)
    }

    private func replaceAllOccurrences(query: String, replacement: String, caseSensitive: Bool) {
        guard !query.isEmpty else { return }
        let opts: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        let updated = string.replacingOccurrences(of: query, with: replacement, options: opts)
        guard updated != string else { return }
        let full = NSRange(location: 0, length: (string as NSString).length)
        if shouldChangeText(in: full, replacementString: updated) {
            replaceCharacters(in: full, with: updated)
            didChangeText()
        }
    }
}

// MARK: - Line Number Gutter View

final class CodeLineNumberGutterView: NSView {
    weak var textView: NSTextView?
    weak var layoutManager: NSLayoutManager?
    var palette: EditorThemePalette = EditorThemeID.monokaiPro.palette
    var font: NSFont = .monospacedSystemFont(ofSize: 11.5, weight: .regular)

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let safeRect = dirtyRect.intersection(bounds)
        guard !safeRect.isEmpty else { return }

        palette.gutterBackgroundNS.setFill()
        safeRect.fill()

        // Subtle separator hairline strictly within bounds
        palette.gutterTextNS.withAlphaComponent(0.18).setFill()
        NSRect(x: bounds.maxX - 1, y: safeRect.minY, width: 1, height: safeRect.height).fill()

        guard let tv = textView,
              let lm = layoutManager,
              let tc = tv.textContainer,
              let clipView = tv.enclosingScrollView?.contentView else { return }

        let ns = tv.string as NSString
        let visRect = clipView.documentVisibleRect
        let origin = tv.textContainerOrigin
        let activeCharIndex = min(tv.selectedRange().location, ns.length)

        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: palette.gutterTextNS
        ]
        let activeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .semibold),
            .foregroundColor: palette.plainTextNS
        ]

        if ns.length == 0 {
            let label = "1" as NSString
            let sz = label.size(withAttributes: activeAttrs)
            label.draw(at: NSPoint(x: bounds.width - sz.width - 10, y: origin.y + 1), withAttributes: activeAttrs)
            return
        }

        let visibleGlyphRange = lm.glyphRange(forBoundingRect: visRect, in: tc)
        let firstVisibleChar = lm.characterIndexForGlyph(at: visibleGlyphRange.location)

        var lineNumber = 1
        var scanIdx = 0
        while scanIdx < firstVisibleChar && scanIdx < ns.length {
            if ns.character(at: scanIdx) == 10 {
                lineNumber += 1
            }
            scanIdx += 1
        }

        var glyphIdx = visibleGlyphRange.location
        while glyphIdx < NSMaxRange(visibleGlyphRange) {
            let charIdx = lm.characterIndexForGlyph(at: glyphIdx)
            let lineCharRange = ns.lineRange(for: NSRange(location: charIdx, length: 0))
            let lineGlyphRange = lm.glyphRange(forCharacterRange: lineCharRange, actualCharacterRange: nil)

            var fragRect = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
            fragRect.origin.y += origin.y - visRect.minY

            let isActiveLine = (activeCharIndex >= lineCharRange.location && activeCharIndex < NSMaxRange(lineCharRange))
                || (activeCharIndex == ns.length && NSMaxRange(lineCharRange) == ns.length && ns.character(at: max(0, ns.length - 1)) != 10)

            let attrs = isActiveLine ? activeAttrs : normalAttrs
            let label = "\(lineNumber)" as NSString
            let sz = label.size(withAttributes: attrs)
            let drawY = fragRect.minY + (fragRect.height - sz.height) * 0.5
            label.draw(at: NSPoint(x: bounds.width - sz.width - 10, y: drawY), withAttributes: attrs)

            lineNumber += 1
            glyphIdx = NSMaxRange(lineGlyphRange)
        }

        if ns.character(at: ns.length - 1) == 10 {
            let extraRect = lm.extraLineFragmentRect
            if extraRect.height > 0 {
                let y = extraRect.minY + origin.y - visRect.minY
                if y >= 0 && y <= bounds.height {
                    let isCursorOnTrailing = (activeCharIndex == ns.length)
                    let attrs = isCursorOnTrailing ? activeAttrs : normalAttrs
                    let label = "\(lineNumber)" as NSString
                    let sz = label.size(withAttributes: attrs)
                    label.draw(at: NSPoint(x: bounds.width - sz.width - 10, y: y + (extraRect.height - sz.height) * 0.5), withAttributes: attrs)
                }
            }
        }
    }
}

// MARK: - Sublime Text Signature Interactive Minimap

final class SublimeMinimapView: NSView {
    struct MiniLineSegment {
        let indent: CGFloat
        let width: CGFloat
        let color: NSColor
    }

    var palette: EditorThemePalette = EditorThemeID.monokaiPro.palette
    var viewportStartFraction: CGFloat = 0.0
    var viewportHeightFraction: CGFloat = 1.0
    var onScrubToFraction: ((CGFloat) -> Void)?

    private var miniLines: [[MiniLineSegment]] = []

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    func updateSnapshot(from storage: NSTextStorage, palette: EditorThemePalette) {
        self.palette = palette
        let str = storage.string
        guard !str.isEmpty else {
            miniLines = []
            needsDisplay = true
            return
        }

        let rawLines = str.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).prefix(650)
        var built: [[MiniLineSegment]] = []
        built.reserveCapacity(rawLines.count)

        let ns = storage.string as NSString
        var runningOffset = 0

        for lineSub in rawLines {
            let lineLen = (String(lineSub) as NSString).length
            guard lineLen > 0, runningOffset + lineLen <= ns.length else {
                built.append([])
                runningOffset += lineLen + 1
                continue
            }

            var segments: [MiniLineSegment] = []
            var pos = 0
            let maxCols = min(lineLen, 96)
            while pos < maxCols {
                let ch = ns.character(at: runningOffset + pos)
                if ch == 32 || ch == 9 {
                    pos += 1
                    continue
                }
                let segStart = pos
                let attrColor = (storage.attribute(.foregroundColor, at: runningOffset + pos, effectiveRange: nil) as? NSColor)
                    ?? palette.plainTextNS
                while pos < maxCols {
                    let c = ns.character(at: runningOffset + pos)
                    if c == 32 || c == 9 { break }
                    pos += 1
                }
                let segLen = pos - segStart
                segments.append(MiniLineSegment(
                    indent: CGFloat(segStart) * 0.68,
                    width: max(1.5, CGFloat(segLen) * 0.68),
                    color: attrColor.withAlphaComponent(0.75)
                ))
            }
            built.append(segments)
            runningOffset += lineLen + 1
        }

        miniLines = built
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Strictly clamp drawing inside self.bounds so macOS 14+ non-clipped dirtyRect never bleeds over siblings!
        let safeRect = dirtyRect.intersection(bounds)
        guard !safeRect.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()

        palette.chromeBackgroundNS.setFill()
        safeRect.fill()

        palette.gutterTextNS.withAlphaComponent(0.20).setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()

        let rowPitch: CGFloat = 2.8
        let totalRenderedHeight = CGFloat(miniLines.count) * rowPitch + 12
        let scrollOffset: CGFloat = totalRenderedHeight > bounds.height
            ? viewportStartFraction * (totalRenderedHeight - bounds.height)
            : 0

        for (rowIdx, segs) in miniLines.enumerated() {
            let y = 8 + CGFloat(rowIdx) * rowPitch - scrollOffset
            if y < 0 || y > bounds.height - 2 { continue }
            for seg in segs {
                let x = 6 + seg.indent
                guard x < bounds.width - 4 else { break }
                let w = min(seg.width, bounds.width - 4 - x)
                seg.color.setFill()
                NSRect(x: x, y: y, width: w, height: 1.5).fill()
            }
        }

        let effectiveTrack = min(bounds.height, max(36, totalRenderedHeight))
        let lensHeight = max(24, min(bounds.height, viewportHeightFraction * effectiveTrack))
        let lensY = min(bounds.height - lensHeight, max(0, viewportStartFraction * (effectiveTrack - lensHeight)))
        let lensRect = NSRect(x: 1, y: lensY, width: bounds.width - 2, height: lensHeight)
        NSColor.white.withAlphaComponent(palette.isDark ? 0.10 : 0.35).setFill()
        lensRect.fill()
        palette.gutterTextNS.withAlphaComponent(0.30).setStroke()
        NSBezierPath(rect: lensRect.insetBy(dx: 0.5, dy: 0.5)).stroke()

        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        scrub(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        scrub(with: event)
    }

    private func scrub(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let frac = min(1.0, max(0.0, pt.y / max(1, bounds.height)))
        onScrubToFraction?(frac)
    }
}
