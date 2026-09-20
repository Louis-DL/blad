import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Bridges the AppKit text view into SwiftUI.
struct MarkdownEditor: NSViewRepresentable {
    let document: DocumentModel
    let text: String
    let style: EditorStyle
    /// False while reading mode covers the editor; a hidden text view can't take keystrokes.
    let isActive: Bool
    /// Pages offered in the link picker after typing `[[`.
    let pages: () -> [PageRef]
    /// ⌘-click on a `[[page]]` link.
    let onOpenPage: (String) -> Void
    /// ⌘-click on a markdown link or URL.
    let onOpenLink: (String) -> Void
    /// ⌘-click on a `#tag`: searches for it.
    let onOpenTag: (String) -> Void
    /// Saves pasted or dropped images next to the page and returns the markdown to insert.
    let importImages: (ImageImporter.Source) -> [String]
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let textView = EditorTextView(styler: MarkdownStyler(style: style))
        textView.delegate = coordinator
        textView.textStorage?.delegate = coordinator
        textView.onEscape = { [weak coordinator] in coordinator?.parent.onEscape() }
        textView.onOpenPage = { [weak coordinator] in coordinator?.parent.onOpenPage($0) }
        textView.onOpenLink = { [weak coordinator] in coordinator?.parent.onOpenLink($0) }
        textView.onOpenTag = { [weak coordinator] in coordinator?.parent.onOpenTag($0) }
        textView.pages = { [weak coordinator] in coordinator?.parent.pages() ?? [] }
        textView.importImages = { [weak coordinator] in coordinator?.parent.importImages($0) ?? [] }
        textView.baseURL = document.url.deletingLastPathComponent()
        coordinator.textView = textView

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.documentView = textView
        scrollView.isHidden = !isActive
        // Start at a realistic width so the first layout isn't one character per line.
        textView.frame = NSRect(x: 0, y: 0, width: 900, height: 600)

        textView.string = text
        textView.applyStyle(style)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        DispatchQueue.main.async { [isActive] in
            if isActive { textView.window?.makeFirstResponder(textView) }
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }

        let baseURL = document.url.deletingLastPathComponent()
        if textView.baseURL != baseURL { textView.baseURL = baseURL }

        if scrollView.isHidden == isActive {
            scrollView.isHidden = !isActive
            if isActive {
                DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
            }
        }

        if textView.styler.style != style {
            textView.applyStyle(style)
        }

        if let jump = document.jump, coordinator.lastJump != jump.id {
            coordinator.lastJump = jump.id
            DispatchQueue.main.async { textView.jump(to: jump.offset) }
        }

        if textView.string != text {
            coordinator.isApplyingModelText = true
            let selection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            coordinator.isApplyingModelText = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: MarkdownEditor
        weak var textView: EditorTextView?
        var isApplyingModelText = false
        var lastJump: UUID?

        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingModelText, let textView else { return }
            parent.document.text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            textView?.selectionDidChange()
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters), let textView else { return }
            textView.styler.highlight(textStorage, editedRange: editedRange)
        }
    }
}

/// A plain-text NSTextView with a centred column, code panels, list continuation and focus mode.
final class EditorTextView: NSTextView {
    let styler: MarkdownStyler
    var onEscape: (() -> Void)?
    var onOpenPage: ((String) -> Void)?
    var onOpenLink: ((String) -> Void)?
    var onOpenTag: ((String) -> Void)?
    var pages: (() -> [PageRef])?
    var importImages: ((ImageImporter.Source) -> [String])?
    /// The page's folder, for resolving relative image paths.
    var baseURL: URL?
    private var imageCache: [URL: NSImage] = [:]
    private let ownedStorage: NSTextStorage

    init(styler: MarkdownStyler) {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        self.styler = styler
        ownedStorage = storage
        super.init(frame: .zero, textContainer: container)

        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        drawsBackground = false
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        styler.imageSize = { [weak self] in self?.previewSize(for: $0) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private var isTypewriterActive: Bool {
        styler.style.focusMode && styler.style.typewriterScrolling
    }

    func applyStyle(_ style: EditorStyle) {
        styler.update(style)
        isContinuousSpellCheckingEnabled = style.checksSpelling
        insertionPointColor = style.theme.accent
        selectedTextAttributes = [.backgroundColor: style.theme.selection]
        typingAttributes = styler.baseAttributes
        if let storage = textStorage {
            storage.beginEditing()
            styler.highlight(storage)
            storage.endEditing()
        }
        updateInsets()
        updateFocusDimming()
        needsDisplay = true
        if isTypewriterActive {
            DispatchQueue.main.async { [weak self] in self?.centerCaret(animated: false) }
        }
    }

    func selectionDidChange() {
        updateFocusDimming()
        if isTypewriterActive { centerCaret(animated: true) }
        closeLinkPickerIfEditingHere()
    }

    // MARK: Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    /// Centres the text column in the view; in typewriter mode adds half a screen above and below.
    private func updateInsets() {
        let column = styler.style.lineWidth + styler.gutter * 2
        let horizontal = max(4, ((bounds.width - column) / 2).rounded())
        let visibleHeight = enclosingScrollView?.contentView.bounds.height ?? 600
        let vertical = isTypewriterActive ? (visibleHeight / 2).rounded() : 36
        let inset = NSSize(width: horizontal, height: vertical)
        if textContainerInset != inset { textContainerInset = inset }
    }

    /// Puts the caret at a heading the outline picked and brings it near the top.
    func jump(to offset: Int) {
        let length = (string as NSString).length
        let location = min(max(0, offset), length)
        setSelectedRange(NSRange(location: location, length: 0))
        guard let layoutManager, let textContainer, let scrollView = enclosingScrollView else { return }
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: location, length: 0), actualCharacterRange: nil)
        let lineRect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        let clip = scrollView.contentView
        let top = max(-scrollView.contentInsets.top, lineRect.minY + textContainerOrigin.y - 24)
        let bottom = max(-scrollView.contentInsets.top, bounds.height - clip.bounds.height)
        clip.animator().setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: min(top, bottom)))
        scrollView.reflectScrolledClipView(clip)
        window?.makeFirstResponder(self)
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        // In typewriter mode the selection handler keeps the caret centred instead.
        guard !isTypewriterActive else { return }
        super.scrollRangeToVisible(range)
    }

    private func centerCaret(animated: Bool) {
        guard let layoutManager, let scrollView = enclosingScrollView else { return }
        let clip = scrollView.contentView
        let length = (string as NSString).length
        let location = selectedRange().location

        let lineRect: NSRect
        if length == 0 || (location >= length && layoutManager.extraLineFragmentTextContainer != nil) {
            lineRect = layoutManager.extraLineFragmentRect
        } else {
            let glyph = layoutManager.glyphIndexForCharacter(at: min(location, length - 1))
            lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        }

        let caretY = lineRect.midY + textContainerOrigin.y
        let topInset = scrollView.contentInsets.top
        let targetY = max(-topInset, caretY - (clip.bounds.height + topInset) / 2)
        guard abs(clip.bounds.origin.y - targetY) > 0.5 else { return }

        let target = NSPoint(x: clip.bounds.origin.x, y: targetY)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.allowsImplicitAnimation = true
                clip.animator().setBoundsOrigin(target)
            }
        } else {
            clip.setBoundsOrigin(target)
        }
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: Focus mode

    /// Fades every block except the one with the caret.
    private func updateFocusDimming() {
        guard let layoutManager else { return }
        let length = (string as NSString).length
        let full = NSRange(location: 0, length: length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        guard styler.style.focusMode, styler.style.dimsParagraphs, length > 0 else { return }

        let current = currentBlock()
        let dimmed = styler.style.theme.text.withAlphaComponent(styler.style.theme.isDark ? 0.24 : 0.2)
        if current.location > 0 {
            layoutManager.addTemporaryAttribute(.foregroundColor, value: dimmed, forCharacterRange: NSRange(location: 0, length: current.location))
        }
        if NSMaxRange(current) < length {
            layoutManager.addTemporaryAttribute(.foregroundColor, value: dimmed, forCharacterRange: NSRange(location: NSMaxRange(current), length: length - NSMaxRange(current)))
        }
    }

    /// The lines around the caret up to the nearest blank lines.
    private func currentBlock() -> NSRange {
        let text = string as NSString
        func isBlank(_ range: NSRange) -> Bool {
            text.substring(with: range).allSatisfy(\.isWhitespace)
        }
        var block = text.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        guard !isBlank(block) else { return block }
        while block.location > 0 {
            let previous = text.lineRange(for: NSRange(location: block.location - 1, length: 0))
            if isBlank(previous) { break }
            block = NSUnionRange(previous, block)
        }
        while NSMaxRange(block) < text.length {
            let next = text.lineRange(for: NSRange(location: NSMaxRange(block), length: 0))
            if isBlank(next) { break }
            block = NSUnionRange(block, next)
        }
        return block
    }

    override func cancelOperation(_ sender: Any?) {
        if styler.style.focusMode, let onEscape {
            onEscape()
        } else {
            super.cancelOperation(sender)
        }
    }

    // MARK: Lists

    /// Return continues a list, quote or task list; on an empty item it ends the list.
    override func insertNewline(_ sender: Any?) {
        let text = string as NSString
        let selection = selectedRange()
        guard selection.length == 0 else { return super.insertNewline(sender) }

        let line = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let beforeCaret = text.substring(with: NSRange(location: line.location, length: selection.location - line.location))
        let afterCaret = text.substring(with: NSRange(location: selection.location, length: NSMaxRange(line) - selection.location))
        let before = beforeCaret as NSString
        let local = NSRange(location: 0, length: before.length)

        let continuation: String
        let prefixLength: Int
        if let match = MarkdownStyler.listItem.firstMatch(in: beforeCaret, range: local) {
            var marker = before.substring(with: match.range(at: 2))
            if let number = Int(marker.dropLast()), let punctuation = marker.last {
                marker = "\(number + 1)\(punctuation)"
            }
            let task = match.range(at: 4).location == NSNotFound ? "" : "[ ] "
            continuation = before.substring(with: match.range(at: 1)) + marker + before.substring(with: match.range(at: 3)) + task
            prefixLength = match.range.length
        } else if let quote = beforeCaret.range(of: #"^[ \t]*>[ \t]?"#, options: .regularExpression) {
            continuation = String(beforeCaret[quote])
            prefixLength = (continuation as NSString).length
        } else {
            return super.insertNewline(sender)
        }

        if prefixLength == before.length, afterCaret.allSatisfy(\.isWhitespace) {
            // Empty item: remove the marker and leave the list.
            insertText("", replacementRange: NSRange(location: line.location, length: prefixLength))
        } else {
            insertText("\n" + continuation, replacementRange: selection)
        }
    }

    // MARK: Drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return }

        let origin = textContainerOrigin
        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y), in: textContainer)
        let visible = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        let full = NSRange(location: 0, length: storage.length)
        styler.style.theme.codeBackground.setFill()

        // Code blocks: one rounded panel per block, spanning the text column.
        var drawnBlockEnd = -1
        storage.enumerateAttribute(.codeBlock, in: visible) { value, range, _ in
            guard value != nil, range.location >= drawnBlockEnd else { return }
            var block = NSRange()
            _ = storage.attribute(.codeBlock, at: range.location, longestEffectiveRange: &block, in: full)
            drawnBlockEnd = NSMaxRange(block)
            let glyphs = layoutManager.glyphRange(forCharacterRange: block, actualCharacterRange: nil)
            let bounds = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            let panel = NSRect(
                x: origin.x + styler.gutter,
                y: origin.y + bounds.minY - 4,
                width: textContainer.size.width - styler.gutter * 2,
                height: bounds.height + 8
            )
            NSBezierPath(roundedRect: panel, xRadius: 10, yRadius: 10).fill()
        }

        // Inline code: a small pill that hugs the glyphs rather than the tall line.
        let codeFont = styler.codeFont
        storage.enumerateAttribute(.inlineCode, in: visible) { value, range, _ in
            guard value != nil else { return }
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, lineGlyphs, _ in
                let part = NSIntersectionRange(lineGlyphs, glyphs)
                guard part.length > 0 else { return }
                let partRect = layoutManager.boundingRect(forGlyphRange: part, in: textContainer)
                let baseline = lineRect.minY + layoutManager.location(forGlyphAt: part.location).y
                let top = baseline - codeFont.ascender - 2
                let bottom = baseline - codeFont.descender + 2
                let pill = NSRect(x: origin.x + partRect.minX - 3, y: origin.y + top, width: partRect.width + 6, height: bottom - top)
                NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4).fill()
            }
        }

        // Image previews, in the space the styler left under each image line.
        storage.enumerateAttribute(.imagePreview, in: visible) { value, range, _ in
            guard let source = value as? String, let image = previewImage(for: source), let size = previewSize(for: source) else { return }
            let lastGlyph = layoutManager.glyphIndexForCharacter(at: max(range.location, NSMaxRange(range) - 1))
            let line = layoutManager.lineFragmentUsedRect(forGlyphAt: lastGlyph, effectiveRange: nil)
            let frame = NSRect(x: origin.x + styler.gutter, y: origin.y + line.maxY + 8, width: size.width, height: size.height)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).addClip()
            image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
            NSGraphicsContext.restoreGraphicsState()
            // A hairline edge, so screenshots with a white background don't melt into the page.
            styler.style.theme.secondary.withAlphaComponent(0.3).setStroke()
            let edge = NSBezierPath(roundedRect: frame.insetBy(dx: 0.25, dy: 0.25), xRadius: 8, yRadius: 8)
            edge.lineWidth = 0.5
            edge.stroke()
        }
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        typedOpeningBracket = replacementString?.hasSuffix("[") == true
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    override func didChangeText() {
        super.didChangeText()
        // Code panels span several lines; redraw them whole so corners stay intact.
        setNeedsDisplay(visibleRect)
        closeLinkPickerIfEditingHere()
        // Typing the second `[` opens the link picker; deleting back to an existing `[[` doesn't.
        let caret = selectedRange()
        if typedOpeningBracket, caret.length == 0, caret.location >= 2,
           undoManager?.isUndoing != true, undoManager?.isRedoing != true,
           (string as NSString).substring(with: NSRange(location: caret.location - 2, length: 2)) == "[[" {
            DispatchQueue.main.async { [weak self] in self?.showLinkPicker() }
        }
        typedOpeningBracket = false
    }

    // MARK: Links

    /// ⌘-click follows `[[page]]` links and URLs; a plain click just places the caret.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let storage = textStorage, storage.length > 0 {
            let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
            for candidate in [index, index - 1] where candidate >= 0 && candidate < storage.length {
                if let page = storage.attribute(.wikiLink, at: candidate, effectiveRange: nil) as? String {
                    onOpenPage?(page)
                    return
                }
                if let target = storage.attribute(.linkTarget, at: candidate, effectiveRange: nil) as? String {
                    onOpenLink?(target)
                    return
                }
                if let tag = storage.attribute(.tagName, at: candidate, effectiveRange: nil) as? String {
                    onOpenTag?(tag)
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: Images

    /// ⌘V with a screenshot, a copied picture or copied image files saves them next to the page.
    override func paste(_ sender: Any?) {
        if let source = ImageImporter.source(from: .general, allowsText: false), insertImages(source) { return }
        super.paste(sender)
    }

    /// Lets Paste stay enabled when the clipboard only holds an image.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + [.png, .tiff]
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + [.png, .tiff]
    }

    override func dragOperation(for dragInfo: any NSDraggingInfo, type: NSPasteboard.PasteboardType) -> NSDragOperation {
        ImageImporter.hasImages(on: dragInfo.draggingPasteboard, allowsText: true) ? .copy : super.dragOperation(for: dragInfo, type: type)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if let source = ImageImporter.source(from: sender.draggingPasteboard, allowsText: true) {
            let point = convert(sender.draggingLocation, from: nil)
            setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
            if insertImages(source) { return true }
        }
        return super.performDragOperation(sender)
    }

    /// Wijzig ▸ Voeg afbeelding in…
    @objc func insertImageFromFile(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.title = "Voeg afbeelding in"
        panel.prompt = "Voeg in"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.insertImages(.files(panel.urls))
        }
    }

    /// Inserts the images' markdown at the caret, each on its own line so it gets a preview.
    @discardableResult
    private func insertImages(_ source: ImageImporter.Source) -> Bool {
        guard let snippets = importImages?(source), !snippets.isEmpty else { return false }
        let text = string as NSString
        let selection = selectedRange()
        let startsLine = selection.location == 0 || text.character(at: selection.location - 1) == 10
        let end = NSMaxRange(selection)
        let endsLine = end >= text.length || text.character(at: end) == 10
        let markdown = (startsLine ? "" : "\n") + snippets.joined(separator: "\n") + (endsLine ? "" : "\n")
        insertText(markdown, replacementRange: selection)
        return true
    }

    /// Local images only; the editor never waits on the network.
    private func previewImage(for source: String) -> NSImage? {
        guard let baseURL else { return nil }
        // Resolve against the folder itself; without a trailing slash, "assets/x.png" would land one folder up.
        let folder = URL(fileURLWithPath: baseURL.path, isDirectory: true)
        let encoded = source.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? source
        guard let url = (URL(string: source, relativeTo: folder) ?? URL(string: encoded, relativeTo: folder))?.absoluteURL,
              url.isFileURL else { return nil }
        if let cached = imageCache[url] { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache[url] = image
        return image
    }

    /// Never wider than the text column, never taller than 360 pt, and never scaled up.
    private func previewSize(for source: String) -> CGSize? {
        guard let image = previewImage(for: source), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, styler.style.lineWidth / image.size.width, 360 / image.size.height)
        return CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
    }

    // MARK: Link picker

    private var linkPicker: NSHostingView<LinkPicker>?
    /// Set while an edit that ends in `[` is being applied.
    private var typedOpeningBracket = false
    /// Where the page name goes: right after the `[[` that opened the picker.
    private var linkPickerLocation = 0
    /// The line with that `[[`, in view coordinates, to place the picker under.
    private var linkPickerAnchor = NSRect.zero

    private func showLinkPicker() {
        guard linkPicker == nil, let layoutManager, let textContainer else { return }
        let location = selectedRange().location
        guard location >= 2 else { return }

        let brackets = layoutManager.glyphRange(forCharacterRange: NSRange(location: location - 2, length: 2), actualCharacterRange: nil)
        let glyphs = layoutManager.boundingRect(forGlyphRange: brackets, in: textContainer)
        let line = layoutManager.lineFragmentRect(forGlyphAt: brackets.location, effectiveRange: nil)
        linkPickerAnchor = NSRect(x: glyphs.minX, y: line.minY, width: glyphs.width, height: line.height)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        linkPickerLocation = location

        let picker = LinkPicker(
            pages: pages?() ?? [],
            theme: styler.style.theme,
            onPick: { [weak self] in self?.insertLink($0) },
            onCancel: { [weak self] in self?.closeLinkPicker(restoreFocus: true, removeBracket: $0) },
            onFocusLost: { [weak self] in self?.closeLinkPicker(restoreFocus: false, removeBracket: false) },
            onSizeChange: { [weak self] size in
                DispatchQueue.main.async { self?.positionLinkPicker(size: size) }
            }
        )
        let host = NSHostingView(rootView: picker)
        addSubview(host)
        linkPicker = host
        positionLinkPicker(size: host.fittingSize)
    }

    /// Under the `[[`, or above it when there's no room below.
    private func positionLinkPicker(size: CGSize) {
        guard let linkPicker else { return }
        let room = LinkPicker.shadowRoom
        var frame = NSRect(
            x: linkPickerAnchor.minX - room - 12,
            y: linkPickerAnchor.maxY + 4 - room,
            width: size.width,
            height: size.height
        )
        if frame.maxY - room > visibleRect.maxY {
            frame.origin.y = linkPickerAnchor.minY - 4 - size.height + room
        }
        frame.origin.x = max(visibleRect.minX, min(frame.origin.x, visibleRect.maxX - size.width))
        linkPicker.frame = frame
    }

    private func insertLink(_ title: String) {
        let location = linkPickerLocation
        closeLinkPicker(restoreFocus: true, removeBracket: false)
        let text = string as NSString
        guard location <= text.length else { return }
        let isClosed = location + 2 <= text.length && text.substring(with: NSRange(location: location, length: 2)) == "]]"
        insertText(isClosed ? title : title + "]]", replacementRange: NSRange(location: location, length: 0))
        if isClosed {
            setSelectedRange(NSRange(location: location + (title as NSString).length + 2, length: 0))
        }
    }

    /// The picker holds keyboard focus while it works. If typing or clicking lands in the text instead,
    /// it didn't get focus or lost it, so it shouldn't stay on screen.
    private func closeLinkPickerIfEditingHere() {
        guard linkPicker != nil, window?.firstResponder === self else { return }
        closeLinkPicker(restoreFocus: false, removeBracket: false)
    }

    private func closeLinkPicker(restoreFocus: Bool, removeBracket: Bool) {
        guard let picker = linkPicker else { return }
        linkPicker = nil
        picker.isHidden = true
        // Removed on the next turn of the run loop: this is often called from inside the picker's own key handling.
        DispatchQueue.main.async { picker.removeFromSuperview() }

        let length = (string as NSString).length
        if restoreFocus {
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location: min(linkPickerLocation, length), length: 0))
        }
        if removeBracket, linkPickerLocation >= 1, linkPickerLocation <= length,
           (string as NSString).substring(with: NSRange(location: linkPickerLocation - 1, length: 1)) == "[" {
            insertText("", replacementRange: NSRange(location: linkPickerLocation - 1, length: 1))
        }
    }
}
