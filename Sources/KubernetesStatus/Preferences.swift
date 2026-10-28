import Foundation

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    static let intervals: [TimeInterval] = [30, 60, 120, 300]

    @Published var kubeconfigText: String {
        didSet { defaults.set(kubeconfigText, forKey: Keys.kubeconfigs) }
    }
    @Published var kubectlPath: String {
        didSet { defaults.set(kubectlPath, forKey: Keys.kubectlPath) }
    }
    @Published var disabledContexts: Set<String> {
        didSet { defaults.set(Array(disabledContexts).sorted(), forKey: Keys.disabledContexts) }
    }
    @Published var namespaceFilters: [String: String] {
        didSet { defaults.set(namespaceFilters, forKey: Keys.namespaceFilters) }
    }
    @Published var interval: TimeInterval {
        didSet { defaults.set(interval, forKey: Keys.interval) }
    }
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notifications) }
    }
    @Published var rancherServers: [String] {
        didSet { defaults.set(rancherServers, forKey: Keys.rancherServers) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let kubeconfigs = "kubeconfigPaths"
        static let kubectlPath = "kubectlPath"
        static let disabledContexts = "disabledContexts"
        static let namespaceFilters = "namespaceFilters"
        static let interval = "refreshInterval"
        static let notifications = "notificationsEnabled"
        static let rancherServers = "rancherServers"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let environmentConfigs = ProcessInfo.processInfo.environment["KUBECONFIG"]?
            .split(separator: ":").joined(separator: "\n")
        kubeconfigText = defaults.string(forKey: Keys.kubeconfigs) ?? environmentConfigs ?? "~/.kube/config"
        kubectlPath = defaults.string(forKey: Keys.kubectlPath) ?? ""
        disabledContexts = Set(defaults.stringArray(forKey: Keys.disabledContexts) ?? [])
        namespaceFilters = defaults.dictionary(forKey: Keys.namespaceFilters) as? [String: String] ?? [:]
        let savedInterval = defaults.double(forKey: Keys.interval)
        interval = Self.intervals.contains(savedInterval) ? savedInterval : 60
        notificationsEnabled = defaults.object(forKey: Keys.notifications) as? Bool ?? true
        rancherServers = defaults.stringArray(forKey: Keys.rancherServers) ?? []
    }

    var kubeconfigEntries: [String] {
        kubeconfigText.split(whereSeparator: \.isNewline).map(String.init)
    }

    func isWatched(_ context: String) -> Bool {
        !disabledContexts.contains(context)
    }

    func setWatched(_ context: String, _ watched: Bool) {
        if watched {
            disabledContexts.remove(context)
        } else {
            disabledContexts.insert(context)
        }
    }

    func namespaces(for context: String) -> [String] {
        (namespaceFilters[context] ?? "")
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map(String.init)
    }
}
