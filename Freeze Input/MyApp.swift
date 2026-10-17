import SwiftUI
import AppKit

@main
struct FreezeInputApp: App {
    @NSApplicationDelegateAdaptor(FreezeInputAppDelegate.self) private var delegate
    @StateObject private var controller = CleaningController.shared

    var body: some Scene {
        Window("Freeze Input", id: "main") {
            ContentView(controller: controller)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

@MainActor
final class FreezeInputAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        CleaningController.shared.shutdown()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        CleaningController.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !CleaningController.shared.isBusy
    }
}
