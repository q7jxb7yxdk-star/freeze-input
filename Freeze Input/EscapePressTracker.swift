import Foundation

/// Counts complete Esc press/release pairs using caller-supplied monotonic time.
/// No key content is retained. Repeats and orphan/duplicate releases do not count.
nonisolated struct EscapePressTracker {
    static let requiredPresses = 5
    static let sequenceDuration: TimeInterval = 3
    private(set) var completedPresses = 0
    private var sequenceStartedAt: TimeInterval?
    private var isPressed = false

    mutating func keyDown(isRepeat: Bool, now: TimeInterval) {
        expireIfNeeded(now: now)
        guard !isRepeat, !isPressed else { return }
        if sequenceStartedAt == nil { sequenceStartedAt = now }
        isPressed = true
    }

    /// Exit only on the fifth release, so no Esc release needs draining afterward.
    mutating func keyUp(now: TimeInterval) -> Bool {
        expireIfNeeded(now: now)
        guard isPressed, sequenceStartedAt != nil else { return false }
        isPressed = false
        completedPresses += 1
        guard completedPresses == Self.requiredPresses else { return false }
        reset()
        return true
    }

    mutating func reset() {
        completedPresses = 0
        sequenceStartedAt = nil
        isPressed = false
    }

    private mutating func expireIfNeeded(now: TimeInterval) {
        if let sequenceStartedAt, now - sequenceStartedAt > Self.sequenceDuration {
            reset()
        }
    }
}

nonisolated enum CleaningExitReason: String, Sendable {
    case escape = "Cleaning finished."
    case backupShortcut = "Cleaning stopped with the backup shortcut."
    case safetyDeadline = "Cleaning stopped after the three-minute safety limit."
    case tapDisabled = "Input interception stopped unexpectedly. Cleaning has been cancelled."
    case permissionLost = "Accessibility permission was removed. Cleaning has been cancelled."
    case secureInput = "Secure Event Input is active. Close password entry or the app using secure input, then try again."
    case interfaceUnresponsive = "The interface stopped responding. Input interception has been released."
    case sleep = "Cleaning stopped because the Mac went to sleep or the session became inactive."
    case foregroundLost = "Cleaning stopped because Freeze Input left the foreground."
    case displayChanged = "Cleaning stopped because the display configuration changed."
    case stopped = "Cleaning stopped."
}

nonisolated struct CleaningSessionPolicy {
    static let maximumDuration: TimeInterval = 180
    static let heartbeatTolerance: TimeInterval = 3
    static let releaseGrace: TimeInterval = 10

    static func shouldExpire(startedAt: TimeInterval, now: TimeInterval) -> Bool {
        now - startedAt >= maximumDuration
    }

    static func isInterfaceUnresponsive(lastHeartbeat: TimeInterval, now: TimeInterval) -> Bool {
        now - lastHeartbeat >= heartbeatTolerance
    }
}
