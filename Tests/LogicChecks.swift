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
        checkEventDecoding()
        checkTapValidation()
        print("PASS: Esc five-press sequence/reset, CGEvent exit decoding, backup modifiers, effective keyboard tap validation, safety/heartbeat boundaries")
    }

    static func key(_ code: CGKeyCode, down: Bool, repeatEvent: Bool = false,
                    flags: CGEventFlags = []) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatEvent ? 1 : 0)
        return event
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

    static func checkEventDecoding() {
        var keys = ExitKeyTracker()
        // First four CGEvent press/release pairs do not exit.
        for index in 0..<4 {
            let down = 10 + Double(index) * 0.4
            precondition(keys.handle(type: .keyDown, event: key(53, down: true), now: down) == nil)
            precondition(keys.handle(type: .keyDown, event: key(53, down: true, repeatEvent: true), now: down + 0.05) == nil)
            precondition(keys.handle(type: .keyUp, event: key(53, down: false), now: down + 0.1) == nil)
        }
        precondition(keys.handle(type: .keyDown, event: key(53, down: true), now: 12) == nil)
        let released = keys.handle(type: .keyUp, event: key(53, down: false), now: 12.1)
        precondition(released?.reason == .escape && released?.releaseKey == nil)
        precondition(keys.handle(type: .keyUp, event: key(53, down: false), now: 12.2) == nil)
        // Another key or a modifier change breaks an otherwise near-complete sequence.
        for useModifier in [false, true] {
            for index in 0..<4 {
                let down = 20 + Double(index) * 0.4
                precondition(keys.handle(type: .keyDown, event: key(53, down: true), now: down) == nil)
                precondition(keys.handle(type: .keyUp, event: key(53, down: false), now: down + 0.1) == nil)
            }
            let type: CGEventType = useModifier ? .flagsChanged : .keyDown
            precondition(keys.handle(type: type, event: key(0, down: true), now: 21.8) == nil)
            precondition(keys.handle(type: .keyDown, event: key(53, down: true), now: 22) == nil)
            precondition(keys.handle(type: .keyUp, event: key(53, down: false), now: 22.1) == nil)
            keys.reset()
        }
        let all: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        for missing in [CGEventFlags.maskControl, .maskAlternate, .maskCommand] {
            precondition(keys.handle(type: .keyDown, event: key(12, down: true, flags: all.subtracting(missing)), now: 41) == nil)
        }
        precondition(keys.handle(type: .keyDown, event: key(12, down: true, repeatEvent: true, flags: all), now: 41) == nil)
        precondition(keys.handle(type: .keyUp, event: key(12, down: false, flags: all), now: 41) == nil)
        precondition(keys.handle(type: .keyDown, event: key(13, down: true, flags: all), now: 41) == nil)
        let backup = keys.handle(type: .keyDown, event: key(12, down: true, flags: all), now: 42)
        precondition(backup?.reason == .backupShortcut && backup?.releaseKey == 12)
        // The AppKit fallback's scalar path must reach the same decision.
        var local = ExitKeyTracker()
        for index in 0..<5 {
            let down = 100 + Double(index) * 0.4
            precondition(local.handle(keyCode: 53, isDown: true, isRepeat: false, modifiers: [], now: down) == nil)
            let decision = local.handle(keyCode: 53, isDown: false, isRepeat: false, modifiers: [], now: down + 0.1)
            if index < 4 { precondition(decision == nil) }
            else { precondition(decision?.reason == .escape && decision?.releaseKey == nil) }
        }
        precondition(local.handle(keyCode: 12, isDown: true, isRepeat: false, modifiers: all, now: 103)?.reason == .backupShortcut)
    }

    static func checkTapValidation() {
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        var tap = CGEventTapInformation()
        tap.tappingProcess = 123
        tap.tapPoint = .cgSessionEventTap
        tap.enabled = true
        tap.eventsOfInterest = mask
        func allowed(_ entries: [CGEventTapInformation]) -> Bool {
            InputTapRequirements.permitsKeyboard(entries: entries, processID: 123, requiredMask: mask)
        }
        precondition(allowed([tap]))
        precondition(!allowed([]))
        tap.eventsOfInterest = CGEventMask(1) << CGEventType.keyDown.rawValue
        precondition(!allowed([tap]), "Key-down without key-up must not allow black screen")
        tap.eventsOfInterest = CGEventMask(1) << CGEventType.mouseMoved.rawValue
        precondition(!allowed([tap]), "A mouse-only tap must not allow black screen")
        tap.eventsOfInterest = mask
        tap.enabled = false
        precondition(!allowed([tap]))
        tap.enabled = true
        tap.tappingProcess = 124
        precondition(!allowed([tap]), "Another process's keyboard tap must not count")
        tap.tappingProcess = 123
        tap.tapPoint = .cgAnnotatedSessionEventTap
        precondition(!allowed([tap]))
    }
}
