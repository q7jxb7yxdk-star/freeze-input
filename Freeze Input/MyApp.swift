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
            CommandGroup(replacing: .appInfo) {
                Button("About Freeze Input") {
                    NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.aboutLinks])
                }
            }
            CommandGroup(replacing: .newItem) {}
        }
    }

    private static var aboutLinks: NSAttributedString {
        let links = NSMutableAttributedString(string: "")
        links.append(NSAttributedString(
            string: "Privacy Policy",
            attributes: [.link: "https://github.com/q7jxb7yxdk-star/freeze-input/blob/main/PRIVACY_POLICY.md"]
        ))
        links.append(NSAttributedString(string: "\n\n"))
        links.append(NSAttributedString(
            string: "Support / Contact",
            attributes: [.link: "https://github.com/q7jxb7yxdk-star/freeze-input/issues"]
        ))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        links.addAttributes([
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .paragraphStyle: paragraph
        ], range: NSRange(location: 0, length: links.length))
        return links
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
