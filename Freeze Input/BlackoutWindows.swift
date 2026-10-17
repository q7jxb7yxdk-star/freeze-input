import AppKit

@MainActor
final class BlackoutWindows {
    private var windows: [NSWindow] = []
    private var previousPresentation: NSApplication.PresentationOptions?
    private var cursorHidden = false
    private var gestureMonitor: Any?
    private var presentationID: UUID?

    var hasKeyboardFocus: Bool {
        windows.contains { window in
            window.isVisible && window.isKeyWindow &&
                window.contentView != nil && window.firstResponder === window.contentView
        }
    }

    func requestKeyboardFocus() {
        guard presentationID != nil, let keyWindow = windows.first else { return }
        keyWindow.makeKeyAndOrderFront(nil)
        guard presentationID != nil else { return }
        keyWindow.makeFirstResponder(keyWindow.contentView)
    }

    /// Installs the overlay. The controller confirms keyboard readiness with a deadline.
    /// A non-nil result describes the specific installation failure.
    func show(onKeyEvent: @escaping @MainActor (NSEvent) -> Void) -> String? {
        guard NSApp.isActive else { return "Return to Freeze Input, then choose Start Cleaning again." }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return "No displays are available. Make sure your displays are awake and connected, then try again." }
        guard windows.isEmpty, gestureMonitor == nil else {
            return "The previous cleaning cover is still closing. Wait a moment, then try again."
        }
        let id = UUID()
        presentationID = id
        // Only events dispatched to this app are consumed. System shortcuts,
        // WindowServer gestures and events destined for other apps are unaffected.
        guard let monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .mouseMoved,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel,
            .gesture, .magnify, .smartMagnify, .rotate, .swipe,
            .beginGesture, .endGesture, .pressure, .directTouch
        ], handler: { event in
            if event.type == .keyDown || event.type == .keyUp || event.type == .flagsChanged {
                onKeyEvent(event)
            }
            return nil
        }) else { return "The cleaning cover could not handle input. Quit and reopen Freeze Input, then try again." }
        gestureMonitor = monitor
        previousPresentation = NSApp.presentationOptions
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching]
        for screen in screens {
            guard presentationID == id else { return "Cleaning was cancelled while preparing your displays. Return to Freeze Input and try again." }
            let window = BlackWindow(contentRect: screen.frame, styleMask: .borderless,
                                     backing: .buffered, defer: false)
            guard presentationID == id else { return "Cleaning was cancelled while opening the cleaning cover. Return to Freeze Input and try again." }
            windows.append(window)
            window.backgroundColor = .black
            window.isOpaque = true
            // Use transparency for observation; set to 1.0 to restore the fully opaque black overlay.
            window.alphaValue = 1
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.acceptsMouseMovedEvents = true
            window.contentView = BlackView(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.setFrame(screen.frame, display: true)
            guard presentationID == id else { return "Cleaning was cancelled while positioning the cleaning cover. Check your display setup and try again." }
            window.orderFrontRegardless()
        }
        guard presentationID == id, !windows.isEmpty else {
            return "The cleaning cover closed before it was ready. Return to Freeze Input and try again."
        }
        requestKeyboardFocus()
        guard presentationID == id else { return "Cleaning was cancelled while preparing keyboard input. Return to Freeze Input and try again." }
        NSCursor.hide()
        cursorHidden = true
        return nil
    }

    func hide() {
        presentationID = nil
        let monitor = gestureMonitor
        gestureMonitor = nil
        let ownedWindows = windows
        windows.removeAll()
        let restoreCursor = cursorHidden
        cursorHidden = false
        let presentation = previousPresentation
        previousPresentation = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        ownedWindows.forEach { $0.close() }
        if restoreCursor { NSCursor.unhide() }
        if let presentation { NSApp.presentationOptions = presentation }
    }
}

private final class BlackWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class BlackView: NSView {
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()
    }
    override func keyDown(with event: NSEvent) {}
    override func keyUp(with event: NSEvent) {}
    override func magnify(with event: NSEvent) {}
    override func rotate(with event: NSEvent) {}
    override func swipe(with event: NSEvent) {}
    override func smartMagnify(with event: NSEvent) {}
}
