import SwiftUI
import AppKit

struct KubernetesStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var monitor = StatusMonitor.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            StatusMonitor.shared.start()
            LoginItem.shared.enableByDefaultIfFirstRun()
            if Preferences.shared.notificationsEnabled {
                Notifier.shared.requestAuthorization()
            }
        }
    }
}
