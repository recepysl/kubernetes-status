import Foundation
import ServiceManagement

@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    @Published private(set) var isEnabled = false
    @Published private(set) var lastError: String?

    private let autoEnabledKey = "loginItemAutoEnabled"

    private init() {
        refresh()
    }

    var isInstalled: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !enabled, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func enableByDefaultIfFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: autoEnabledKey), isInstalled else { return }
        if SMAppService.mainApp.status == .notRegistered {
            setEnabled(true)
        }
        defaults.set(true, forKey: autoEnabledKey)
    }
}
