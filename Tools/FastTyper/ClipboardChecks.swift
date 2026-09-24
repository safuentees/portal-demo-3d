import AppKit

@main
enum ClipboardChecks {
    static func main() {
        let board = NSPasteboard(name: NSPasteboard.Name("FastTyperChecks-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let snippet = """
        if (bookTitle1.compareTo(bookTitle2) >= 0) {
            lastAlphabetically = bookTitle1;
        } else {
            lastAlphabetically = bookTitle2;
        }
        """
        let original = NSPasteboardItem()
        original.setString("original clipboard", forType: .string)
        let richData = Data("{\\rtf1 original clipboard}".utf8)
        original.setData(richData, forType: .rtf)
        let second = NSPasteboardItem()
        second.setString("second item", forType: .string)
        board.clearContents()
        precondition(board.writeObjects([original, second]))
        guard let lease = ClipboardLease(text: snippet, pasteboard: board) else { fatalError("Cannot prepare paste") }
        precondition(board.string(forType: .string) == snippet, "Java snippet changed")
        precondition(board.pasteboardItems?.count == 1)
        lease.restore()
        precondition(board.pasteboardItems?.count == 2)
        precondition(board.pasteboardItems?[0].string(forType: .string) == "original clipboard")
        precondition(board.pasteboardItems?[0].data(forType: .rtf) == richData)
        precondition(board.pasteboardItems?[1].string(forType: .string) == "second item")

        let unicode = "\t你好 👩🏽‍💻 café e\u{301}\n{\n\t\"quoted\"\n}\n"
        guard let concurrent = ClipboardLease(text: unicode, pasteboard: board) else { fatalError("Cannot prepare Unicode") }
        precondition(board.string(forType: .string) == unicode)
        board.clearContents()
        board.setString("new copy from user", forType: .string)
        concurrent.restore()
        precondition(board.string(forType: .string) == "new copy from user", "Overwrote newer clipboard")
        lease.restore()
        precondition(board.string(forType: .string) == "new copy from user", "Restoration was not idempotent")

        board.clearContents()
        guard let empty = ClipboardLease(text: snippet, pasteboard: board) else { fatalError("Cannot use empty clipboard") }
        empty.restore()
        precondition(board.pasteboardItems?.isEmpty != false, "Empty clipboard not restored")
        print("PASS: exact Java snippet, Unicode, indentation, multiple clipboard items/formats, empty clipboard, and newer-copy preservation")
    }
}
