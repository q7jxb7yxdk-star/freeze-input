import Foundation
import CoreGraphics

@main
struct LogicChecks {
    static func main() {
        checkPressSequence()
        precondition(!CleaningSessionPolicy.shouldExpire(startedAt: 100, now: 279.999))
        precondition(CleaningSessionPolicy.shouldExpire(startedAt: 100, now: 280))
        precondition(!CleaningSessionPolicy.isInterfaceUnresponsive(lastHeartbeat: 100, now: 102.999))
        precondition(CleaningSessionPolicy.isInterfaceUnresponsive(lastHeartbeat: 100, now: 103))
        checkLocalExitKeys()
        print("PASS: Esc sequence/reset, local backup release/grace, safety/heartbeat boundaries")
    }

    static func checkPressSequence() {
        var presses = EscapePressTracker()
        precondition(!presses.keyUp(now: 0), "An orphan release must not count")
        presses.keyDown(isRepeat: true, now: 0)
        precondition(!presses.keyUp(now: 0.1), "An orphan repeat must not arm")
        for index in 0..<5 {
            let down = Double(index) * 0.6
            presses.keyDown(isRepeat: false, now: down)
            presses.keyDown(isRepeat: false, now: down + 0.01)
            presses.keyDown(isRepeat: true, now: down + 0.02)
            let up = index == 4 ? 3.0 : down + 0.1
            precondition(presses.keyUp(now: up) == (index == 4), "Only the fifth complete press exits, including the exact 3-second boundary")
            precondition(!presses.keyUp(now: up), "Duplicate releases must not count")
        }
        precondition(presses.completedPresses == 0, "Successful exit resets sequence state")
        for index in 0..<4 {
            let down = 10 + Double(index) * 0.5
            presses.keyDown(isRepeat: false, now: down)
            precondition(!presses.keyUp(now: down + 0.1))
        }
        presses.keyDown(isRepeat: false, now: 12.9)
        precondition(!presses.keyUp(now: 13.001), "The fifth release after the deadline must not exit")
        precondition(presses.completedPresses == 0)
        presses.keyDown(isRepeat: false, now: 20)
        for index in 1...5 { presses.keyDown(isRepeat: true, now: 20 + Double(index) * 0.1) }
        precondition(!presses.keyUp(now: 20.6), "Holding Esc is one press, not five")
        precondition(presses.completedPresses == 1)
        presses.reset()
        precondition(presses.completedPresses == 0)
        presses.keyDown(isRepeat: false, now: 30)
        precondition(!presses.keyUp(now: 33.001), "A long hold cannot exit")
    }

    static func checkLocalExitKeys() {
        var keys = ExitKeyTracker()
        for index in 0..<5 {
            let down = 10 + Double(index) * 0.4
            precondition(keys.handle(keyCode: 53, isDown: true, isRepeat: false,
                                     modifiers: [], now: down) == nil)
            precondition(keys.handle(keyCode: 53, isDown: true, isRepeat: true,
                                     modifiers: [], now: down + 0.05) == nil)
            let reason = keys.handle(keyCode: 53, isDown: false, isRepeat: false,
                                     modifiers: [], now: down + 0.1)
            precondition(reason == (index == 4 ? .escape : nil))
        }
        // Another key or modifier change must interrupt a near-complete Esc sequence.
        for useModifier in [false, true] {
            keys = ExitKeyTracker()
            for index in 0..<4 {
                let down = 20 + Double(index) * 0.4
                precondition(keys.handle(keyCode: 53, isDown: true, isRepeat: false,
                                         modifiers: [], now: down) == nil)
                precondition(keys.handle(keyCode: 53, isDown: false, isRepeat: false,
                                         modifiers: [], now: down + 0.1) == nil)
            }
            if useModifier {
                keys.modifiersChanged()
            } else {
                precondition(keys.handle(keyCode: 0, isDown: true, isRepeat: false,
                                         modifiers: [], now: 21.8) == nil)
            }
            precondition(keys.handle(keyCode: 53, isDown: true, isRepeat: false,
                                     modifiers: [], now: 22) == nil)
            precondition(keys.handle(keyCode: 53, isDown: false, isRepeat: false,
                                     modifiers: [], now: 22.1) == nil)
        }
        keys = ExitKeyTracker()
        let all: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        for missing in [CGEventFlags.maskControl, .maskAlternate, .maskCommand] {
            precondition(keys.handle(keyCode: 12, isDown: true, isRepeat: false,
                                     modifiers: all.subtracting(missing), now: 40) == nil)
            precondition(!keys.isWaitingForBackupRelease)
        }
        precondition(keys.handle(keyCode: 12, isDown: true, isRepeat: true,
                                 modifiers: all, now: 40) == nil)
        precondition(!keys.isWaitingForBackupRelease)
        precondition(keys.handle(keyCode: 12, isDown: false, isRepeat: false,
                                 modifiers: all, now: 40) == nil, "Orphan Q release must not exit")
        precondition(keys.handle(keyCode: 13, isDown: true, isRepeat: false,
                                 modifiers: all, now: 40) == nil)
        precondition(!keys.isWaitingForBackupRelease)
        precondition(keys.handle(keyCode: 12, isDown: true, isRepeat: false,
                                 modifiers: all, now: 42) == nil, "Q down must keep the overlay")
        precondition(keys.isWaitingForBackupRelease)
        precondition(keys.handle(keyCode: 12, isDown: true, isRepeat: true,
                                 modifiers: all, now: 43) == nil)
        precondition(!keys.releaseWaitExpired(now: 51.999))
        precondition(keys.releaseWaitExpired(now: 52), "Grace includes repeats and is bounded")
        keys.modifiersChanged()
        precondition(keys.handle(keyCode: 12, isDown: false, isRepeat: false,
                                 modifiers: [], now: 45) == .backupShortcut,
                     "Q release exits even if modifiers were released first")
        precondition(!keys.isWaitingForBackupRelease)
        precondition(!keys.releaseWaitExpired(now: 100))
        precondition(keys.handle(keyCode: 12, isDown: false, isRepeat: false,
                                 modifiers: [], now: 46) == nil, "Duplicate Q release must not exit")
    }
}
