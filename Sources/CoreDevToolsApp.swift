import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct CoreDevToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = WorkspaceStore()

    var body: some Scene {
        Window("Core Dev Tools", id: "main") {
            RootView()
                .environmentObject(store)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Tool Tab") {
                    store.addHomeTab()
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandMenu("Tabs") {
                Button("Close Tab") {
                    store.closeSelectedTab()
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Button("Previous Tab") {
                    store.selectAdjacentTab(offset: -1)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Button("Next Tab") {
                    store.selectAdjacentTab(offset: 1)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            }
        }
    }
}
