import AppKit
import SwiftUI

@main
struct AliniereApp: App {
    @NSApplicationDelegateAdaptor(AliniereAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Alinière") {
            ContentView()
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Alinière") {
                    AliniereAppDelegate.updateAppMenuTitle()
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Alinière"
                    ])
                }
            }
            CommandGroup(replacing: .newItem) {}
        }
    }
}

private final class AliniereAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.updateAppMenuTitleRepeatedly()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.updateAppMenuTitleRepeatedly()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Self.updateAppMenuTitleRepeatedly()
    }

    static func updateAppMenuTitle() {
        NSApp.mainMenu?.items.first?.title = "Alinière"
        NSApp.mainMenu?.items.first?.submenu?.items.first?.title = "About Alinière"
    }

    private static func updateAppMenuTitleRepeatedly() {
        updateAppMenuTitle()
        for delay in [0.0, 0.1, 0.5, 1.0, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                updateAppMenuTitle()
            }
        }
    }
}
