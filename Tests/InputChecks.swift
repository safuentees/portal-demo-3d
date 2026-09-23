import AppKit
import MetalKit
import simd

/// Exercises native callbacks in hidden windows with inert cursor operations.
@MainActor
enum InputChecks {
    private final class InputWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    static func run() throws {
        try checkCamera()
        _ = NSApplication.shared
        let window = makeWindow()
        let reopenedWindow = makeWindow()
        defer {
            window.close()
            reopenedWindow.close()
        }

        var cursorEvents: [String] = []
        let view = KeyboardMetalView(
            frame: CGRect(x: 0, y: 0, width: 64, height: 64), device: nil,
            cursorControl: .init(
                capture: { cursorEvents.append("capture") },
                release: { cursorEvents.append("release") }
            )
        )
        view.isPaused = true
        window.contentView?.addSubview(view)
        try SmokeTests.expect(window.makeFirstResponder(view), "The input fixture could not take focus.")
        let forward = try key("w", code: 13)
        let escape = try key("\u{1b}", code: 53)
        let mouse = try mouseDelta(x: 6, y: -4)

        func queueInput() {
            view.enableMouseLook()
            view.keyDown(with: forward)
            view.mouseMoved(with: mouse)
        }

        func expectReleased(_ reason: String) throws {
            try SmokeTests.expect(!view.mouseLookEnabled, "\(reason) left mouse capture enabled.")
            try SmokeTests.expect(view.movementDirection == .zero, "\(reason) left held movement.")
            try SmokeTests.expect(view.consumeMouseDelta() == .zero, "\(reason) left a pending mouse delta.")
            try SmokeTests.expect(cursorEvents.count % 2 == 0,
                                  "\(reason) did not balance cursor capture and release.")
        }

        queueInput()
        view.enableMouseLook()
        try SmokeTests.expect(cursorEvents == ["capture"], "Repeated capture hid the cursor twice.")
        try SmokeTests.expect(view.movementDirection == SIMD3<Float>(0, 0, 1), "W must move along local +Z.")
        try SmokeTests.expect(view.consumeMouseDelta() == SIMD2<Float>(6, -4), "Mouse deltas changed signs.")
        try SmokeTests.expect(view.consumeMouseDelta() == .zero, "Mouse deltas must be consumed only once.")
        view.mouseMoved(with: mouse)
        view.keyDown(with: escape)
        try expectReleased("Escape")
        view.keyDown(with: escape)
        view.keyDown(with: forward)
        view.keyDown(with: escape)
        try expectReleased("Escape without capture")
        try SmokeTests.expect(cursorEvents == ["capture", "release"], "Repeated release unhid the cursor twice.")

        queueInput()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: reopenedWindow)
        try SmokeTests.expect(view.mouseLookEnabled, "A different window incorrectly released capture.")
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        try expectReleased("Window focus loss")

        queueInput()
        try SmokeTests.expect(window.makeFirstResponder(nil), "The input fixture could not relinquish focus.")
        try expectReleased("First responder loss")
        try SmokeTests.expect(window.makeFirstResponder(view), "The input fixture could not regain focus.")

        queueInput()
        view.removeFromSuperview()
        try expectReleased("Retained view detachment")
        let afterDetachment = cursorEvents
        view.enableMouseLook()
        try SmokeTests.expect(cursorEvents == afterDetachment, "A detached view captured the cursor.")

        // Keep this same instance alive and reattach it; release cannot depend on deinit.
        reopenedWindow.contentView?.addSubview(view)
        try SmokeTests.expect(reopenedWindow.makeFirstResponder(view), "The reopened view could not take focus.")
        try expectReleased("Reopening")
        queueInput()
        let coordinator = MetalView.Coordinator()
        MetalView.dismantleNSView(view, coordinator: coordinator)
        try expectReleased("SwiftUI dismantling while retained and attached")
        try SmokeTests.expect(view.isPaused && view.delegate == nil, "Dismantling left rendering active.")
        let afterDismantling = cursorEvents
        view.enableMouseLook()
        view.keyDown(with: forward)
        view.mouseMoved(with: mouse)
        try expectReleased("Input after dismantling")
        MetalView.dismantleNSView(view, coordinator: coordinator)
        try SmokeTests.expect(cursorEvents == afterDismantling, "Repeated dismantling unbalanced the cursor.")

        view.removeFromSuperview()
        window.contentView?.addSubview(view)
        try SmokeTests.expect(window.makeFirstResponder(view), "The reused view could not take focus.")
        queueInput()
        try SmokeTests.expect(view.mouseLookEnabled, "Reattaching after teardown did not restore input.")
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        try expectReleased("Focus loss after reattachment")

        queueInput()
        window.close()
        try expectReleased("Closing a window with a retained captured view")
        let afterClose = cursorEvents
        view.enableMouseLook()
        try SmokeTests.expect(cursorEvents == afterClose, "A retained closed window allowed capture.")
        view.removeFromSuperview()
        reopenedWindow.contentView?.addSubview(view)
        try SmokeTests.expect(reopenedWindow.makeFirstResponder(view), "A view from a closed window could not regain focus.")
        try expectReleased("Opening a view after its window closed")
        queueInput()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: reopenedWindow)
        try expectReleased("Focus loss after reopening a closed view")
        view.removeFromSuperview()
        try SmokeTests.expect(cursorEvents.enumerated().allSatisfy {
            $0.element == ($0.offset.isMultiple(of: 2) ? "capture" : "release")
        }, "Cursor calls must alternate capture/release throughout the view lifecycle.")
        print("PASS: input signs, one-time mouse consumption, Escape/focus/detachment/teardown/close/reopen lifecycle")
    }

    private static func checkCamera() throws {
        let sensitivity = SceneConfiguration.mouseSensitivity
        var camera = Camera()
        camera.updateDirection([10, -20])
        try SmokeTests.expect(abs(camera.yaw - 10 * sensitivity) < 0.00001
            && abs(camera.pitch - 20 * sensitivity) < 0.00001,
            "Mouse look must preserve the existing yaw/pitch signs and sensitivity.")
        var grouped = Camera()
        grouped.updateDirection([3, -7])
        grouped.updateDirection([7, -13])
        try SmokeTests.expect(abs(grouped.yaw - camera.yaw) < 0.00001
            && abs(grouped.pitch - camera.pitch) < 0.00001,
            "Mouse look must depend on accumulated travel, not frame grouping.")

        var turned = Camera()
        turned.updateDirection([(.pi / 2) / sensitivity, 0.7 / sensitivity])
        turned.updateMovement(direction: [0, 0, 1], deltaTime: 0.05)
        try SmokeTests.expect(simd_length(turned.position - SIMD3<Float>(SceneConfiguration.cameraSpeed * 0.05, 0, 0)) < 0.0001,
            "Forward movement must use inverse yaw and ignore pitch for grounded controls.")

        let baseWorld = Transforms.rotateY(0.6) * Transforms.translation([3, 2, -4])
        var placed = Camera(viewMatrix: simd_inverse(baseWorld))
        placed.updateMovement(direction: [0, 0, 1], deltaTime: 0.05)
        let expectedEye = SIMD4<Float>(placed.position, 1) * baseWorld
        try SmokeTests.expect(simd_length(placed.worldPosition - SIMD3(expectedEye.x, expectedEye.y, expectedEye.z)) < 0.0001,
            "The world eye must include base placement as well as the movement offset.")
        try SmokeTests.expect(simd_length(SIMD4<Float>(placed.worldPosition, 1) * placed.viewMatrix
            - SIMD4<Float>(0, 0, 0, 1)) < 0.0001, "The complete view must map the world eye to the origin.")
    }

    private static func makeWindow() -> NSWindow {
        let window = InputWindow(contentRect: CGRect(x: 0, y: 0, width: 64, height: 64),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        return window
    }

    private static func key(_ characters: String, code: UInt16) throws -> NSEvent {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else {
            throw SmokeTests.Failure(description: "Could not construct a keyboard test event.")
        }
        return event
    }

    private static func mouseDelta(x: Int64, y: Int64) throws -> NSEvent {
        guard let cgEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                   mouseCursorPosition: .zero, mouseButton: .left) else {
            throw SmokeTests.Failure(description: "Could not construct a mouse test event.")
        }
        cgEvent.setIntegerValueField(.mouseEventDeltaX, value: x)
        cgEvent.setIntegerValueField(.mouseEventDeltaY, value: y)
        guard let event = NSEvent(cgEvent: cgEvent) else {
            throw SmokeTests.Failure(description: "Could not wrap the mouse test event.")
        }
        return event
    }
}
