import AppKit

/// Everything on the clipboard, every item in every form it was offered in, so putting it back after a paste returns
/// an image, a file or rich text as it was, not only its plain text.
struct ClipboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(of board: NSPasteboard) {
        items = (board.pasteboardItems ?? []).map { item in
            var forms: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { forms[type] = data }
            }
            return forms
        }.filter { !$0.isEmpty }
    }

    func restore(to board: NSPasteboard) {
        board.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { forms -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in forms { item.setData(data, forType: type) }
            return item
        }
        board.writeObjects(restored)
    }
}
