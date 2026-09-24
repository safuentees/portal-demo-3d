import AppKit

/// Temporarily provides plain text for a paste, preserving every readable format.
/// A newer clipboard write by another app always takes precedence over restoration.
final class ClipboardLease {
    private let pasteboard: NSPasteboard
    private let originalItems: [[NSPasteboard.PasteboardType: Data]]
    private var changeCount: Int
    private var restored = false

    init?(text: String, pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        let initialCount = pasteboard.changeCount
        var originals: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var formats: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                // Do not discard a clipboard format that cannot be preserved.
                guard let data = item.data(forType: type) else { return nil }
                formats[type] = data
            }
            originals.append(formats)
        }
        guard pasteboard.changeCount == initialCount else { return nil }
        originalItems = originals
        changeCount = pasteboard.clearContents()
        let written = pasteboard.setString(text, forType: .string)
        changeCount = pasteboard.changeCount
        if !written {
            restore()
            return nil
        }
    }

    func restore() {
        guard !restored else { return }
        restored = true
        guard pasteboard.changeCount == changeCount else { return }
        let items = originalItems.map { formats -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in formats { item.setData(data, forType: type) }
            return item
        }
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
