import AppKit
import MetalKit

/// MTKView responsible for collecting keyboard and mouse input.
/// The renderer consumes the current input state each frame.
final class KeyboardMetalView: MTKView {
    /// Injected in checks so lifecycle coverage never hides or moves the user's cursor.
    struct CursorControl {
        let capture: () -> Void
        let release: () -> Void

        static let system = CursorControl(
            capture: {
                NSCursor.hide()
                CGAssociateMouseAndMouseCursorPosition(0)
            },
            release: {
                CGAssociateMouseAndMouseCursorPosition(1)
                NSCursor.unhide()
            }
        )
    }

    private let cursorControl: CursorControl
    private var inputEnabled = false

    override convenience init(frame: CGRect, device: MTLDevice?) {
        self.init(frame: frame, device: device, cursorControl: .system)
    }

    init(frame: CGRect, device: MTLDevice?, cursorControl: CursorControl) {
        self.cursorControl = cursorControl
        super.init(frame: frame, device: device)
    }

    required init(coder: NSCoder) {
        cursorControl = .system
        super.init(coder: coder)
    }

    // MARK: - Keyboard

    /// Physical key code -> logical key.
    /// Using the physical code ensures keyUp still works if modifiers change.
    private var pressedKeys: [UInt16: String] = [:]

    override var acceptsFirstResponder: Bool { true }


    // MARK: - Mouse

    private var mouseTrackingArea: NSTrackingArea?

    private var accumulatedMouseDelta = SIMD2<Double>.zero

    private(set) var mouseLookEnabled = false

    /// Returns all mouse movement accumulated since the previous call.
    func consumeMouseDelta() -> SIMD2<Float> {
        let delta = accumulatedMouseDelta
        accumulatedMouseDelta = .zero

        return SIMD2<Float>(
            Float(delta.x),
            Float(delta.y)
        )
    }

    func enableMouseLook() {
        guard inputEnabled, window?.isKeyWindow == true,
              window?.firstResponder === self, !mouseLookEnabled else { return }

        mouseLookEnabled = true
        accumulatedMouseDelta = .zero

        cursorControl.capture()
    }

    func disableMouseLook() {
        // Clear all input even when capture was already released. Escape and
        // focus changes must not leave held movement or a pending look update.
        pressedKeys.removeAll()
        accumulatedMouseDelta = .zero
        guard mouseLookEnabled else { return }

        mouseLookEnabled = false
        cursorControl.release()
    }


    // MARK: - Movement

    var movementDirection: SIMD3<Float> {
        guard inputEnabled, window?.isKeyWindow == true,
              window?.firstResponder === self
        else {
            return .zero
        }

        let keys = Set(pressedKeys.values)

        var direction = SIMD3<Float>.zero

        if keys.contains("a") { direction.x -= 1 }
        if keys.contains("d") { direction.x += 1 }

        // This scene's camera looks along +Z.
        if keys.contains("w") { direction.z += 1 }
        if keys.contains("s") { direction.z -= 1 }

        // Prevent diagonal movement from being faster.
        if simd_length_squared(direction) > 0 {
            direction = simd_normalize(direction)
        }

        return direction
    }


    // MARK: - Window

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            // Detachment may leave this view retained, so do not wait for deinit.
            tearDownInput()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tearDownInput()

        guard let window else { return }
        inputEnabled = true

        window.initialFirstResponder = self
        window.makeFirstResponder(self)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }


    // MARK: - Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let mouseTrackingArea {
            removeTrackingArea(mouseTrackingArea)
        }

        let area = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseMoved,
                .mouseEnteredAndExited,
                .activeInKeyWindow,
                .inVisibleRect,
                .enabledDuringMouseDrag
            ],
            owner: self,
            userInfo: nil
        )

        addTrackingArea(area)
        mouseTrackingArea = area
    }


    // MARK: - Mouse Events

    override func mouseMoved(with event: NSEvent) {
        guard mouseLookEnabled else { return }

        accumulatedMouseDelta.x += Double(event.deltaX)
        accumulatedMouseDelta.y += Double(event.deltaY)
    }

    override func mouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        enableMouseLook()
    }


    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        guard inputEnabled else { return }
        // Escape releases the mouse.
        if event.keyCode == 53 {
            disableMouseLook()
            return
        }

        // Leave Command/Control/Option shortcuts to AppKit.
        guard event.modifierFlags
                  .intersection([.command, .control, .option])
                  .isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased(),
              ["w", "a", "s", "d"].contains(key)
        else {
            super.keyDown(with: event)
            return
        }

        pressedKeys[event.keyCode] = key
    }

    override func keyUp(with event: NSEvent) {
        if pressedKeys.removeValue(forKey: event.keyCode) == nil {
            super.keyUp(with: event)
        }
    }


    // MARK: - Focus

    override func resignFirstResponder() -> Bool {
        disableMouseLook()

        return super.resignFirstResponder()
    }

    @objc
    private func windowDidResignKey(_ notification: Notification) {
        // Prevent stuck input when switching to another application.
        disableMouseLook()
    }

    @objc
    private func windowWillClose(_ notification: Notification) {
        // A closed window can retain its content view after focus has changed.
        tearDownInput()
    }


    // MARK: - Cleanup

    /// Called both by AppKit detachment and explicitly by SwiftUI dismantling.
    /// Reattaching to a window starts a fresh input lifecycle.
    func tearDownInput() {
        inputEnabled = false
        disableMouseLook()
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.didResignKeyNotification, object: nil
        )
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.willCloseNotification, object: nil
        )
    }

    deinit {
        // Last-resort balance only; normal release happens while the view lives.
        if mouseLookEnabled {
            cursorControl.release()
        }

        NotificationCenter.default.removeObserver(self)
    }
}
