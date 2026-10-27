import Foundation

public struct ContextStatus: Sendable, Equatable, Identifiable {
    public var id: String { name }

    public let name: String
    public let pods: [PodStatus]
    public let error: String?
    public let fetchedAt: Date

    public init(name: String, pods: [PodStatus], error: String? = nil, fetchedAt: Date = Date()) {
        self.name = name
        self.pods = pods
        self.error = error
        self.fetchedAt = fetchedAt
    }

    public var unhealthy: [PodStatus] {
        pods
            .filter { $0.severity != .healthy }
            .sorted { lhs, rhs in
                lhs.severity != rhs.severity ? lhs.severity > rhs.severity : lhs.id < rhs.id
            }
    }

    public var healthyCount: Int {
        pods.count - unhealthy.count
    }

    public var severity: Severity {
        if error != nil { return .warning }
        return unhealthy.map(\.severity).max() ?? .healthy
    }
}

public struct ClusterSummary: Sendable, Equatable {
    public let contexts: [ContextStatus]

    public init(contexts: [ContextStatus]) {
        self.contexts = contexts
    }

    public var podCount: Int {
        contexts.reduce(0) { $0 + $1.pods.count }
    }

    public var unhealthyCount: Int {
        contexts.reduce(0) { $0 + $1.unhealthy.count }
    }

    public var unreachableCount: Int {
        contexts.filter { $0.error != nil }.count
    }

    public var severity: Severity {
        contexts.map(\.severity).max() ?? .healthy
    }
}

public enum PodTransitions {
    public static func newlyFailing(previous: ContextStatus?, current: ContextStatus) -> [PodStatus] {
        guard let previous, previous.error == nil, current.error == nil else { return [] }
        let before = Set(previous.pods.filter { $0.severity == .critical }.map(\.id))
        return current.pods.filter { $0.severity == .critical && !before.contains($0.id) }
    }
}
