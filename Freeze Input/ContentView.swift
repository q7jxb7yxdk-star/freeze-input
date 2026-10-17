import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: CleaningController

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Freeze Input")
                .font(.largeTitle.bold())
            Text("Reduce accidental input while cleaning your screen, keyboard and trackpad.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Label("Press Esc 5 times within 3 seconds to finish.", systemImage: "escape")
                Label("Backup exit: Control + Option + Command + Q, then release Q.", systemImage: "keyboard")
                Label("Automatically finishes after 3 minutes.", systemImage: "clock")
            }
            .font(.callout)

            Button("Start Cleaning") { controller.start() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(controller.isBusy)

            if controller.isBusy && !controller.isCleaning {
                Text("Preparing the cleaning cover…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let message = controller.message {
                Text(message)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(message)
            }
            if controller.isWaitingForExitRelease {
                Text("Release Q to finish cleaning.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("Only input sent to the cleaning cover is blocked. System shortcuts, gestures, Touch ID and the power button may still work. Some system gestures may play an alert sound. Cleaning ends if you switch away from Freeze Input.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("No Accessibility or Input Monitoring permission is required. Your typing is not recorded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(width: 510)
        .fixedSize(horizontal: false, vertical: true)
    }
}
