import SwiftUI
import UIKit

/// Lets SwiftUI (the keyboard bar, the link sheet, the photo picker) act on the text view.
@Observable
final class EditorController {
    @ObservationIgnored weak var textView: BladTextView?
    /// True while the keyboard is up; the word count steps aside then.
    var isEditing = false

    func insertLink(_ title: String) { textView?.completeLink(title) }
    func insertImages(_ markdown: [String]) { textView?.insertImageMarkdown(markdown) }
    func toggleHeading() { textView?.toggleLinePrefix("# ") }
    func toggleTask() { textView?.toggleLinePrefix("- [ ] ") }
    func toggleBold() { textView?.wrapSelection(with: "**") }
    func toggleItalic() { textView?.wrapSelection(with: "*") }
    func startLink() { textView?.startLink() }
    func dismissKeyboard() { textView?.resignFirstResponder() }

    /// Opens iOS' own find panel over the page, with the replace field open.
    func find() {
        guard let textView else { return }
        textView.becomeFirstResponder()
        textView.findInteraction?.presentFindNavigator(showingReplace: true)
    }
}

/// Bridges the UIKit text view into SwiftUI, like MarkdownEditor does on the Mac.
struct MarkdownTextView: UIViewRepresentable {
    let text: String
    let style: EditorStyle
    let baseURL: URL
    let controller: EditorController
    let onChange: (String) -> Void
    /// Typing `[[` asks for a page to link to.
    let onLinkTrigger: () -> Void
    let onPhoto: () -> Void
    /// Set by the outline; moves the editor to that heading.
    var jump: Jump?
    let importImages: (ImageImporter.Source) -> [String]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> BladTextView {
        let coordinator = context.coordinator
        let textView = BladTextView(styler: MarkdownStyler(style: style))
        coordinator.textView = textView
        textView.delegate = coordinator
        textView.textStorage.delegate = coordinator
        textView.baseURL = baseURL
        textView.importImages = { [weak coordinator] in coordinator?.parent.importImages($0) ?? [] }
        textView.onLinkTrigger = { [weak coordinator] in coordinator?.parent.onLinkTrigger() }
        textView.inputAccessoryView = coordinator.makeKeyboardBar()
        textView.text = text
        textView.applyStyle(style)
        controller.textView = textView
        return textView
    }

    func updateUIView(_ textView: BladTextView, context: Context) {
        context.coordinator.parent = self
        if let jump, context.coordinator.lastJump != jump.id {
            context.coordinator.lastJump = jump.id
            DispatchQueue.main.async { textView.jump(to: jump.offset) }
        }
        controller.textView = textView
        if textView.baseURL != baseURL { textView.baseURL = baseURL }
        if textView.styler.style != style { textView.applyStyle(style) }
        if textView.text != text {
            let selection = textView.selectedRange
            textView.text = text
            textView.selectedRange = NSRange(location: min(selection.location, (text as NSString).length), length: 0)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, NSTextStorageDelegate {
        var lastJump: UUID?
        var parent: MarkdownTextView
        weak var textView: BladTextView?
        private var typedOpeningBracket = false
        private var keyboardBar: UIHostingController<KeyboardBar>?

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        func makeKeyboardBar() -> UIView {
            let bar = KeyboardBar(controller: parent.controller) { [weak self] in self?.parent.onPhoto() }
            let host = UIHostingController(rootView: bar)
            host.view.backgroundColor = .clear
            host.view.frame = CGRect(x: 0, y: 0, width: 0, height: KeyboardBar.height)
            host.view.autoresizingMask = [.flexibleWidth]
            keyboardBar = host
            return host.view
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            typedOpeningBracket = text.hasSuffix("[")
            if text == "\n", let textView = textView as? BladTextView, textView.continueList(at: range) {
                return false
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.onChange(textView.text)
            (textView as? BladTextView)?.redrawVisibleDecorations()

            // Typing the second `[` opens the link picker; deleting back to an existing `[[` doesn't.
            let caret = textView.selectedRange
            if typedOpeningBracket, caret.length == 0, caret.location >= 2,
               (textView.text as NSString).substring(with: NSRange(location: caret.location - 2, length: 2)) == "[[" {
                DispatchQueue.main.async { self.parent.onLinkTrigger() }
            }
            typedOpeningBracket = false
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.controller.isEditing = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.controller.isEditing = false
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorage.EditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters), let textView else { return }
            textView.styler.highlight(textStorage, editedRange: editedRange)
        }
    }
}

/// A UITextView on TextKit 1 with the Mac editor's styling: a centred column, code panels,
/// image previews and list continuation.
final class BladTextView: UITextView {
    let styler: MarkdownStyler
    var baseURL: URL?
    var importImages: ((ImageImporter.Source) -> [String])?
    var onLinkTrigger: (() -> Void)?

    private let ownedStorage: NSTextStorage
    private let decorations: DecoratingLayoutManager
    private var imageCache: [URL: UIImage] = [:]
    private var styledContainerWidth: CGFloat = 0

    init(styler: MarkdownStyler) {
        let storage = NSTextStorage()
        let layoutManager = DecoratingLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        self.styler = styler
        ownedStorage = storage
        decorations = layoutManager
        super.init(frame: .zero, textContainer: container)
        layoutManager.textView = self

        backgroundColor = .clear
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        isFindInteractionEnabled = true
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        styler.imageSize = { [weak self] in self?.previewSize(for: $0) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Puts the caret at a heading the outline picked and brings it near the top.
    func jump(to offset: Int) {
        let length = (text as NSString).length
        let location = min(max(0, offset), length)
        selectedRange = NSRange(location: location, length: 0)
        let caret = layoutManager.boundingRect(
            forGlyphRange: layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil),
            in: textContainer
        )
        let top = min(max(0, caret.minY + textContainerInset.top - 16), max(0, contentSize.height - bounds.height))
        setContentOffset(CGPoint(x: 0, y: top - adjustedContentInset.top), animated: true)
    }

    func applyStyle(_ style: EditorStyle) {
        styler.update(style)
        tintColor = style.theme.accent
        let spelling: UITextSpellCheckingType = style.checksSpelling ? .yes : .no
        if spellCheckingType != spelling {
            spellCheckingType = spelling
            if isFirstResponder { reloadInputViews() }
        }
        restyle()
        updateInsets()
    }

    private func restyle() {
        textStorage.beginEditing()
        styler.highlight(textStorage)
        textStorage.endEditing()
        typingAttributes = styler.baseAttributes
        styledContainerWidth = textContainer.size.width
        redrawVisibleDecorations()
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        updateInsets()
        // Image previews are sized to the column; restyle once the real width is known.
        if abs(textContainer.size.width - styledContainerWidth) > 1, text.contains("![") {
            restyle()
        }
    }

    /// Centres the text column; on a phone the column is simply the screen.
    private func updateInsets() {
        let column = styler.style.lineWidth + styler.gutter * 2
        let horizontal = max(12, ((bounds.width - column) / 2).rounded())
        let insets = UIEdgeInsets(top: 20, left: horizontal, bottom: 140, right: horizontal)
        if textContainerInset != insets { textContainerInset = insets }
    }

    /// Code panels and image previews span several lines; redraw what's on screen after an edit.
    func redrawVisibleDecorations() {
        let visible = CGRect(origin: contentOffset, size: bounds.size)
            .offsetBy(dx: -textContainerInset.left, dy: -textContainerInset.top)
        layoutManager.invalidateDisplay(forGlyphRange: layoutManager.glyphRange(forBoundingRect: visible, in: textContainer))
    }

    // MARK: Editing

    /// Return in a list or quote continues it; on an empty item it ends the list.
    /// Returns false when Return should just type a new line.
    func continueList(at range: NSRange) -> Bool {
        guard range.length == 0 else { return false }
        let text = self.text as NSString
        let line = text.lineRange(for: NSRange(location: range.location, length: 0))
        let before = text.substring(with: NSRange(location: line.location, length: range.location - line.location))
        let after = text.substring(with: NSRange(location: range.location, length: NSMaxRange(line) - range.location))
        let beforeText = before as NSString
        let local = NSRange(location: 0, length: beforeText.length)

        let continuation: String
        let prefixLength: Int
        if let match = MarkdownStyler.listItem.firstMatch(in: before, range: local) {
            var marker = beforeText.substring(with: match.range(at: 2))
            if let number = Int(marker.dropLast()), let punctuation = marker.last {
                marker = "\(number + 1)\(punctuation)"
            }
            let task = match.range(at: 4).location == NSNotFound ? "" : "[ ] "
            continuation = beforeText.substring(with: match.range(at: 1)) + marker + beforeText.substring(with: match.range(at: 3)) + task
            prefixLength = match.range.length
        } else if let quote = before.range(of: #"^[ \t]*>[ \t]?"#, options: .regularExpression) {
            continuation = String(before[quote])
            prefixLength = (continuation as NSString).length
        } else {
            return false
        }

        if prefixLength == beforeText.length, after.allSatisfy(\.isWhitespace) {
            // Empty item: remove the marker and leave the list.
            replace(NSRange(location: line.location, length: prefixLength), with: "")
        } else {
            replace(range, with: "\n" + continuation)
        }
        notifyChange()
        return true
    }

    /// The keyboard bar's link key: types `[[` and asks for a page.
    func startLink() {
        replace(selectedRange, with: "[[")
        notifyChange()
        onLinkTrigger?()
    }

    /// Finishes a link after `[[`: the page name, then `]]` unless it's already there.
    func completeLink(_ title: String) {
        becomeFirstResponder()
        let text = self.text as NSString
        let caret = selectedRange.location
        let hasOpening = caret >= 2 && text.substring(with: NSRange(location: caret - 2, length: 2)) == "[["
        let isClosed = caret + 2 <= text.length && text.substring(with: NSRange(location: caret, length: 2)) == "]]"
        let insertion = (hasOpening ? "" : "[[") + title + (isClosed ? "" : "]]")
        replace(NSRange(location: caret, length: 0), with: insertion)
        if isClosed {
            selectedRange = NSRange(location: caret + (insertion as NSString).length + 2, length: 0)
        }
        notifyChange()
    }

    func wrapSelection(with marker: String) {
        let range = selectedRange
        let selected = (text as NSString).substring(with: range)
        replace(range, with: marker + selected + marker)
        selectedRange = NSRange(location: range.location + (marker as NSString).length, length: range.length)
        notifyChange()
    }

    func toggleLinePrefix(_ prefix: String) {
        let text = self.text as NSString
        let caret = selectedRange.location
        let line = text.lineRange(for: NSRange(location: caret, length: 0))
        let prefixLength = (prefix as NSString).length
        if text.substring(with: line).hasPrefix(prefix) {
            replace(NSRange(location: line.location, length: prefixLength), with: "")
            selectedRange = NSRange(location: max(line.location, caret - prefixLength), length: 0)
        } else {
            replace(NSRange(location: line.location, length: 0), with: prefix)
            selectedRange = NSRange(location: caret + prefixLength, length: 0)
        }
        notifyChange()
    }

    /// Each image on its own line, so it gets a preview.
    func insertImageMarkdown(_ snippets: [String]) {
        guard !snippets.isEmpty else { return }
        let text = self.text as NSString
        let selection = selectedRange
        let startsLine = selection.location == 0 || text.character(at: selection.location - 1) == 10
        let end = NSMaxRange(selection)
        let endsLine = end >= text.length || text.character(at: end) == 10
        replace(selection, with: (startsLine ? "" : "\n") + snippets.joined(separator: "\n") + (endsLine ? "" : "\n"))
        notifyChange()
    }

    private func replace(_ range: NSRange, with string: String) {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length),
              let textRange = textRange(from: start, to: end) else { return }
        replace(textRange, withText: string)
    }

    /// Edits made in code don't always reach the delegate; tell it, so the page is saved.
    private func notifyChange() {
        delegate?.textViewDidChange?(self)
    }

    // MARK: Images

    /// Pasting a screenshot or copied picture saves it next to the page.
    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general
        if pasteboard.hasImages, !pasteboard.hasStrings,
           let png = pasteboard.image?.pngData(),
           let markdown = importImages?(.data(png)), !markdown.isEmpty {
            insertImageMarkdown(markdown)
            return
        }
        super.paste(sender)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), UIPasteboard.general.hasImages { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    func previewImage(for source: String) -> UIImage? {
        guard let baseURL else { return nil }
        let folder = URL(fileURLWithPath: baseURL.path, isDirectory: true)
        let encoded = source.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? source
        guard let url = (URL(string: source, relativeTo: folder) ?? URL(string: encoded, relativeTo: folder))?.absoluteURL,
              url.isFileURL else { return nil }
        if let cached = imageCache[url] { return cached }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        imageCache[url] = image
        return image
    }

    /// Never wider than the column, never taller than 360 pt, and never scaled up.
    func previewSize(for source: String) -> CGSize? {
        guard let image = previewImage(for: source), image.size.width > 0, image.size.height > 0 else { return nil }
        let column = max(80, min(styler.style.lineWidth, textContainer.size.width - styler.gutter * 2))
        let scale = min(1, column / image.size.width, 360 / image.size.height)
        return CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
    }
}

/// Draws code panels, inline code pills and image previews behind the text, as the Mac editor does.
final class DecoratingLayoutManager: NSLayoutManager {
    weak var textView: BladTextView?

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let textView, let storage = textStorage, storage.length > 0,
              let container = textContainers.first, let context = UIGraphicsGetCurrentContext() else { return }

        let styler = textView.styler
        let visible = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let full = NSRange(location: 0, length: storage.length)
        styler.style.theme.codeBackground.setFill()

        // Code blocks: one rounded panel per block, spanning the text column.
        var drawnBlockEnd = -1
        storage.enumerateAttribute(.codeBlock, in: visible) { value, range, _ in
            guard value != nil, range.location >= drawnBlockEnd else { return }
            var block = NSRange()
            _ = storage.attribute(.codeBlock, at: range.location, longestEffectiveRange: &block, in: full)
            drawnBlockEnd = NSMaxRange(block)
            let bounds = boundingRect(forGlyphRange: glyphRange(forCharacterRange: block, actualCharacterRange: nil), in: container)
            let panel = CGRect(
                x: origin.x + styler.gutter,
                y: origin.y + bounds.minY - 4,
                width: container.size.width - styler.gutter * 2,
                height: bounds.height + 8
            )
            UIBezierPath(roundedRect: panel, cornerRadius: 10).fill()
        }

        // Inline code: a small pill that hugs the glyphs rather than the tall line.
        let codeFont = styler.codeFont
        storage.enumerateAttribute(.inlineCode, in: visible) { value, range, _ in
            guard value != nil else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, lineGlyphs, _ in
                let part = NSIntersectionRange(lineGlyphs, glyphs)
                guard part.length > 0 else { return }
                let partRect = self.boundingRect(forGlyphRange: part, in: container)
                let baseline = lineRect.minY + self.location(forGlyphAt: part.location).y
                let top = baseline - codeFont.ascender - 2
                let bottom = baseline - codeFont.descender + 2
                let pill = CGRect(x: origin.x + partRect.minX - 3, y: origin.y + top, width: partRect.width + 6, height: bottom - top)
                UIBezierPath(roundedRect: pill, cornerRadius: 4).fill()
            }
        }

        // Image previews, in the space the styler left under each image line.
        storage.enumerateAttribute(.imagePreview, in: visible) { value, range, _ in
            guard let source = value as? String,
                  let image = textView.previewImage(for: source),
                  let size = textView.previewSize(for: source) else { return }
            let lastGlyph = glyphIndexForCharacter(at: max(range.location, NSMaxRange(range) - 1))
            let line = lineFragmentUsedRect(forGlyphAt: lastGlyph, effectiveRange: nil)
            let frame = CGRect(x: origin.x + styler.gutter, y: origin.y + line.maxY + 8, width: size.width, height: size.height)
            context.saveGState()
            UIBezierPath(roundedRect: frame, cornerRadius: 8).addClip()
            image.draw(in: frame)
            context.restoreGState()
            // A hairline edge, so screenshots with a white background don't melt into the page.
            styler.style.theme.secondary.withAlphaComponent(0.3).setStroke()
            let edge = UIBezierPath(roundedRect: frame.insetBy(dx: 0.25, dy: 0.25), cornerRadius: 8)
            edge.lineWidth = 0.5
            edge.stroke()
        }
    }
}
