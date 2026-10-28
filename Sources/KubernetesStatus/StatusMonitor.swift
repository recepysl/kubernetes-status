import Foundation
import Combine
import KubeStatusKit

@MainActor
final class StatusMonitor: ObservableObject {
    static let shared = StatusMonitor()

    @Published private(set) var contexts: [String] = []
    @Published private(set) var currentContext: String?
    @Published private(set) var statuses: [String: ContextStatus] = [:]
    @Published private(set) var setupError: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var expanded: Set<String> = []

    private let preferences: Preferences
    private var timer: Timer?
    private var generation = 0
    private var userExpansion: [String: Bool] = [:]
    private var subscriptions: Set<AnyCancellable> = []
    private var discoveredRancher: [String: RancherEndpoint] = [:]

    private init() {
        preferences = .shared
    }

    init(
        preview statuses: [ContextStatus],
        currentContext: String? = nil,
        setupError: String? = nil,
        lastUpdated: Date? = Date()
    ) {
        preferences = Preferences(defaults: UserDefaults(suiteName: "preview-\(UUID().uuidString)")!)
        self.contexts = statuses.map(\.name)
        self.statuses = Dictionary(uniqueKeysWithValues: statuses.map { ($0.name, $0) })
        self.currentContext = currentContext
        self.setupError = setupError
        self.lastUpdated = lastUpdated
        self.expanded = Set(statuses.filter { $0.severity != .healthy }.map(\.name))
    }

    var watchedStatuses: [ContextStatus] {
        contexts.filter(preferences.isWatched).compactMap { statuses[$0] }
    }

    var summary: ClusterSummary {
        ClusterSummary(contexts: watchedStatuses)
    }

    var hasLoaded: Bool {
        lastUpdated != nil || setupError != nil
    }

    func start() {
        refreshNow()
        schedule()
        preferences.$interval
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor in self?.schedule() } }
            .store(in: &subscriptions)
        preferences.$disabledContexts
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor in self?.refreshNow() } }
            .store(in: &subscriptions)
    }

    func refreshNow() {
        Task { await tick() }
    }

    func isExpanded(_ context: String) -> Bool {
        expanded.contains(context)
    }

    func toggle(_ context: String) {
        let open = !expanded.contains(context)
        userExpansion[context] = open
        if open {
            expanded.insert(context)
        } else {
            expanded.remove(context)
        }
    }

    func kubectl() -> Kubectl? {
        guard let executable = Kubectl.locate(override: preferences.kubectlPath) else { return nil }
        let entries = preferences.kubeconfigEntries + RancherAccounts.shared.kubeconfigEntries
        return Kubectl(executable: executable, kubeconfigs: Kubectl.resolveKubeconfigs(entries))
    }

    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: preferences.interval, repeats: true) { [weak self] _ in
            Task { await self?.tick() }
        }
    }

    private func tick() async {
        generation += 1
        let gen = generation
        isRefreshing = true
        defer { if gen == generation { isRefreshing = false } }

        await RancherAccounts.shared.sync()
        guard gen == generation else { return }

        guard let kubectl = kubectl() else {
            setupError = KubectlError.notFound.localizedDescription
            return
        }
        guard !kubectl.kubeconfigs.isEmpty else {
            setupError = KubectlError.noKubeconfig.localizedDescription
            return
        }

        let discovery = await Self.discover(kubectl)
        guard gen == generation else { return }
        switch discovery {
        case .failure(let error):
            setupError = error.localizedDescription
            return
        case .success(let found):
            setupError = found.contexts.isEmpty ? "No contexts found in the configured kubeconfig files." : nil
            contexts = found.contexts
            currentContext = found.current
            discoveredRancher = found.rancher
        }

        let targets = contexts.filter(preferences.isWatched).map { ($0, preferences.namespaces(for: $0)) }
        let results = await Self.fetch(kubectl, rancher: discoveredRancher, targets: targets)
        guard gen == generation else { return }

        for status in results {
            let previous = statuses[status.name]
            if preferences.notificationsEnabled {
                Notifier.shared.notify(PodTransitions.newlyFailing(previous: previous, current: status), context: status.name)
            }
            statuses[status.name] = status
            if userExpansion[status.name] == nil {
                if status.severity != .healthy {
                    expanded.insert(status.name)
                } else {
                    expanded.remove(status.name)
                }
            }
        }
        lastUpdated = Date()
    }

    private struct Discovery: Sendable {
        let contexts: [String]
        let current: String?
        let rancher: [String: RancherEndpoint]
    }

    nonisolated private static func discover(_ kubectl: Kubectl) async -> Result<Discovery, Error> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let contexts = try kubectl.contexts()
                    let discovery = Discovery(
                        contexts: contexts,
                        current: kubectl.currentContext(),
                        rancher: kubectl.rancherEndpoints()
                    )
                    continuation.resume(returning: .success(discovery))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }

    nonisolated private static func fetch(
        _ kubectl: Kubectl,
        rancher: [String: RancherEndpoint],
        targets: [(String, [String])]
    ) async -> [ContextStatus] {
        await withTaskGroup(of: ContextStatus.self) { group in
            for (context, namespaces) in targets {
                if let endpoint = rancher[context] {
                    group.addTask {
                        await RancherClient(endpoint: endpoint).status(context: context, clusterID: endpoint.clusterID, namespaces: namespaces)
                    }
                    continue
                }
                group.addTask {
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global(qos: .utility).async {
                            continuation.resume(returning: kubectl.status(context: context, namespaces: namespaces))
                        }
                    }
                }
            }
            var results: [ContextStatus] = []
            for await status in group { results.append(status) }
            return results
        }
    }
}
