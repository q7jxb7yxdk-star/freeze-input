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
            Text("Clean your screen, keyboard and trackpad with fewer accidental inputs.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Label("Press Esc 5 times within 3 seconds to finish.", systemImage: "escape")
                Label("Backup exit: Control + Option + Command + Q.", systemImage: "keyboard")
                Label("Automatically finishes after 3 minutes.", systemImage: "clock")
            }
            .font(.callout)

            if !controller.hasPermission {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Accessibility permission required", systemImage: "lock.shield")
                        .font(.headline)
                    Text("In System Settings → Privacy & Security, allow Freeze Input under Accessibility (called Device Control and Data Access on some macOS versions). This is needed to block input. Return here after granting access.")
                        .font(.callout)
                    HStack {
                        Button("Request Access") { controller.requestPermission() }
                    }
                }
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
            Button("Start Cleaning") { controller.start() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!controller.hasPermission || controller.isBusy)

            if let message = controller.message {
                Text(message)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(message)
            }
            if controller.isBusy && !controller.isCleaning {
                Text("Release the exit key before starting again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("System gestures, Touch ID and the power button may still work. This app does not disable hardware or record your typing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(width: 510)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { controller.refreshPermission() }
    }
}
