# Freeze Input — Technical Documentation

This document describes the sandbox foreground-overlay implementation as of 2026-10-17. The [README](README.md) provides setup and usage; [PRIVACY_POLICY.md](PRIVACY_POLICY.md) describes user-facing information handling.

## Evidence boundary

Source implementation, test coverage, and runtime verification are separate. The current changes are limited to source/configuration inspection, syntax/property-list checks, and diff review. The agent did not perform Build/Test, standalone logic-check execution, app launch, signing, Archive, or hardware validation for these changes. Earlier successful checks of the non-sandboxed version do not establish that this version builds or runs correctly.

The user reported successful Esc exit and an alert sound for the thumb-and-three-finger pinch while the overlay remained active. In a user-run comparison, removing `disableProcessSwitching` removed that sound but allowed a screen switch that stopped cleaning; the option is restored. These are scoped user observations, not a complete runtime test report.

App Sandbox is declared in Debug and Release with only the sandbox entitlement. The final signed executable's entitlements, behavior on a clean Mac, and App Store acceptance remain externally unverified.

## Architecture and ownership

The app uses SwiftUI for its control window and AppKit for foreground black overlays and local event handling. There is no Accessibility permission gate, Input Monitoring request, global event tap, privileged helper, or systemwide event suppression.

| Component under `Freeze Input/` | Responsibility |
| --- | --- |
| `MyApp.swift` | Composes the app and shared controller; supplies standard About panel links; performs shutdown on normal termination |
| `ContentView.swift` | Presents instructions, start availability, and session status |
| `CleaningController.swift` | Owns main-actor session state, lifecycle observers, timers, exit tracking, windows, and current watchdog |
| `BlackoutWindows.swift` | Owns black windows, the local event monitor, cursor hide accounting, and saved presentation options |
| `InputInterceptor.swift` | Contains `SessionWatchdog` and scalar exit-key decoding, without tap creation or Accessibility APIs |
| `EscapePressTracker.swift` | Pure Esc-sequence tracking, user-facing exit reasons, and timing policy |
| `Tests/LogicChecks.swift` | Standalone scalar-key and timing assertions; outside the app's synchronized source group |
| `PrivacyInfo.xcprivacy` | Privacy declarations and the approved local timing reason |

AppKit objects and session transitions remain on the main actor. A background DispatchSource timer monitors the session independently of the main run loop. Its shared heartbeat/cancellation state requires synchronization; background work requests main-thread cleanup rather than manipulating windows directly.

The app target uses a file-system-synchronized source group. Empty explicit Sources/Resources lists do not imply inactive source. There is one macOS app target, no XCTest/Swift Testing target, and no checked-in shared scheme or CI configuration.

## Session lifecycle

### Startup

Startup rejects an already-busy session and requires the app to be active. It captures a display signature, creates the watchdog and common-mode safety timer, then queues overlay installation on the main queue after the Start button event. There is no semaphore or synchronous two-second readiness wait.

The controller installs the local event monitor and black windows, hides the cursor, saves presentation state, and requests keyboard focus with `makeKeyAndOrderFront`. The common-mode timer checks for a visible key window whose content view is first responder, for up to 0.5 seconds. It retries focus without blocking the main thread and marks cleaning active only when ready. Failure cleans up and provides a specific retry message. Session and presentation UUIDs prevent cancelled startup work from recreating an overlay or overwriting its cancellation reason. The watchdog remains active throughout startup.

The previous source-only visible inspection mode is removed: a local monitor with no overlay cannot provide the foreground coverage described by the product. No permission request or live global tap is used as a startup prerequisite.

### Local input handling

The local monitor consumes supported keyboard, modifier, mouse button, mouse movement/drag, scroll, and gesture events that macOS sends to this app. Returning `nil` prevents normal dispatch within this app; it does not stop events routed to macOS or another application. Black windows cover enumerated screens, and a key-capable window receives keyboard input.

The implementation examines only event metadata needed for exit recognition: event direction, virtual key code, modifier flags, repeat status, and timing. It does not convert key events into typed text, post/replay events, or keep input history.

Cursor hiding is presentation only. The actual pointer can move, system gestures and reserved shortcuts can still act, and AppKit's monitor does not cover every nested event-tracking loop. Presentation options hide the Dock/menu bar and disable process-switching UI; a restricted system action may still produce an alert sound. There is no per-gesture sound suppression. The app stops when it loses foreground status. Overlay alpha is currently `1`, with no UI transparency setting.

### Esc exit

`EscapePressTracker` counts five complete press/release pairs within three seconds from the first accepted key-down. Exit occurs on the fifth release. The exact three-second boundary is accepted; a later event expires the sequence. Orphan/duplicate releases, repeated key-downs, and holding Esc do not count as additional presses. Another key-down or modifier change resets the sequence.

### Backup exit and release grace

Control + Option + Command + Q uses virtual key code 12. A qualifying non-repeat Q key-down arms backup exit; the overlay remains until the matching Q release. This avoids intentionally closing the overlay while Q is still repeating. A ten-second grace bounds a missing release, and the 180-second session maximum takes priority.

This is local release handling, not a global tail filter. If the app loses foreground status or a deadline forces cleanup while a key is held, later repeat/release events may reach macOS or another app. No guarantee of post-cleanup suppression is made.

### Display-change handling

At session start, the controller records each screen's ID, full frame, and backing scale factor, sorted by ID. A display-parameters notification ends the session only if this signature differs or cannot be read. Enumeration-order differences and changes limited to `visibleFrame` do not cancel cleaning. The full frame is used because Dock/menu presentation can change the usable area without changing overlay coverage. The queued startup also rechecks the signature before creating windows. The signature is cleared before cleanup so restoration notifications cannot act on an ended session.

### Safety and cleanup

A main-run-loop heartbeat and background watchdog enforce layered recovery. The background timer checks the 180-second session maximum and a three-second heartbeat tolerance. On a failure it first requests cleanup on the main queue. If cleanup is not acknowledged within two seconds, emergency `_exit(EXIT_FAILURE)` ends the process so WindowServer can remove its windows and presentation ownership.

Normal stop cancels the current watchdog/session. Session identity and cancellation prevent delayed work from an old session from terminating a newer session. Cleanup acknowledgment must follow actual cleanup, not merely queue submission. The watchdog never calls AppKit from its background queue.

Cleanup removes the local monitor, closes owned windows, balances cursor hiding, restores saved presentation options, clears session state, and permits a new manual start. Sleep/session changes, display changes, foreground loss, normal shutdown, Esc, backup release, and safety expiry do not automatically resume cleaning.

These timers are scheduling policies, not hard real-time recovery guarantees. A fully stalled process cannot execute its own timers. Emergency termination deliberately skips normal AppKit cleanup, so cursor and presentation restoration require physical verification.

## Configuration

| Setting | Current declaration |
| --- | --- |
| App target | `Freeze Input`, output `Freeze Input.app` |
| Platform | macOS only; Catalyst disabled |
| Deployment target | macOS 14.0 |
| Identity | `com.sunny.freeze-input`; marketing version 1.1.1; build 20261017 |
| Configurations | Debug and Release; configuration-list default Release |
| Sandbox | Enabled in both configurations; only `com.apple.security.app-sandbox = true` is needed |
| File access | No user-selected-file entitlement is needed; no user-document workflow exists |
| Signing | Automatic signing with a preconfigured development team; no signing material is stored in this documentation |
| Swift | Language mode 5.0, approachable concurrency, default MainActor isolation |
| Project format | 90 with a synchronized app source group; no pinned Xcode/compiler version |
| Schemes | User-specific metadata exists; no shared `.xcscheme` is checked in |

Unused non-macOS deployment and interface-orientation settings do not create mobile support. Legacy `MyApp` product metadata does not identify a second app target. SDK/type compatibility and signed entitlement generation must be checked in a fresh manual Build/Run.

## Security and privacy

There is no backend, network request, persistent input storage, database, account, advertising, analytics, tracking SDK, or third-party dependency. App state remains in memory and an active session is not restored after restart. No root privileges, kernel extension, private API, arbitrary Apple Event control, or SIP modification is required.

This version does not request or depend on Accessibility or Input Monitoring permission. Old grants from a previous installation are not required and may be removed manually in System Settings. Opening the About panel's privacy/support links launches an external website; GitHub handles that interaction under its own policy. The app itself does not send input events to GitHub.

`PrivacyInfo.xcprivacy` declares `NSPrivacyTracking = false`, an empty tracking-domain list, and an empty collected-data-type list. `NSPrivacyAccessedAPITypes` declares `NSPrivacyAccessedAPICategorySystemBootTime` with reason `35F9.1`. The app uses `ProcessInfo.processInfo.systemUptime` for elapsed-time calculations, heartbeat checks, focus and exit-release deadlines, and the cleaning-session maximum. It does not transmit that timing information or use it for fingerprinting.

The file resides inside the target's synchronized source group. Xcode is expected to copy it into `Freeze Input.app/Contents/Resources/PrivacyInfo.xcprivacy`; this has not been verified by a new Build or Archive. Validate the final bundle location and Xcode privacy report manually. A valid source plist does not establish successful resource processing or server acceptance.

The sandbox configuration narrows resource access but is not evidence of a complete security audit, final distribution signing, or App Store approval. Final App Store Connect privacy answers must be checked against the complete submitted product; the manifest does not fill those answers automatically. The [Apple API reason list](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) and [manifest packaging guidance](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk) describe the declarations and bundle placement.

## Testing and validation

The standalone `Tests/LogicChecks.swift` executable uses `precondition` assertions for scalar exit-key decisions, Esc edge cases, and pure timing policies. It does not construct a real cleaning session or install a local/global monitor. Do not disable assertions when running it. The manual command is documented in the [README](README.md#development-and-validation).

The sandbox change did not execute those checks or any Build/Test. Syntax parsing cannot establish framework type compatibility; property-list validation cannot prove signed entitlements. There is no automated UI, controller/window-lifecycle, watchdog-race, emergency-exit, or physical event coverage.

### Manual runtime validation

The following remains a manual checklist; the scoped user observations above do not mark these items as passed:

- Build Debug and Release, inspect the signed App Sandbox entitlement, and run with no old Accessibility/Input Monitoring grants on a clean user account or Mac.
- Confirm the final built app contains a valid manifest at `Contents/Resources/PrivacyInfo.xcprivacy`, includes the local timing declaration, and produces an accurate Xcode privacy report.
- Verify start/stop and all failure paths leave no residual monitor, window, hidden cursor, or presentation setting.
- Verify focus-readiness success and timeout keep the UI responsive, preserve lifecycle cancellation messages, and never leave an unusable overlay.
- Verify hiding/restoring Dock/menu presentation does not falsely end cleaning, while actual screen ID/frame/scale changes still stop the session.
- Test internal/external keyboards, mouse buttons, movement, drags, scrolling, trackpad gestures, and pressure input where available. Distinguish local event consumption from actual systemwide suppression.
- Test one through five Esc presses, the exact sequence boundary, timeout, long hold, repeats, other-key/modifier resets, and no unintended Esc action after normal exit.
- Test the backup chord, Q release, long-held Q, missing-release grace, modifiers released in different orders, the three-minute deadline taking priority, and starting another session.
- Test black coverage on multiple/scaled/mirrored displays, notches, Spaces, existing full-screen apps, and display hot-plug.
- Test Mission Control, Spaces, Show Desktop, reserved shortcuts, Touch ID, power/media/brightness keys, and document system bypasses rather than treating them as blocked.
- Test deactivation, sleep/wake, lid close/open, lock/user switch, normal Quit, and Force Quit; verify no automatic session resumption.
- Test UI-only stalls, cleanup that cannot execute, independent watchdog deadlines, normal cancellation, and a quick new session after stop. Pausing all threads does not test independent watchdog behavior.
- Verify emergency process exit removes overlays and restores a usable cursor/presentation state.
- Test the minimum supported macOS and current macOS on supported Intel and Apple silicon hardware.
- Verify **Freeze Input → About Freeze Input** shows version/build and opens publicly accessible privacy/support destinations.

## Remaining development work

The following are recommendations, not implemented guarantees: add lifecycle/watchdog regression coverage, establish a shared scheme and CI/toolchain policy, document a distribution/signing process, and define a project license. A global input-lock feature would require a separate feasibility and distribution decision; it is not supplied by this foreground-overlay design.
