# Freeze Input

Freeze Input is a native macOS app that reduces accidental input while you clean your screen, keyboard, or trackpad. It shows black windows on connected screens and consumes supported keyboard, pointer, scroll, and gesture events delivered to those foreground windows. It does not disable hardware or filter input systemwide.

## Implementation and evidence status

- **Implemented:** App Sandbox configuration, foreground black overlays, local AppKit event filtering, deliberate keyboard exits, nonblocking startup, lifecycle cleanup, independent safety monitoring, and a privacy manifest.
- **Test-covered:** Standalone assertions cover Esc sequences, scalar exit-key decisions, and safety time boundaries. Test source is not evidence of a passing execution.
- **Validation boundary for the current changes (2026-10-17):** Source, property-list, syntax, and diff checks only. The agent did not perform Build/Test, standalone check execution, signing, Archive, or runtime validation for these changes. Earlier checks of the non-sandboxed implementation do not validate this version.
- **User-reported observations:** Esc exited a cleaning session normally. Pinching the thumb and three fingers produced a system alert sound while the overlay remained active. Temporarily removing the process-switching restriction removed the sound but allowed a screen switch that stopped cleaning; the restriction was restored. These observations do not validate every gesture, device, or OS version.
- **Externally unverified:** Actual sandbox entitlements in a signed build, input delivery, all display/Spaces configurations, cursor restoration, emergency termination, and App Store submission or approval.

## Features and limits

- Starts a foreground cleaning session without requesting Accessibility or Input Monitoring permission.
- Covers connected screens with black windows, hides the cursor, and changes Dock/menu presentation during cleaning. The hidden pointer may still move within macOS.
- Consumes supported events sent to this app through a local AppKit monitor. Events handled by macOS or sent to another app are outside its scope.
- Exits on the fifth complete Esc press/release within three seconds.
- Supports Control + Option + Command + Q as a backup exit. The overlay stays until Q is released, or a ten-second release grace expires; the three-minute session deadline takes priority.
- Automatically stops after three minutes or when the app loses the foreground, the Mac sleeps/session changes, or the display configuration changes. Sessions do not resume automatically.
- Uses a background watchdog to request cleanup if the UI heartbeat stops. If main-thread cleanup cannot be acknowledged, an emergency process exit limits exposure to a stuck overlay.
- Provides **Privacy Policy** and **Support / Contact** links in **Freeze Input → About Freeze Input**.

Mission Control, Spaces, Show Desktop, reserved shortcuts, Touch ID, power/media/brightness keys, and system gestures may continue to work or produce a system alert sound when restricted. This is a foreground cleaning cover, not a global input lock. Do not rely on it as a security or access-control feature.

## Requirements and setup

| Item | Current declaration |
| --- | --- |
| Platform | macOS only; Mac Catalyst disabled |
| Minimum OS | macOS 14.0 |
| Swift | Swift language mode 5.0; no pinned compiler version |
| Project | `Freeze Input.xcodeproj`, project format 90, file-system-synchronized app source group |
| Configurations | Debug and Release |
| App identity | `com.sunny.freeze-input`; version 1.1.1; build 20261017 |
| Sandbox | Enabled in Debug and Release; only the App Sandbox entitlement is needed |
| Dependencies | Apple SDK frameworks only; no third-party dependency installation |
| Signing | Automatic signing with a configured development team; review it for your account |

Open the project in a compatible Xcode installation, select the **Freeze Input** app target and local Mac destination, and Build/Run manually. There is no iOS/iPadOS target or Simulator workflow. User-specific scheme metadata exists, but no shared `.xcscheme`, pinned toolchain, or CI pipeline is checked in.

No API keys, backend, account, environment variables, or permission setup is required for normal app operation. Existing Accessibility grants from older versions are not used by this version and may be removed manually in System Settings. Do not grant extra permissions to resolve a startup error; follow the displayed retry instructions instead.

## Usage

1. Read the exit instructions before choosing **Start Cleaning** while the app is in the foreground.
2. Press and release **Esc five times within three seconds**, or hold **Control + Option + Command**, press **Q**, then release **Q**.
3. Otherwise, wait for the **three-minute automatic exit**.

Esc repeats and long holds do not count as multiple presses. Another key-down or modifier change resets the Esc sequence. A held key may produce ordinary events after a release-grace timeout, a safety deadline, or loss of foreground; this app cannot drain keys globally after its overlay closes.

## Project structure

| Path | Responsibility |
| --- | --- |
| `Freeze Input/MyApp.swift` | App entry point, About links, and termination delegate |
| `Freeze Input/ContentView.swift` | Instructions, start control, and status |
| `Freeze Input/CleaningController.swift` | Main-actor session coordination, local exits, and lifecycle cleanup |
| `Freeze Input/BlackoutWindows.swift` | Black windows, local event monitor, cursor and presentation ownership |
| `Freeze Input/InputInterceptor.swift` | Background `SessionWatchdog` and scalar exit-key logic; no global event tap |
| `Freeze Input/EscapePressTracker.swift` | Esc sequence, exit reasons, and timing policy |
| `Freeze Input/Assets.xcassets/` | App icons and accent color |
| `Tests/LogicChecks.swift` | Standalone assertions; not an Xcode test target |
| `Freeze Input/PrivacyInfo.xcprivacy` | No-tracking/no-collection declarations and local timing API reason |
| `PRIVACY_POLICY.md` | Public-facing privacy policy |
| `APP_STORE_METADATA.md` | English macOS product-page copy, review notes, and internal submission checklist |

## Startup and privacy declarations

Startup is scheduled on the main queue after the Start button event completes. A common-mode timer checks keyboard focus for up to 0.5 seconds without blocking the main thread; there is no two-second semaphore wait. Failure cancels the overlay and reports an actionable message. The background safety watchdog remains active during startup.

Display-change notifications are compared against the session's screen IDs, full frames, and backing scale factors. Notifications with the same configuration do not end a session. `visibleFrame`, which changes with Dock/menu presentation, is not used as the layout signature. Unreadable or genuinely changed configurations still cancel cleaning.

`Freeze Input/PrivacyInfo.xcprivacy` declares no tracking, no tracking domains, and no collected data types. Its `NSPrivacyAccessedAPICategorySystemBootTime` entry uses reason `35F9.1` for local elapsed-time calculations and timers using `systemUptime`; this timing information is not sent off-device. The synchronized app source group is intended to include the manifest as a resource. A manual Build/Archive must confirm it is present at `Freeze Input.app/Contents/Resources/PrivacyInfo.xcprivacy`. File presence and plist syntax alone do not prove packaging or App Store Connect acceptance.

## Development and validation

The standalone logic checks can be compiled and run manually on macOS with a suitable Swift compiler:

```sh
swiftc -module-cache-path /tmp/freeze-input-swift-module-cache -parse-as-library 'Freeze Input/EscapePressTracker.swift' 'Freeze Input/InputInterceptor.swift' Tests/LogicChecks.swift -o /tmp/freeze-input-logic-checks
/tmp/freeze-input-logic-checks
```

The executable uses `precondition` assertions. Do not disable assertions. It does not start a cleaning session, install event monitors, create global taps, post events, or reproduce the app target's full build settings. It was not executed for the sandbox change.

Static checks include property-list validation, Swift syntax parsing, and `git diff --check`. These do not prove SDK type compatibility, signed entitlements, runtime safety, or App Store eligibility. Build/Test and the [manual runtime checklist](TECHNICAL_DOCUMENTATION.md#manual-runtime-validation) remain manual.

## Known limitations

- A local monitor only consumes supported events delivered to this app; system event routing and nested event-tracking loops can bypass it.
- Cursor hiding does not freeze the pointer or disable a mouse/trackpad.
- Watchdog scheduling is not a hard real-time guarantee. A fully stalled process cannot run its own cleanup, and emergency termination bypasses normal AppKit restoration.
- There is no UI inspection switch or background global filtering mode. The current source sets overlay alpha to `1` (fully opaque); changing that source value is a diagnostic edit, not a product setting.
- Enabling App Sandbox does not establish a signed distribution artifact or guarantee Apple approval.
- No project-wide `LICENSE` or `COPYING` file was found. Do not infer redistribution rights from source availability.
