import AppKit
import ApplicationServices
import Carbon
import Darwin

/// Dedicated RunLoop owns all event and Esc-sequence state. Only resource publication,
/// cancellation and the UI heartbeat cross threads, under `lock`.
nonisolated final class InputInterceptor: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var taps: [CFMachPort] = []
    private var startupFailure = "Input filter startup failed."
    private var runLoop: CFRunLoop?
    private var heartbeat = ProcessInfo.processInfo.systemUptime
    private let onExit: @Sendable (CleaningExitReason) -> Void
    private let onFinished: @Sendable () -> Void
    private var exitKeys = ExitKeyTracker()
    private var startedAt: TimeInterval = 0
    private var releaseDeadline: TimeInterval?
    private var releaseKey: Int64?
    private var locallyReleasedExitKeys: Set<Int64> = []
    private var exitReported = false
    private var recoveryAcknowledged = false // Protected by lock.

    init(onExit: @escaping @Sendable (CleaningExitReason) -> Void,
         onFinished: @escaping @Sendable () -> Void) {
        self.onExit = onExit
        self.onFinished = onFinished
    }

    /// Returns only after the tap/source/timer are installed and enabled.
    func start() -> Bool {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in run(ready: ready) }
        thread.name = "Freeze Input Event Tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        guard ready.wait(timeout: .now() + 2) == .success else {
            stop()
            return false
        }
        lock.lock()
        let installed = taps.count == 2 && !cancelled
        lock.unlock()
        return installed
    }

    var failureDescription: String {
        lock.lock()
        defer { lock.unlock() }
        return startupFailure
    }

    /// Serialize the local AppKit fallback through the worker when responsive.
    /// The controller has its own deadline if this request cannot be serviced.
    func requestExit(_ reason: CleaningExitReason, draining key: Int64?) {
        lock.lock()
        let loop = runLoop
        let isCancelled = cancelled
        lock.unlock()
        guard !isCancelled, let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { [self] in
            finish(reason, draining: key)
        }
        CFRunLoopWakeUp(loop)
    }

    func acknowledgeLocalRelease(keyCode: Int64) {
        guard keyCode == 53 || keyCode == 12 else { return }
        lock.lock()
        let loop = runLoop
        let isCancelled = cancelled
        lock.unlock()
        guard !isCancelled, let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { [self] in
            locallyReleasedExitKeys.insert(keyCode)
            if releaseKey == keyCode { stop() }
        }
        CFRunLoopWakeUp(loop)
    }

    func pulse() {
        lock.lock()
        heartbeat = ProcessInfo.processInfo.systemUptime
        lock.unlock()
    }

    /// Idempotent and synchronous input release, even if the UI or worker stalls.
    func stop() {
        lock.lock()
        cancelled = true
        let currentTaps = taps
        let currentLoop = runLoop
        lock.unlock()
        currentTaps.forEach { CGEvent.tapEnable(tap: $0, enable: false) }
        if let currentLoop {
            CFRunLoopStop(currentLoop)
            CFRunLoopWakeUp(currentLoop)
        }
    }

    private static func mask(for types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    }

    private static func hasEffectiveKeyboardTap(requiredMask: CGEventMask) -> Bool {
        // Allocate with headroom and fail closed if the list changed/truncated.
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success else { return false }
        var entries = [CGEventTapInformation](repeating: CGEventTapInformation(),
                                              count: Int(count) + 16)
        let capacity = UInt32(entries.count)
        guard CGGetEventTapList(capacity, &entries, &count) == .success,
              count <= capacity else { return false }
        return InputTapRequirements.permitsKeyboard(entries: Array(entries.prefix(Int(count))),
                                                    processID: getpid(), requiredMask: requiredMask)
    }

    private func run(ready: DispatchSemaphore) {
        let keyboardTypes: [CGEventType] = [.keyDown, .keyUp]
        let pointerTypes: [CGEventType] = [
            .flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .mouseMoved,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel
        ]
        let keyboardMask = Self.mask(for: keyboardTypes)
        var installedTaps: [CFMachPort] = []
        var sources: [CFRunLoopSource] = []
        func failStartup(_ description: String) {
            installedTaps.forEach { CFMachPortInvalidate($0) }
            lock.lock()
            startupFailure = description
            cancelled = true
            lock.unlock()
            ready.signal()
            onFinished()
        }
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else {
            failStartup("Keyboard filtering is unavailable. Check Accessibility and Secure Event Input.")
            return
        }
        for types in [keyboardTypes, pointerTypes] {
            guard let newTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: Self.mask(for: types),
                callback: { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    let owner = Unmanaged<InputInterceptor>.fromOpaque(context).takeUnretainedValue()
                    return owner.filter(type: type, event: event)
                }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
                failStartup("Could not create the keyboard and pointer filters. Re-add the running app in Accessibility settings, then relaunch it.")
                return
            }
            installedTaps.append(newTap)
            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
                failStartup("Could not install an input filter RunLoop source.")
                return
            }
            sources.append(source)
        }
        // A mixed mouse/keyboard tap can succeed with its keyboard bits stripped.
        // Require both effective keyboard bits in an enabled tap owned by this PID.
        guard Self.hasEffectiveKeyboardTap(requiredMask: keyboardMask) else {
            failStartup("macOS did not enable both keyboard press and release filtering. Cleaning was cancelled. Re-add the Xcode-built Freeze Input app in Accessibility settings, then relaunch it.")
            return
        }
        let loop = CFRunLoopGetCurrent()!
        startedAt = ProcessInfo.processInfo.systemUptime
        let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent() + 0.05, 0.05, 0, 0) { [weak self] _ in
                self?.checkHealth()
            }!
        sources.forEach { CFRunLoopAddSource(loop, $0, .defaultMode) }
        CFRunLoopAddTimer(loop, timer, .defaultMode)
        lock.lock()
        taps = installedTaps
        runLoop = loop
        let wasCancelled = cancelled
        if !wasCancelled { installedTaps.forEach { CGEvent.tapEnable(tap: $0, enable: true) } }
        let enabled = !wasCancelled && installedTaps.allSatisfy { CGEvent.tapIsEnabled(tap: $0) }
        if !enabled { cancelled = true }
        lock.unlock()
        ready.signal()
        if enabled {
            // Bounded runs also handle cancellation immediately before a run begins.
            while true {
                lock.lock()
                let shouldStop = cancelled
                lock.unlock()
                if shouldStop { break }
                let result = CFRunLoopRunInMode(.defaultMode, 0.25, false)
                if result == .finished {
                    finish(.tapDisabled)
                    break
                }
            }
        }
        installedTaps.forEach { CGEvent.tapEnable(tap: $0, enable: false) }
        CFRunLoopTimerInvalidate(timer)
        CFRunLoopRemoveTimer(loop, timer, .defaultMode)
        sources.forEach { CFRunLoopRemoveSource(loop, $0, .defaultMode) }
        installedTaps.forEach { CFMachPortInvalidate($0) }
        lock.lock()
        taps.removeAll()
        runLoop = nil
        cancelled = true
        lock.unlock()
        onFinished()
    }

    private func filter(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        lock.lock()
        let isCancelled = cancelled
        lock.unlock()
        guard !isCancelled else { return Unmanaged.passUnretained(event) }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            finish(.tapDisabled)
            return Unmanaged.passUnretained(event)
        }
        let isKey = type == .keyDown || type == .keyUp
        let code = isKey ? event.getIntegerValueField(.keyboardEventKeycode) : -1
        // After visual exit, swallow only the exit key until its release.
        // This avoids delivering a stray Esc/Q key-up or repeat to another app.
        if let releaseKey {
            guard isKey, code == releaseKey else { return Unmanaged.passUnretained(event) }
            if type == .keyUp { stop() }
            return nil
        }
        if let decision = exitKeys.handle(type: type, event: event,
                                          now: ProcessInfo.processInfo.systemUptime) {
            finish(decision.reason, draining: decision.releaseKey)
        }
        return nil
    }

    private func checkHealth() {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        let isCancelled = cancelled
        let lastHeartbeat = heartbeat
        let currentTaps = taps
        lock.unlock()
        guard !isCancelled else { return }
        if !AXIsProcessTrusted() { finish(.permissionLost); return }
        if IsSecureEventInputEnabled() { finish(.secureInput); return }
        guard currentTaps.count == 2, currentTaps.allSatisfy({ CGEvent.tapIsEnabled(tap: $0) }) else {
            finish(.tapDisabled)
            return
        }
        if let releaseDeadline {
            if now >= releaseDeadline { stop() }
            return
        }
        if CleaningSessionPolicy.isInterfaceUnresponsive(lastHeartbeat: lastHeartbeat, now: now) {
            finish(.interfaceUnresponsive)
        } else if CleaningSessionPolicy.shouldExpire(startedAt: startedAt, now: now) {
            finish(.safetyDeadline)
        }
    }

    private func finish(_ reason: CleaningExitReason, draining key: Int64? = nil) {
        guard !exitReported else { stop(); return }
        exitReported = true
        if let key, !locallyReleasedExitKeys.contains(key) {
            releaseKey = key
            releaseDeadline = ProcessInfo.processInfo.systemUptime + CleaningSessionPolicy.releaseGrace
        } else {
            stop()
        }
        onExit(reason)
        armRecoveryFallback()
    }

    private func armRecoveryFallback() {
        // onExit queues the AppKit cleanup first. This acknowledgment runs behind it.
        // Keep the independent fallback alive even after the event thread ends.
        DispatchQueue.main.async { [self] in
            lock.lock()
            recoveryAcknowledged = true
            lock.unlock()
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2) { [self] in
            lock.lock()
            let recovered = recoveryAcknowledged
            lock.unlock()
            if !recovered {
                // No user document state exists. Process death lets WindowServer
                // remove owned windows/presentation instead of leaving a stuck overlay.
                Darwin._exit(EXIT_FAILURE)
            }
        }
    }
}

/// Both CGEventTap and the AppKit fallback use the same exit-event decoding.
/// Tests construct CGEvents in memory; nothing is posted to the event stream.
nonisolated struct ExitKeyTracker {
    private var presses = EscapePressTracker()

    mutating func handle(type: CGEventType, event: CGEvent, now: TimeInterval)
        -> (reason: CleaningExitReason, releaseKey: Int64?)? {
        if type == .flagsChanged {
            reset()
            return nil
        }
        guard type == .keyDown || type == .keyUp else { return nil }
        return handle(keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                      isDown: type == .keyDown,
                      isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                      modifiers: event.flags, now: now)
    }

    mutating func handle(keyCode: Int64, isDown: Bool, isRepeat: Bool,
                         modifiers: CGEventFlags, now: TimeInterval)
        -> (reason: CleaningExitReason, releaseKey: Int64?)? {
        if keyCode == 53 {
            if isDown {
                presses.keyDown(isRepeat: isRepeat, now: now)
            } else if presses.keyUp(now: now) {
                return (.escape, nil)
            }
        } else if isDown {
            presses.reset()
        }
        let backupFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        if isDown, !isRepeat, keyCode == 12, modifiers.contains(backupFlags) {
            return (.backupShortcut, 12)
        }
        return nil
    }

    mutating func reset() { presses.reset() }
}

nonisolated enum InputTapRequirements {
    static func permitsKeyboard(entries: [CGEventTapInformation], processID: pid_t,
                                requiredMask: CGEventMask) -> Bool {
        entries.contains {
            $0.tappingProcess == processID && $0.tapPoint == .cgSessionEventTap &&
            $0.enabled && ($0.eventsOfInterest & requiredMask) == requiredMask
        }
    }
}
