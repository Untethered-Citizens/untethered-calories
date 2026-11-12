import SwiftUI
import UIKit

/// The Log tab's text box. It's a UIKit text view because SwiftUI's `TextField` only takes
/// pasted text: here a long-press → Paste (or ⌘V) with a photo on the clipboard attaches the
/// photo instead (issue #66). It grows with its text up to `maxLines`, then scrolls.
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String
    var maxLines = 5
    /// Called with the photos from a Paste; the text is left as it was. Nil when no more
    /// photos can be added, so Paste behaves as usual.
    var onPasteImages: (([UIImage]) -> Void)?

    func makeUIView(context: Context) -> PastingTextView {
        let view = PastingTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = Self.font
        view.adjustsFontForContentSizeCategory = true
        view.textColor = UIColor(Palette.ink)
        view.tintColor = UIColor(Palette.green)
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.accessibilityLabel = placeholder
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.onPasteImages = onPasteImages
        context.coordinator.placeholder.text = placeholder
        context.coordinator.placeholder.font = Self.font
        context.coordinator.placeholder.adjustsFontForContentSizeCategory = true
        context.coordinator.placeholder.textColor = UIColor(Palette.muted)
        context.coordinator.placeholder.isAccessibilityElement = false
        context.coordinator.placeholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(context.coordinator.placeholder)
        NSLayoutConstraint.activate([
            context.coordinator.placeholder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            context.coordinator.placeholder.topAnchor.constraint(equalTo: view.topAnchor),
        ])
        return view
    }

    func updateUIView(_ view: PastingTextView, context: Context) {
        context.coordinator.parent = self
        view.onPasteImages = onPasteImages
        if view.text != text {
            view.text = text
            context.coordinator.textChanged(view)
        }
        context.coordinator.placeholder.isHidden = !text.isEmpty
        // Focus changes go through the main queue: UIKit refuses them mid-update.
        if isFocused != view.isFirstResponder {
            let focus = isFocused
            DispatchQueue.main.async {
                if focus { view.becomeFirstResponder() } else { view.resignFirstResponder() }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: PastingTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 240
        let lineHeight = view.font?.lineHeight ?? 22
        let fitted = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let maxHeight = ceil(lineHeight * CGFloat(maxLines))
        let scrolls = fitted > maxHeight
        if view.isScrollEnabled != scrolls {
            DispatchQueue.main.async { view.isScrollEnabled = scrolls }
        }
        return CGSize(width: width, height: max(ceil(lineHeight), min(fitted, maxHeight)))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private static var font: UIFont {
        UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: UIFont(name: BrandFont.barlow(.regular), size: 17) ?? .preferredFont(forTextStyle: .body))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerTextView
        let placeholder = UILabel()

        init(_ parent: ComposerTextView) { self.parent = parent }

        func textViewDidChange(_ view: UITextView) {
            parent.text = view.text
            textChanged(view)
        }

        func textChanged(_ view: UITextView) {
            placeholder.isHidden = !view.text.isEmpty
            view.invalidateIntrinsicContentSize()
        }

        func textViewDidBeginEditing(_ view: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ view: UITextView) {
            // Ending editing commits a word the keyboard was still suggesting.
            parent.text = view.text
            if parent.isFocused { parent.isFocused = false }
        }
    }
}

/// A text view whose Paste attaches photos when the clipboard holds them. A Paste the person
/// chose reads the clipboard without iOS's "Allow Paste?" prompt.
final class PastingTextView: UITextView {
    var onPasteImages: (([UIImage]) -> Void)?

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), UIPasteboard.general.hasImages, onPasteImages != nil { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general
        if pasteboard.hasImages, let onPasteImages, let images = pasteboard.images, !images.isEmpty {
            onPasteImages(images)
        } else {
            super.paste(sender)
        }
    }
}
