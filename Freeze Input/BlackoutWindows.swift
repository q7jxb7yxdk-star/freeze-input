import AppKit

@MainActor
final class BlackoutWindows {
    private var windows: [NSWindow] = []
    private var previousPresentation: NSApplication.PresentationOptions?
    private var cursorHidden = false
    private var gestureMonitor: Any?

    func show(showsBlackScreen: Bool,
              onKeyEvent: @escaping @MainActor (NSEvent) -> Void) -> Bool {
        if showsBlackScreen {
            guard !NSScreen.screens.isEmpty else { return false }
            previousPresentation = NSApp.presentationOptions
            NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching]
            NSApp.activate(ignoringOtherApps: true)
        }
        // Public AppKit gesture events delivered to this app are consumed locally.
        // System gestures handled by WindowServer are outside this monitor's scope.
        gestureMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .gesture, .magnify, .smartMagnify, .rotate, .swipe,
            .beginGesture, .endGesture, .pressure, .directTouch, .keyDown, .keyUp, .flagsChanged
        ]) { event in
            if event.type == .flagsChanged {
                onKeyEvent(event)
                return showsBlackScreen ? nil : event
            }
            if event.type == .keyDown || event.type == .keyUp {
                onKeyEvent(event)
                // Visible inspection mode must not hide a failed keyboard tap
                // by swallowing all ordinary keys again in the local monitor.
                if !showsBlackScreen {
                    let isEscape = event.keyCode == 53
                    let isBackup = event.keyCode == 12 &&
                        (event.type == .keyUp ||
                         event.modifierFlags.contains([.control, .option, .command]))
                    return isEscape || isBackup ? nil : event
                }
            }
            return nil
        }
        // Keep the local exit/gesture monitor in both modes, but create no
        // overlay or cursor/presentation changes in visible inspection mode.
        guard showsBlackScreen else { return true }
        for screen in NSScreen.screens {
            let window = BlackWindow(contentRect: screen.frame, styleMask: .borderless,
                                     backing: .buffered, defer: false)
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.acceptsMouseMovedEvents = true
            window.contentView = BlackView(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
        if let keyWindow = windows.first {
            keyWindow.makeKey()
            keyWindow.makeFirstResponder(keyWindow.contentView)
        }
        NSCursor.hide()
        cursorHidden = true
        return true
    }

    func hide() {
        if let gestureMonitor { NSEvent.removeMonitor(gestureMonitor) }
        gestureMonitor = nil
        windows.forEach { $0.close() }
        windows.removeAll()
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
        if let previousPresentation { NSApp.presentationOptions = previousPresentation }
        previousPresentation = nil
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
