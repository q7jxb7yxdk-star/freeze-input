import Foundation
import CoreGraphics
import Darwin

/// Background safety supervision only. No global event taps or input permissions.
nonisolated final class SessionWatchdog: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "Freeze Input Session Safety", qos: .userInitiated)
    private let timer: DispatchSourceTimer
    private let startedAt: TimeInterval
    private var heartbeat: TimeInterval
    private var cancelled = false
    private var recoveryRequested = false
    private let onExit: @Sendable (CleaningExitReason) -> Void

    init(onExit: @escaping @Sendable (CleaningExitReason) -> Void) {
        let now = ProcessInfo.processInfo.systemUptime
        startedAt = now
        heartbeat = now
        self.onExit = onExit
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.checkHealth() }
        timer.resume()
    }

    func pulse() {
        lock.lock()
        if !cancelled { heartbeat = ProcessInfo.processInfo.systemUptime }
        lock.unlock()
    }

    /// Call only after the main actor has removed the overlay and restored presentation.
    func stop() {
        lock.lock()
        cancelled = true
        lock.unlock()
        timer.cancel()
    }

    private func checkHealth() {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard !cancelled, !recoveryRequested else { lock.unlock(); return }
        let reason: CleaningExitReason
        if CleaningSessionPolicy.shouldExpire(startedAt: startedAt, now: now) {
            reason = .safetyDeadline
        } else if CleaningSessionPolicy.isInterfaceUnresponsive(lastHeartbeat: heartbeat, now: now) {
            reason = .interfaceUnresponsive
        } else {
            lock.unlock()
            return
        }
        recoveryRequested = true
        lock.unlock()

        // The controller queues AppKit cleanup on the main actor. stop() acknowledges
        // completed cleanup; a heartbeat alone must never acknowledge recovery.
        onExit(reason)
        queue.asyncAfter(deadline: .now() + 2) { [self] in
            lock.lock()
            if !cancelled {
                // If the main actor remains blocked, process death removes its windows.
                // No document state exists. Cursor/presentation recovery needs hardware QA.
                // Keep cancellation serialized through termination so an old watchdog
                // cannot exit after stop() has completed and a new session has started.
                Darwin._exit(EXIT_FAILURE)
            }
            lock.unlock()
        }
    }

    deinit { timer.cancel() }
}

/// Decodes metadata from events delivered to this app, without storing typed text.
nonisolated struct ExitKeyTracker {
    private var presses = EscapePressTracker()
    private var backupStartedAt: TimeInterval?
    var isWaitingForBackupRelease: Bool { backupStartedAt != nil }

    mutating func modifiersChanged() { presses.reset() }

    mutating func handle(keyCode: Int64, isDown: Bool, isRepeat: Bool,
                         modifiers: CGEventFlags, now: TimeInterval) -> CleaningExitReason? {
        if backupStartedAt != nil {
            guard keyCode == 12, !isDown else { return nil }
            backupStartedAt = nil
            return .backupShortcut
        }
        if keyCode == 53 {
            if isDown {
                presses.keyDown(isRepeat: isRepeat, now: now)
            } else if presses.keyUp(now: now) {
                return .escape
            }
        } else if isDown {
            presses.reset()
        }
        let backupFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        if isDown, !isRepeat, keyCode == 12, modifiers.contains(backupFlags) {
            // Keep the overlay until Q is released; there is no global tail filter.
            backupStartedAt = now
        }
        return nil
    }

    func releaseWaitExpired(now: TimeInterval) -> Bool {
        guard let backupStartedAt else { return false }
        return now - backupStartedAt >= CleaningSessionPolicy.releaseGrace
    }
}
