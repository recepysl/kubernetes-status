import Foundation

public struct ContextStatus: Sendable, Equatable, Identifiable {
    public var id: String { name }

    public let name: String
    public let pods: [PodStatus]
    public let error: String?
    public let fetchedAt: Date
    public let info: ClusterInfo?

    public init(name: String, pods: [PodStatus], error: String? = nil, fetchedAt: Date = Date(), info: ClusterInfo? = nil) {
        self.name = name
        self.pods = pods
        self.error = error
        self.fetchedAt = fetchedAt
        self.info = info
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

public struct ClusterInfo: Sendable, Equatable {
    public struct Allocation: Sendable, Equatable {
        public let requested: Double
        public let allocatable: Double

        public init(requested: Double, allocatable: Double) {
            self.requested = requested
            self.allocatable = allocatable
        }

        public var fraction: Double? {
            allocatable > 0 ? min(max(requested / allocatable, 0), 1) : nil
        }
    }

    public let provider: String?
    public let version: String?
    public let state: String?
    public let nodeCount: Int?
    public let cpu: Allocation?
    public let memory: Allocation?
    public let pods: Allocation?

    public init(
        provider: String? = nil,
        version: String? = nil,
        state: String? = nil,
        nodeCount: Int? = nil,
        cpu: Allocation? = nil,
        memory: Allocation? = nil,
        pods: Allocation? = nil
    ) {
        self.provider = provider
        self.version = version
        self.state = state
        self.nodeCount = nodeCount
        self.cpu = cpu
        self.memory = memory
        self.pods = pods
    }

    public var isActive: Bool {
        state.map { $0.lowercased() == "active" } ?? true
    }

    public var headline: String {
        var parts: [String] = []
        if let provider, !provider.isEmpty { parts.append(provider.uppercased()) }
        if let version, !version.isEmpty { parts.append(version) }
        if let nodeCount { parts.append("\(nodeCount) node\(nodeCount == 1 ? "" : "s")") }
        if !isActive, let state { parts.append(state) }
        return parts.joined(separator: " · ")
    }
}

public enum Quantity {
    private static let suffixes: [(String, Double)] = [
        ("Ki", 1024), ("Mi", pow(1024, 2)), ("Gi", pow(1024, 3)), ("Ti", pow(1024, 4)), ("Pi", pow(1024, 5)),
        ("n", 1e-9), ("u", 1e-6), ("m", 1e-3), ("k", 1e3), ("M", 1e6), ("G", 1e9), ("T", 1e12), ("P", 1e15),
    ]

    public static func parse(_ text: String?) -> Double? {
        guard let raw = text?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        for (suffix, factor) in suffixes where raw.hasSuffix(suffix) {
            return Double(raw.dropLast(suffix.count)).map { $0 * factor }
        }
        return Double(raw)
    }
}
