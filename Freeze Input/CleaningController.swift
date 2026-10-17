import AppKit
import Combine

@MainActor
final class CleaningController: ObservableObject {
    static let shared = CleaningController()
    @Published private(set) var isCleaning = false
    @Published private(set) var isBusy = false
    @Published private(set) var isWaitingForExitRelease = false
    @Published private(set) var message: String?
    private let blackout = BlackoutWindows()
    private var watchdog: SessionWatchdog?
    private var sessionID: UUID?
    private var safetyTimer: Timer?
    private var exitKeys = ExitKeyTracker()
    private var cleaningStartedAt: TimeInterval?
    private var focusDeadline: TimeInterval?
    private var sessionDisplays: [DisplayConfiguration]?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    private struct DisplayConfiguration: Equatable {
        let id: UInt32
        let frame: NSRect
        let scale: CGFloat
    }

    private static func currentDisplays() -> [DisplayConfiguration]? {
        var displays: [DisplayConfiguration] = []
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            // Full frame is independent of the space occupied by the Dock/menu bar.
            displays.append(DisplayConfiguration(id: number.uint32Value,
                                                 frame: screen.frame,
                                                 scale: screen.backingScaleFactor))
        }
        guard !displays.isEmpty else { return nil }
        // Screen enumeration order alone is not a layout change.
        return displays.sorted { $0.id < $1.id }
    }

    private var displayConfigurationChanged: Bool {
        guard let sessionDisplays, let current = Self.currentDisplays() else { return true }
        return current != sessionDisplays
    }

    init() {
        observe(NSApplication.didResignActiveNotification, in: .default, reason: .foregroundLost)
        observe(NSApplication.didChangeScreenParametersNotification, in: .default, reason: .displayChanged)
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.willSleepNotification, in: workspace, reason: .sleep)
        observe(NSWorkspace.screensDidSleepNotification, in: workspace, reason: .sleep)
        observe(NSWorkspace.sessionDidResignActiveNotification, in: workspace, reason: .sleep)
        observe(NSWorkspace.didWakeNotification, in: workspace, reason: .sleep)
        observe(NSWorkspace.screensDidWakeNotification, in: workspace, reason: .sleep)
    }

    func start() {
        guard !isBusy else { return }
        guard NSApp.isActive else {
            message = "Return to Freeze Input, then choose Start Cleaning again."
            return
        }
        guard let displays = Self.currentDisplays() else {
            message = "Your display setup could not be checked. Make sure your displays are awake and connected, then try again."
            return
        }
        // Capture before changing presentation options, including during startup.
        sessionDisplays = displays
        let id = UUID()
        sessionID = id
        isBusy = true
        message = nil
        exitKeys = ExitKeyTracker()
        isWaitingForExitRelease = false
        cleaningStartedAt = ProcessInfo.processInfo.systemUptime
        watchdog = SessionWatchdog { [weak self] reason in
            DispatchQueue.main.async {
                guard let self, self.sessionID == id else { return }
                self.stop(reason: reason)
            }
        }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSafety() }
        }
        RunLoop.main.add(timer, forMode: .common)
        safetyTimer = timer
        // Let the Start button's event finish before changing the key window.
        DispatchQueue.main.async { [weak self] in self?.beginOverlay(for: id) }
    }

    private func beginOverlay(for id: UUID) {
        guard sessionID == id else { return }
        guard !displayConfigurationChanged else { stop(reason: .displayChanged); return }
        let failure = blackout.show(onKeyEvent: { [weak self] event in self?.handleLocalKey(event) })
        // A lifecycle notification may already have stopped this session. Preserve its reason.
        guard sessionID == id else { return }
        if let failure {
            stop()
            message = failure
            return
        }
        guard NSApp.isActive else { stop(reason: .foregroundLost); return }
        focusDeadline = ProcessInfo.processInfo.systemUptime + 0.5
    }

    private func handleLocalKey(_ event: NSEvent) {
        guard isCleaning else { return }
        if event.type == .flagsChanged {
            exitKeys.modifiersChanged()
            return
        }
        var flags: CGEventFlags = []
        if event.modifierFlags.contains(.control) { flags.insert(.maskControl) }
        if event.modifierFlags.contains(.option) { flags.insert(.maskAlternate) }
        if event.modifierFlags.contains(.command) { flags.insert(.maskCommand) }
        let reason = exitKeys.handle(keyCode: Int64(event.keyCode),
                                     isDown: event.type == .keyDown,
                                     isRepeat: event.type == .keyDown && event.isARepeat,
                                     modifiers: flags, now: ProcessInfo.processInfo.systemUptime)
        isWaitingForExitRelease = exitKeys.isWaitingForBackupRelease
        if let reason { stop(reason: reason) }
    }

    private func checkSafety() {
        guard isBusy, let cleaningStartedAt else { return }
        let now = ProcessInfo.processInfo.systemUptime
        watchdog?.pulse()
        if CleaningSessionPolicy.shouldExpire(startedAt: cleaningStartedAt, now: now) {
            stop(reason: .safetyDeadline)
        } else if !NSApp.isActive {
            stop(reason: .foregroundLost)
        } else if let focusDeadline {
            if blackout.hasKeyboardFocus {
                self.focusDeadline = nil
                isCleaning = true
            } else if now >= focusDeadline {
                stop()
                message = "The cleaning cover could not become ready for keyboard input. Return to Freeze Input and try again."
            } else {
                blackout.requestKeyboardFocus()
            }
        } else if isCleaning, exitKeys.releaseWaitExpired(now: now) {
            stop(reason: .backupShortcut)
        }
    }

    func stop(reason: CleaningExitReason = .stopped) {
        sessionID = nil // Ignore queued callbacks from an older session.
        isCleaning = false
        safetyTimer?.invalidate()
        safetyTimer = nil
        cleaningStartedAt = nil
        focusDeadline = nil
        sessionDisplays = nil
        exitKeys = ExitKeyTracker()
        isWaitingForExitRelease = false
        let previousWatchdog = watchdog
        watchdog = nil
        blackout.hide()
        // Cancellation acknowledges actual AppKit cleanup, not merely a queued callback.
        previousWatchdog?.stop()
        isBusy = false
        message = reason.rawValue
    }

    func shutdown() {
        stop()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    private func observe(_ name: Notification.Name, in center: NotificationCenter,
                         reason: CleaningExitReason) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.sessionID != nil else { return }
                if reason == .displayChanged, !self.displayConfigurationChanged { return }
                self.stop(reason: reason)
            }
        }
        observers.append((center, token))
    }
}
