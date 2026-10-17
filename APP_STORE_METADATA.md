# Freeze Input — macOS App Store Metadata

The product-page fields below are English copy for the current macOS foreground-cleaning design. They are ready to paste after confirming the submitted build matches them. Internal checks at the end are not product-page copy. No App Store Connect fields were changed by creating this file.

## Name

Freeze Input

## Subtitle

A foreground cleaning cover

## Promotional Text

Cover your displays and reduce accidental input while cleaning your Mac. Finish with five Esc presses, a backup shortcut, or the three-minute automatic exit.

## Description

Give your Mac a foreground cleaning cover while you wipe your screen, keyboard, or trackpad.

Freeze Input places a black cover across your connected displays and hides the pointer. While its cleaning windows remain in the foreground, it absorbs supported keyboard, mouse, scroll, and trackpad events delivered to the app, helping reduce accidental actions.

SIMPLE TO START AND FINISH
• Choose Start Cleaning while Freeze Input is active.
• Press and release Esc five times within three seconds to finish.
• Or hold Control + Option + Command, press Q, then release Q.
• Every session automatically ends after three minutes.

LOCAL AND PRIVATE
No account, Accessibility permission, or Input Monitoring permission is required. Freeze Input does not record your typing, save input history, collect personal information, or include advertising or tracking.

KNOW THE LIMITS
Freeze Input is a foreground cleaning cover, not a systemwide input lock or a security feature. It does not turn off your keyboard, mouse, or trackpad. The hidden pointer may still move. macOS shortcuts, gestures, Touch ID, the power button, and other system-handled controls may still work. Some restricted system gestures may produce an alert sound.

Cleaning stops if Freeze Input leaves the foreground, the Mac sleeps or changes session, or the display layout changes. It does not resume automatically. If a key remains held when a timeout or system action ends cleaning, later key events may reach another app.

Privacy Policy and Support / Contact are available from Freeze Input → About Freeze Input.

Requires macOS 14 or later.

## Keywords

clean,screen,keyboard,trackpad,display,cover,utility,mac

## Privacy policy URL

https://github.com/q7jxb7yxdk-star/freeze-input/blob/main/PRIVACY_POLICY.md

## Support URL

https://github.com/q7jxb7yxdk-star/freeze-input/issues

## Notes for Review

Freeze Input is a macOS foreground cleaning-cover utility. No login, demo account, backend, Accessibility permission, or Input Monitoring permission is needed.

To review:
1. Open the app and read the exit instructions.
2. Select Start Cleaning. Black windows cover the connected displays and the pointer is hidden.
3. Press and release Esc five times within three seconds to finish. Alternatively, hold Control + Option + Command, press Q, then release Q. The session also ends automatically after three minutes.
4. Open Freeze Input → About Freeze Input for Privacy Policy and Support / Contact links.

The app handles supported input delivered to its own foreground cleaning windows. It does not disable hardware or intercept events systemwide. macOS-reserved shortcuts and gestures may remain available or produce an alert sound when restricted. If the app loses the foreground, the Mac sleeps or changes session, or the display layout changes, cleaning stops and does not resume automatically.

The app processes local event metadata to recognize exit commands. It does not record typed text, save input history, or transmit input events. No third-party SDKs, advertising, analytics, or tracking are included.

## Internal submission checks — do not paste into the product page

- Verify the exact Release build matches this copy, including fully opaque black covers. The current source alpha is `1`; any later diagnostic transparency edit must be restored before using screenshots or copy that show opaque covers.
- Perform manual Build/Test, Archive, distribution-signing, and Organizer validation. These have not been performed for the current metadata/manifest changes. Do not infer their success from earlier non-sandboxed build results.
- Confirm `PrivacyInfo.xcprivacy` is included at `Contents/Resources/PrivacyInfo.xcprivacy` in the final built/archived app and inspect Xcode's generated privacy report.
- Confirm the final App Sandbox entitlement and resource access match the submitted build.
- Verify both GitHub URLs are publicly accessible without signing in, the privacy policy is on the default `main` branch, and Issues is enabled. Public availability has not been verified here. Posting a GitHub issue may require a GitHub account.
- Fill App Privacy based on the final build. The manifest and policy do not submit App Privacy answers automatically. Reassess if any SDK or data flow changes.
- Use real macOS screenshots of the release app. Do not describe complete input blocking, silent operation, disabled hardware, or guaranteed prevention of App/Spaces switching.
- Complete age-rating, export-compliance, pricing, availability, agreement, and applicable trader-status information in App Store Connect.
- Enter the actual review contact details in App Store Connect; no email address or phone number is invented in this file.
- Recheck Apple requirements before submission. Accurate copy and a valid manifest do not guarantee approval.
