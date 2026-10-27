import Foundation

public enum Severity: Int, Sendable, Comparable {
    case healthy = 0
    case warning = 1
    case critical = 2

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct PodStatus: Sendable, Equatable, Identifiable {
    public var id: String { "\(namespace)/\(name)" }

    public let name: String
    public let namespace: String
    public let reason: String
    public let ready: Int
    public let total: Int
    public let restarts: Int
    public let createdAt: Date?
    public let severity: Severity

    public init(
        name: String,
        namespace: String,
        reason: String,
        ready: Int,
        total: Int,
        restarts: Int,
        createdAt: Date?,
        severity: Severity
    ) {
        self.name = name
        self.namespace = namespace
        self.reason = reason
        self.ready = ready
        self.total = total
        self.restarts = restarts
        self.createdAt = createdAt
        self.severity = severity
    }
}

public enum PodClassifier {
    public static let startupGrace: TimeInterval = 5 * 60

    static let criticalReasons: Set<String> = [
        "CrashLoopBackOff",
        "ImagePullBackOff",
        "ErrImagePull",
        "InvalidImageName",
        "CreateContainerConfigError",
        "CreateContainerError",
        "RunContainerError",
        "OOMKilled",
        "Error",
        "ContainerCannotRun",
        "DeadlineExceeded",
    ]

    public static func decode(_ data: Data, now: Date = Date()) throws -> [PodStatus] {
        let list = try JSONDecoder().decode(PodList.self, from: data)
        return list.items.compactMap { classify($0, now: now) }
    }

    static func classify(_ pod: PodList.Pod, now: Date) -> PodStatus? {
        guard pod.metadata.deletionTimestamp == nil else { return nil }

        let status = pod.status
        let containers = status?.containerStatuses ?? []
        let initContainers = status?.initContainerStatuses ?? []
        let total = max(pod.spec?.containers?.count ?? 0, containers.count)
        let ready = containers.filter { $0.ready == true }.count
        let restarts = (containers + initContainers).reduce(0) { $0 + ($1.restartCount ?? 0) }
        let createdAt = pod.metadata.creationTimestamp.flatMap(parseDate)
        let isYoung = createdAt.map { now.timeIntervalSince($0) < startupGrace } ?? false
        let ownedByJob = pod.metadata.ownerReferences?.contains { $0.kind == "Job" } ?? false
        let phase = status?.phase ?? "Unknown"

        func make(_ reason: String, _ severity: Severity) -> PodStatus {
            PodStatus(
                name: pod.metadata.name,
                namespace: pod.metadata.namespace ?? "default",
                reason: reason,
                ready: ready,
                total: total,
                restarts: restarts,
                createdAt: createdAt,
                severity: severity
            )
        }

        if phase == "Succeeded" {
            return make("Completed", .healthy)
        }
        if phase == "Failed" {
            let reason = status?.reason ?? containers.compactMap { $0.state?.terminated?.reason }.first ?? "Failed"
            return make(reason, ownedByJob || reason == "Evicted" ? .warning : .critical)
        }

        let stuck = (initContainers + containers).compactMap { container -> String? in
            if let waiting = container.state?.waiting?.reason { return waiting }
            if let terminated = container.state?.terminated?.reason, terminated != "Completed" { return terminated }
            return nil
        }
        if let critical = stuck.first(where: { criticalReasons.contains($0) }) {
            return make(critical, .critical)
        }

        if phase == "Running" && total > 0 && ready == total {
            return make("Running", .healthy)
        }

        let reason = stuck.first ?? (phase == "Running" ? "NotReady" : phase)
        return make(reason, isYoung ? .healthy : .warning)
    }

    static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

struct PodList: Decodable {
    struct Pod: Decodable {
        struct Metadata: Decodable {
            struct Owner: Decodable {
                let kind: String?
            }

            let name: String
            let namespace: String?
            let creationTimestamp: String?
            let deletionTimestamp: String?
            let ownerReferences: [Owner]?
        }

        struct Spec: Decodable {
            struct Container: Decodable {
                let name: String?
            }

            let containers: [Container]?
        }

        struct Status: Decodable {
            struct ContainerStatus: Decodable {
                struct State: Decodable {
                    struct Detail: Decodable {
                        let reason: String?
                    }

                    let waiting: Detail?
                    let terminated: Detail?
                }

                let ready: Bool?
                let restartCount: Int?
                let state: State?
            }

            let phase: String?
            let reason: String?
            let containerStatuses: [ContainerStatus]?
            let initContainerStatuses: [ContainerStatus]?
        }

        let metadata: Metadata
        let spec: Spec?
        let status: Status?
    }

    let items: [Pod]
}
