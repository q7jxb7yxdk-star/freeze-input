import AppKit
import Carbon
import Combine

@MainActor
final class CleaningController: ObservableObject {
    static let shared = CleaningController()
    /// Set to true for normal cleaning; false keeps the screen/cursor visible
    /// so input interception can be inspected. Requires rebuilding the app.
    static let showsBlackScreen = true
    @Published private(set) var isCleaning = false
    @Published private(set) var isBusy = false
    @Published private(set) var hasPermission = AccessibilityPermission.isGranted
    @Published private(set) var message: String?
    private let blackout = BlackoutWindows()
    private var interceptor: InputInterceptor?
    private var sessionID: UUID?
    private var heartbeatTimer: Timer?
    private var localSafetyTimer: Timer?
    private var localExitKeys = ExitKeyTracker()
    private var cleaningStartedAt: TimeInterval?
    private var pendingLocalExit: (reason: CleaningExitReason, requestedAt: TimeInterval)?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        observe(NSApplication.didResignActiveNotification, in: .default, reason: .foregroundLost)
        observe(NSApplication.didChangeScreenParametersNotification, in: .default, reason: .displayChanged)
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.willSleepNotification, in: workspace, reason: .sleep)
        observe(NSWorkspace.screensDidSleepNotification, in: workspace, reason: .sleep)
        observe(NSWorkspace.sessionDidResignActiveNotification, in: workspace, reason: .sleep)
        observe(NSWorkspace.didWakeNotification, in: workspace, reason: .sleep)
        observe(NSWorkspace.screensDidWakeNotification, in: workspace, reason: .sleep)
        let token = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermission() }
        }
        observers.append((.default, token))
        // Runs in common modes, so ordinary menu tracking does not starve the heartbeat.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.interceptor?.pulse()
                self?.refreshPermission()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    func refreshPermission() {
        hasPermission = AccessibilityPermission.isGranted
        if isCleaning, !hasPermission { stop(reason: .permissionLost) }
    }

    func requestPermission() {
        AccessibilityPermission.request()
        refreshPermission()
    }

    func start() {
        guard !isBusy else { return }
        refreshPermission()
        guard hasPermission else {
            message = "Allow Freeze Input in System Settings → Privacy & Security → Accessibility (or Device Control and Data Access), then return here."
            return
        }
        guard !IsSecureEventInputEnabled() else {
            message = CleaningExitReason.secureInput.rawValue
            return
        }
        message = nil
        isBusy = true
        let id = UUID()
        sessionID = id
        let input = InputInterceptor(onExit: { [weak self] reason in
            DispatchQueue.main.async {
                guard let self, self.sessionID == id else { return }
                // The worker has already released general input interception.
                // Keep it alive only to consume release/repeat events for the exit key.
                self.clearLocalSafety()
                self.isCleaning = false
                self.blackout.hide()
                self.message = reason.rawValue
            }
        }, onFinished: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.sessionID == id else { return }
                self.clearLocalSafety()
                self.blackout.hide()
                self.isCleaning = false
                self.isBusy = false
                self.interceptor = nil
                self.sessionID = nil
            }
        })
        interceptor = input
        guard input.start() else {
            stop(reason: .tapDisabled)
            message = input.failureDescription
            return
        }
        // Recheck after the worker startup wait; avoid entering a cancelled session.
        guard AccessibilityPermission.isGranted, !IsSecureEventInputEnabled(),
              NSApp.isActive, blackout.show(showsBlackScreen: Self.showsBlackScreen,
                                           onKeyEvent: { [weak self] event in
                  self?.handleLocalKey(event)
              }) else {
            stop(reason: .stopped)
            message = "Cleaning could not start safely. Return to Freeze Input and try again."
            return
        }
        isCleaning = true
        if !Self.showsBlackScreen {
            message = "Input filtering is active with the screen visible. Press and release Esc 5 times within 3 seconds to finish."
        }
        cleaningStartedAt = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkLocalSafety() }
        }
        RunLoop.main.add(timer, forMode: .common)
        localSafetyTimer = timer
    }

    private func handleLocalKey(_ event: NSEvent) {
        if event.type == .keyUp, pendingLocalExit != nil {
            // The release may arrive before the worker services requestExit.
            interceptor?.acknowledgeLocalRelease(keyCode: Int64(event.keyCode))
        }
        guard isCleaning else { return }
        if event.type == .flagsChanged {
            localExitKeys.reset()
            return
        }
        var flags: CGEventFlags = []
        if event.modifierFlags.contains(.control) { flags.insert(.maskControl) }
        if event.modifierFlags.contains(.option) { flags.insert(.maskAlternate) }
        if event.modifierFlags.contains(.command) { flags.insert(.maskCommand) }
        let now = ProcessInfo.processInfo.systemUptime
        if let decision = localExitKeys.handle(keyCode: Int64(event.keyCode),
                                               isDown: event.type == .keyDown,
                                               isRepeat: event.type == .keyDown && event.isARepeat,
                                               modifiers: flags, now: now) {
            requestLocalExit(decision.reason, draining: decision.releaseKey, now: now)
        }
    }

    private func checkLocalSafety() {
        guard isCleaning, let cleaningStartedAt else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let pendingLocalExit {
            // If the worker cannot service the fallback, the UI can still release
            // input and close its windows without waiting for a worker callback.
            if now - pendingLocalExit.requestedAt >= 0.25 {
                stop(reason: pendingLocalExit.reason)
            }
        } else if CleaningSessionPolicy.shouldExpire(startedAt: cleaningStartedAt, now: now) {
            stop(reason: .safetyDeadline)
        }
    }

    private func requestLocalExit(_ reason: CleaningExitReason, draining key: Int64?,
                                  now: TimeInterval) {
        guard pendingLocalExit == nil else { return }
        pendingLocalExit = (reason, now)
        interceptor?.requestExit(reason, draining: key)
    }

    private func clearLocalSafety() {
        localSafetyTimer?.invalidate()
        localSafetyTimer = nil
        cleaningStartedAt = nil
        pendingLocalExit = nil
        localExitKeys = ExitKeyTracker()
    }

    func stop(reason: CleaningExitReason = .stopped) {
        clearLocalSafety()
        sessionID = nil // Ignore late callbacks from a previous worker.
        interceptor?.stop()
        interceptor = nil
        blackout.hide()
        isCleaning = false
        isBusy = false
        message = reason.rawValue
    }

    func shutdown() {
        stop()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    private func observe(_ name: Notification.Name, in center: NotificationCenter,
                         reason: CleaningExitReason) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isBusy else { return }
                // Preserve the Esc/Q release filter if another app gains focus
                // after visual exit. Sleep and display changes still stop it.
                if reason == .foregroundLost && !self.isCleaning { return }
                self.stop(reason: reason)
            }
        }
        observers.append((center, token))
    }
}
