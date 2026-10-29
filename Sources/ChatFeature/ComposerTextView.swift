import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The pictures a paste carries: one per item, its raw bytes (a screenshot copied on the Mac arrives as PNG), or a
/// `UIImage` re-encoded as PNG when the item only has that. An item without a picture is left out.
///
/// A file copied in the Finder comes with its icon — `com.apple.icns`, an image type too — so the file itself wins: the
/// contents behind its file URL when that is a picture, else its richest image type; an icon is never a picture.
enum ComposerPaste {
    static func imageData(from items: [[String: Any]]) -> [Data] {
        items.compactMap { item in
            if let data = fileContents(item[UTType.fileURL.identifier]) { return data }
            let candidates = item.compactMap { type, value -> (rank: Int, type: String, value: Any)? in
                guard let utType = UTType(type), utType.conforms(to: .image), !isIcon(utType) else { return nil }
                return (rank(utType), type, value)
            }
            for candidate in candidates.sorted(by: { ($0.rank, $0.type) < ($1.rank, $1.type) }) {
                if let data = candidate.value as? Data { return data }
                if let image = candidate.value as? UIImage, let data = image.pngData() { return data }
            }
            return nil
        }
    }

    /// The picture a file URL points at, read whole; nil for anything that is not a picture file.
    private static func fileContents(_ value: Any?) -> Data? {
        let url: URL? =
            switch value {
            case let url as URL: url
            case let string as String: URL(string: string)
            case let data as Data: String(data: data, encoding: .utf8).flatMap { URL(string: $0) }
            default: nil
            }
        guard let url, url.isFileURL,
            let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image), !isIcon(type)
        else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func isIcon(_ type: UTType) -> Bool {
        type.conforms(to: .icns) || type.identifier == "com.apple.icns"
    }

    /// The formats a picture is saved in first; TIFF, the pasteboard's lossless stand-in, and anything else after.
    private static func rank(_ type: UTType) -> Int {
        for (i, preferred) in [UTType.png, .jpeg, .heic, .heif, .webP, .gif].enumerated() where type.conforms(to: preferred) {
            return i
        }
        return type.conforms(to: .tiff) ? 8 : 7
    }
}

/// The composer's field: a `UITextView`, because a SwiftUI `TextField` takes only the text of a paste — a picture
/// copied on the Mac came through as its file name (ISSUE-299). A paste that carries pictures adds them to the
/// message, as the photo picker does, and inserts nothing; a paste of text is the text view's own.
///
/// It grows a line at a time up to `maxLines`, then scrolls, and reports its height for a proposed width, which is
/// what `ComposerRowLayout` measures.
public struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String
    /// The caret's colour (the chat's tone): a UIKit view does not read SwiftUI's `.tint`.
    var tint: Color
    var maxLines = 5
    var accessibilityIdentifier: String
    var onPasteImages: ([Data]) -> Void

    public init(
        text: Binding<String>, isFocused: Binding<Bool>, placeholder: String, tint: Color, maxLines: Int = 5,
        accessibilityIdentifier: String, onPasteImages: @escaping ([Data]) -> Void
    ) {
        _text = text
        _isFocused = isFocused
        self.placeholder = placeholder
        self.tint = tint
        self.maxLines = maxLines
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onPasteImages = onPasteImages
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeUIView(context: Context) -> PastingTextView {
        let view = PastingTextView.composerField()
        view.delegate = context.coordinator
        view.accessibilityIdentifier = accessibilityIdentifier
        view.text = text
        view.placeholderLabel.text = placeholder
        view.onPasteImages = onPasteImages
        return view
    }

    public func updateUIView(_ view: PastingTextView, context: Context) {
        context.coordinator.parent = self
        // Never while a composition is under way: setting the text would cancel the IME's marked text.
        if view.text != text, view.markedTextRange == nil {
            view.text = text
            view.updatePlaceholder()
        }
        view.placeholderLabel.text = placeholder
        view.onPasteImages = onPasteImages
        view.tintColor = UIColor(tint)
        let enabled = context.environment.isEnabled
        view.isEditable = enabled
        view.isSelectable = enabled
        if isFocused, enabled, !view.isFirstResponder, view.window != nil {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        } else if !isFocused, view.isFirstResponder {
            DispatchQueue.main.async { view.resignFirstResponder() }
        }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView view: PastingTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? view.bounds.width
        guard width > 0, width.isFinite else { return nil }
        let (height, scrolls) = Self.height(of: view, width: width, maxLines: maxLines)
        if view.isScrollEnabled != scrolls {
            DispatchQueue.main.async { view.isScrollEnabled = scrolls }
        }
        return CGSize(width: width, height: height)
    }

    /// One line at least (the placeholder's), `maxLines` at most; past that the text scrolls.
    static func height(of view: UITextView, width: CGFloat, maxLines: Int) -> (height: CGFloat, scrolls: Bool) {
        let lineHeight = view.font?.lineHeight ?? 22
        let fitting = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let cap = ceil(lineHeight * CGFloat(maxLines))
        return (min(max(fitting, ceil(lineHeight)), cap), fitting > cap)
    }

    public final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerTextView

        init(_ parent: ComposerTextView) { self.parent = parent }

        public func textViewDidChange(_ textView: UITextView) {
            (textView as? PastingTextView)?.updatePlaceholder()
            if parent.text != textView.text { parent.text = textView.text }
        }

        public func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }

        public func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }
    }
}

public final class PastingTextView: UITextView {
    var onPasteImages: (([Data]) -> Void)?
    /// The general pasteboard; a test hands in a private one (reading the general one outside a person's paste asks
    /// them first).
    var pasteboard: UIPasteboard = .general

    let placeholderLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .placeholderText
        label.numberOfLines = 1
        label.isAccessibilityElement = false
        return label
    }()

    /// The field as the composer draws it: body text, no insets of its own (the composer row pads it), not scrolling
    /// until it outgrows its lines.
    static func composerField() -> PastingTextView {
        let view = PastingTextView()
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .label
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        addSubview(placeholderLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override public var text: String! {
        didSet { updatePlaceholder() }
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        placeholderLabel.frame = CGRect(
            x: textContainerInset.left + textContainer.lineFragmentPadding, y: textContainerInset.top,
            width: max(0, bounds.width - textContainerInset.left - textContainerInset.right),
            height: placeholderLabel.font.lineHeight)
    }

    func updatePlaceholder() {
        placeholderLabel.isHidden = !text.isEmpty
        accessibilityLabel = text.isEmpty ? placeholderLabel.text : nil
    }

    override public func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), pasteboard.hasImages { return isEditable }
        return super.canPerformAction(action, withSender: sender)
    }

    override public func paste(_ sender: Any?) {
        // Read inside the paste the person asked for, so iOS does not ask again whether to allow it.
        let board = pasteboard
        if board.hasImages {
            let pictures = ComposerPaste.imageData(from: board.items)
            if !pictures.isEmpty {
                onPasteImages?(pictures)
                return
            }
        }
        super.paste(sender)
    }
}
