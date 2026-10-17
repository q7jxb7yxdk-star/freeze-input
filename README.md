# Freeze Input

Freeze Input is a native macOS app that reduces accidental keyboard and pointer input while cleaning a screen, keyboard, or trackpad. It uses SwiftUI for its control window, AppKit for black overlays, and public Core Graphics event taps for input filtering. It does not disable input hardware.

## Implementation and evidence status

- **Implemented:** Accessibility-gated session startup, keyboard and pointer event filtering, black windows on connected screens, local AppKit gesture filtering, exit-key handling, and safety/recovery paths are connected to the app's normal execution path.
- **Test-covered:** Standalone checks exist for Esc sequences, exit-event decoding, keyboard-tap metadata validation, and safety/heartbeat boundaries. Their presence does not establish a passing run.
- **Verified in this task (2026-10-15):** Repository/source inspection, property-list syntax validation, and documentation consistency, path, formatting, and change-scope checks only. No app build or test suite was executed.
- **Externally unverified:** Accessibility authorization, physical input delivery/suppression, displays, cursor recovery, system gestures, emergency termination, signing, and distribution require validation on a Mac.
- **Experimental / Inactive:** A source-only visible inspection mode exists but is disabled by the current `showsBlackScreen = true` setting. It still creates real input filters; it is not a mock or demo.
- **Planned / Not implemented:** Suggested extensions are listed in the [technical documentation](TECHNICAL_DOCUMENTATION.md#future-development); they are not available features.

## Features

- Requires Accessibility trust and rejects startup while Secure Event Input is active.
- Creates separate keyboard and pointer session event taps. Startup requires both taps and an enabled keyboard tap belonging to this process with key-down and key-up coverage before showing black windows.
- Covers each enumerated screen with a plain black window, hides the cursor, and changes Dock/menu presentation during cleaning.
- Exits on the fifth complete Esc press/release within three seconds, on Control + Option + Command + Q, or at a three-minute safety deadline.
- Stops for permission loss, tap disablement, Secure Event Input, app deactivation, sleep/session changes, and display changes. It never resumes automatically.
- Includes UI heartbeat monitoring and an independent emergency process-exit fallback for a blocked main queue.

These are source implementations, not guarantees that macOS delivers every hardware or reserved system event to the app. See [Known limitations](#known-limitations).

## Requirements

| Item | Repository evidence |
| --- | --- |
| Platform | macOS only: `SUPPORTED_PLATFORMS = macosx`; Mac Catalyst disabled |
| Minimum OS | macOS 14.0 in Debug and Release project settings |
| Swift | `SWIFT_VERSION = 5.0` is the language mode, not a pinned compiler version |
| Xcode / SDK | No exact minimum or pinned version is declared. Project metadata records creation with tools 26.3 and upgrade check 2700; these do not establish compatibility. `SDKROOT = auto` |
| Project format | `objectVersion = 90`; uses a file-system-synchronized source group, requiring an Xcode version that supports this project format |
| Dependencies | Apple frameworks only; no third-party dependency manifest, package lockfile, or dependency installation step |
| Runtime permission | Accessibility trust for the running app identity |
| Architecture | No explicit CPU architecture restriction is declared; Apple Silicon/Intel compatibility has not been verified in this task |

## Installation and setup

1. Obtain a local checkout and work from its repository root. No repository clone URL is supplied here because it is not declared in project setup files.
2. Open `Freeze Input.xcodeproj` in a compatible Xcode installation.
3. Select the **Freeze Input** app target and the local Mac run destination. The project has Debug and Release configurations.
4. Select the scheme for that target in Xcode. There is no checked-in `.xcscheme` definition; user scheme metadata mentions `Freeze Input` and a stale `MyApp` entry, which does not prove either scheme's actions or command-line availability.
5. Review Signing & Capabilities for your development environment. Automatic signing and a machine/account-specific development team are configured; no certificates or private signing material are included. Signing changes are separate from this documentation update.
6. Launch manually and use **Request Access** if needed. Grant the running app Accessibility access in System Settings, then return to the app. Rebuilt apps whose identity or path changes may need manual reauthorization; the app cannot grant itself permission.

There are no app environment variables, API keys, backend services, cloud accounts, or environment example files. The app operates locally and has no offline/demo versus remote-service split.

## How to run

Build and Run manually in Xcode using the app target and local Mac destination. No iOS/iPadOS target or Simulator workflow exists despite unused mobile-platform settings in the project file. A command-line app build command is intentionally not asserted: a shared scheme and its build actions are not checked in or verified.

Before starting, read the exit instructions:

1. Press **Start Cleaning** while Freeze Input is in the foreground. With the current source default, connected screens receive black overlays with no controls or countdown.
2. Press and release **Esc five times within three seconds**. Exit occurs on the fifth release. Automatic repeats and a long hold do not count as multiple presses; another key-down or modifier change resets the sequence.
3. Use **Control + Option + Command + Q** as the backup exit, or wait for the **three-minute automatic exit**.

After backup exit, starting another session remains disabled until Q is released or the ten-second release grace period expires. If a key remains physically held after that deadline, its later events can pass through normally.

## Project structure

| Path | Responsibility |
| --- | --- |
| `Freeze Input.xcodeproj/` | App target, build settings, workspace, and user scheme metadata |
| `Freeze Input/MyApp.swift` | `FreezeInputApp` entry point and termination delegate |
| `Freeze Input/ContentView.swift` | Instructions, permission request, start control, and status |
| `Freeze Input/CleaningController.swift` | Main-actor session and lifecycle coordination |
| `Freeze Input/InputInterceptor.swift` | Event-tap worker, exit decoding, health checks, and recovery |
| `Freeze Input/EscapePressTracker.swift` | Pure sequence tracking, exit reasons, and time policies |
| `Freeze Input/BlackoutWindows.swift` | Overlay windows, cursor/presentation ownership, and local event fallback |
| `Freeze Input/AccessibilityPermission.swift` | Trust checks, permission prompt, and unused Settings-link helper |
| `Freeze Input/Assets.xcassets/` | Asset catalog metadata and accent-color entry |
| `Tests/LogicChecks.swift` | Standalone in-memory logic checks; not an Xcode test target |

## Development and validation

The existing standalone check command can be run manually from the repository root on macOS with a suitable Swift compiler and Apple SDK:

```sh
swiftc -module-cache-path /tmp/freeze-input-swift-module-cache -parse-as-library 'Freeze Input/EscapePressTracker.swift' 'Freeze Input/InputInterceptor.swift' Tests/LogicChecks.swift -o /tmp/freeze-input-logic-checks
/tmp/freeze-input-logic-checks
```

This compiles a separate check executable, constructs events in memory, and uses `precondition` assertions. It neither creates live taps nor posts events. Do not disable assertions when using it. It does not use the full app target's build configuration and cannot establish app compilation or runtime correctness. It was **not run in this task**.

Lightweight configuration/whitespace checks used for this documentation task:

```sh
plutil -lint 'Freeze Input.xcodeproj/project.pbxproj'
git diff --check
```

There is no XCTest/Swift Testing target, CI pipeline, repository script, or configured standalone lint/format tool. Xcode enables compiler/analyzer warnings, but no analysis run is claimed here. App Build/Test and the [physical Mac validation checklist](TECHNICAL_DOCUMENTATION.md#manual-runtime-validation) remain manual.

## Known limitations

- Public event APIs cannot guarantee suppression of Mission Control, Spaces, Show Desktop, Touch ID, power/media/brightness keys, or reserved system shortcuts. AppKit monitors consume only supported events delivered to this app.
- Secure Event Input prevents safe operation; the app refuses startup or ends the session when detected. Tap metadata is not proof of physical event delivery.
- Foreground loss ends cleaning. This is not a background input blocker.
- Timers and watchdogs reduce failure exposure but cannot guarantee recovery from every OS/process failure. Emergency termination bypasses normal AppKit cleanup; cursor restoration needs hardware verification.
- App Sandbox is explicitly disabled. The repository does not establish Mac App Store eligibility, notarization, or a distributable signed artifact.
- The source-only inspection setting requires a code change and rebuild; it has no UI toggle. Its behavior and safety limits are detailed in the [technical documentation](TECHNICAL_DOCUMENTATION.md).
- The repository includes user-specific Xcode metadata and a development-team setting, with no shared scheme or pinned toolchain.

## License

No project-wide `LICENSE`, `COPYING`, or other license declaration was found. Do not infer redistribution rights from the source being present. No third-party packages or corresponding bundled license notices were found; Apple frameworks and SDKs remain subject to their own terms, separate from a project license.
