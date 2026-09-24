import AppKit
import ApplicationServices
import Carbon

// Standalone utility; it does not use or modify the portal experiment.
final class FastTyper: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let editor = NSTextView()
    private let status = NSTextField(wrappingLabelWithString: "Paste text above, then click a destination and press Control + Option + T.")
    private let speed = NSPopUpButton()
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var generation = 0
    private var typing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeMenus()
        makeWindow()
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerResult = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let app = Unmanaged<FastTyper>.fromOpaque(context).takeUnretainedValue()
            app.toggleTyping()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let keyResult = RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey),
                                           EventHotKeyID(signature: 0x46545950, id: 1),
                                           GetApplicationEventTarget(), 0, &hotKey)
        if handlerResult != noErr || keyResult != noErr {
            status.stringValue = "Could not register Control + Option + T. Another app may already use it. Quit that app and reopen Fast Typer."
        }
        showWindow()
    }

    private func makeMenus() {
        let bar = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Show Fast Typer", action: #selector(showWindow), keyEquivalent: "0").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Fast Typer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        bar.addItem(appItem)
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"),
                                     ("Copy", "copy:", "c"), ("Paste", "paste:", "v"),
                                     ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        bar.addItem(editItem)
        NSApp.mainMenu = bar
    }

    private func makeWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Fast Typer"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 380)
        window.center()

        editor.isRichText = false
        editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.allowsUndo = true
        editor.textContainerInset = NSSize(width: 10, height: 10)
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.setAccessibilityLabel("Text to type")
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.documentView = editor

        speed.addItems(withTitles: ["Fast · 8–22 ms per character", "Very fast · 3–10 ms per character", "Slower · 25–50 ms per character"])
        speed.setAccessibilityLabel("Typing speed")
        let permission = NSButton(title: "Enable Accessibility…", target: self, action: #selector(enableAccessibility))
        let hide = NSButton(title: "Hide Window", target: self, action: #selector(hideWindow))
        let controls = NSStackView(views: [permission, hide])
        controls.spacing = 12
        status.textColor = .secondaryLabelColor
        let hint = NSTextField(wrappingLabelWithString: "Control + Option + T starts or stops. Escape also stops. Text stays in memory until you quit.")
        hint.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [NSTextField(labelWithString: "Text to type"), scroll, speed, hint, controls, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    @objc private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func hideWindow() { NSApp.hide(nil) }

    @objc private func enableAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        status.stringValue = trusted ? "Accessibility is enabled. Ready to type." : "Enable Fast Typer in System Settings → Privacy & Security → Accessibility."
    }

    private func stop(_ message: String) {
        generation += 1
        typing = false
        editor.isEditable = true
        speed.isEnabled = true
        status.stringValue = message
    }

    private func toggleTyping() {
        if typing { stop("Stopped."); return }
        guard AXIsProcessTrusted() else {
            status.stringValue = "Click Enable Accessibility, then allow Fast Typer in System Settings."
            showWindow()
            return
        }
        let text = editor.string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard !text.isEmpty else {
            status.stringValue = "Paste or enter text first."
            showWindow()
            return
        }
        guard let target = NSWorkspace.shared.frontmostApplication,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            status.stringValue = "Click the text field in another app, then press Control + Option + T."
            return
        }
        generation += 1
        typing = true
        editor.isEditable = false
        speed.isEnabled = false
        status.stringValue = "Typing into \(target.localizedName ?? "the selected app")… Press the shortcut again or Escape to stop."
        let delays: [ClosedRange<Double>] = [0.008...0.022, 0.003...0.010, 0.025...0.050]
        let token = generation
        let characters = Array(text)
        let deadline = Date().addingTimeInterval(3)
        sendNext(characters, index: 0, targetPID: target.processIdentifier,
                 delay: delays[speed.indexOfSelectedItem], token: token, releaseDeadline: deadline)
    }

    private func sendNext(_ characters: [Character], index: Int, targetPID: pid_t,
                          delay: ClosedRange<Double>, token: Int, releaseDeadline: Date) {
        guard typing && token == generation else { return }
        guard !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Escape)) else {
            stop("Stopped with Escape."); return
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
            stop("Stopped because the active app changed."); return
        }
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        if !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty {
            guard Date() < releaseDeadline else { stop("Stopped. Release the modifier keys before typing."); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.sendNext(characters, index: index, targetPID: targetPID, delay: delay,
                               token: token, releaseDeadline: releaseDeadline)
            }
            return
        }
        guard index < characters.count else { stop("Done — typed \(characters.count) characters."); return }
        guard postCharacter(characters[index]) else { stop("Unable to create keyboard events."); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: delay)) { [weak self] in
            self?.sendNext(characters, index: index + 1, targetPID: targetPID, delay: delay,
                           token: token, releaseDeadline: Date().addingTimeInterval(3))
        }
    }

    private func postCharacter(_ character: Character) -> Bool {
        let key: CGKeyCode = character == "\n" ? CGKeyCode(kVK_Return) : character == "\t" ? CGKeyCode(kVK_Tab) : 0
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return false }
        down.flags = []
        up.flags = []
        if character != "\n" && character != "\t" {
            let units = Array(String(character).utf16)
            units.withUnsafeBufferPointer { buffer in
                if let base = buffer.baseAddress {
                    down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                    up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                }
            }
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        stop("Stopped.")
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

let application = NSApplication.shared
let delegate = FastTyper()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
