import AppKit
import SwiftUI

@main
struct TimeMachineViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = MonitorStore()

    var body: some Scene {
        Window("Time Machine Viewer", id: "main") {
            ContentView()
                .environment(store)
                .task { store.start() }
        }
        .defaultSize(width: 920, height: 680)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // swift run で .app にせず起動したときも、普通のアプリとして前面に出す。
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
