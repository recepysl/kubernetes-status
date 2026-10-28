import Foundation

public enum RancherError: Error, LocalizedError, Equatable {
    case invalidURL
    case unauthorized
    case http(Int, String)
    case network(String)
    case decode(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter the Rancher server URL, e.g. https://rancher.example.com."
        case .unauthorized: return "Rancher rejected the API token (401). Create a new one under Account & API Keys."
        case .http(let code, let message): return message.isEmpty ? "Rancher returned HTTP \(code)." : "Rancher returned HTTP \(code): \(message)"
        case .network(let message): return message
        case .decode(let message): return "Unexpected Rancher response: \(message)"
        }
    }
}

public struct RancherEndpoint: Sendable, Equatable {
    public let baseURL: URL
    public let clusterID: String
    public let token: String

    public init(baseURL: URL, clusterID: String, token: String) {
        self.baseURL = baseURL
        self.clusterID = clusterID
        self.token = token
    }

    public static func detect(server: String?, token: String?) -> RancherEndpoint? {
        guard let server, let token, !token.isEmpty,
              let components = URLComponents(string: server),
              let scheme = components.scheme, let host = components.host else { return nil }
        let segments = components.path.split(separator: "/").map(String.init)
        guard segments.count >= 3,
              segments[segments.count - 3] == "k8s",
              segments[segments.count - 2] == "clusters" else { return nil }
        let prefix = segments.dropLast(3).map { "/" + $0 }.joined()
        let port = components.port.map { ":\($0)" } ?? ""
        guard let base = URL(string: "\(scheme)://\(host)\(port)\(prefix)") else { return nil }
        return RancherEndpoint(baseURL: base, clusterID: segments[segments.count - 1], token: token)
    }

    public static func normalize(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        for suffix in ["/v3", "/dashboard"] where trimmed.hasSuffix(suffix) {
            trimmed.removeLast(suffix.count)
        }
        guard let url = URL(string: trimmed), url.host != nil, url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }
}

public struct RancherCluster: Decodable, Sendable, Equatable {
    public struct Version: Decodable, Sendable, Equatable {
        public let gitVersion: String?
    }

    public let id: String
    public let name: String
    public let state: String?
    public let provider: String?
    public let version: Version?
    public let nodeCount: Int?
    public let allocatable: [String: String]?
    public let requested: [String: String]?

    public init(
        id: String,
        name: String,
        state: String? = nil,
        provider: String? = nil,
        version: String? = nil,
        nodeCount: Int? = nil,
        allocatable: [String: String]? = nil,
        requested: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.state = state
        self.provider = provider
        self.version = version.map { Version(gitVersion: $0) }
        self.nodeCount = nodeCount
        self.allocatable = allocatable
        self.requested = requested
    }

    public var info: ClusterInfo {
        let reportsRequests = (Quantity.parse(requested?["pods"]) ?? 0) > 0
        func allocation(_ key: String) -> ClusterInfo.Allocation? {
            guard reportsRequests, let total = Quantity.parse(allocatable?[key]), total > 0 else { return nil }
            return ClusterInfo.Allocation(requested: Quantity.parse(requested?[key]) ?? 0, allocatable: total)
        }
        return ClusterInfo(
            provider: provider,
            version: version?.gitVersion,
            state: state,
            nodeCount: nodeCount,
            cpu: allocation("cpu"),
            memory: allocation("memory"),
            pods: allocation("pods")
        )
    }
}

public struct RancherClient: Sendable {
    public let baseURL: URL
    public let token: String

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: configuration)
    }()

    public init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    public init(endpoint: RancherEndpoint) {
        self.init(baseURL: endpoint.baseURL, token: endpoint.token)
    }

    public func clusters() async throws -> [RancherCluster] {
        let data = try await get(baseURL.appendingPathComponent("v3/clusters"))
        do {
            return try JSONDecoder().decode(ClusterCollection.self, from: data).data
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            throw RancherError.decode(error.localizedDescription)
        }
    }

    public func cluster(id: String) async throws -> RancherCluster {
        let data = try await get(baseURL.appendingPathComponent("v3/clusters/\(id)"))
        do {
            return try JSONDecoder().decode(RancherCluster.self, from: data)
        } catch {
            throw RancherError.decode(error.localizedDescription)
        }
    }

    public func pods(clusterID: String, now: Date = Date()) async throws -> [PodStatus] {
        var next: URL? = baseURL.appendingPathComponent("k8s/clusters/\(clusterID)/v1/pods")
        var pods: [PodStatus] = []
        var pages = 0
        while let url = next, pages < 50 {
            let page = try await get(url)
            do {
                let collection = try JSONDecoder().decode(SteveCollection.self, from: page)
                pods += collection.data.compactMap { PodClassifier.classify($0, now: now) }
                next = collection.pagination?.next.flatMap(URL.init(string:))
            } catch {
                throw RancherError.decode(error.localizedDescription)
            }
            pages += 1
        }
        return pods
    }

    public func status(context: String, clusterID: String, namespaces: [String], now: Date = Date()) async -> ContextStatus {
        async let detail = try? cluster(id: clusterID)
        do {
            var pods = try await self.pods(clusterID: clusterID, now: now)
            if !namespaces.isEmpty {
                let allowed = Set(namespaces)
                pods = pods.filter { allowed.contains($0.namespace) }
            }
            return ContextStatus(name: context, pods: pods, fetchedAt: now, info: await detail?.info)
        } catch {
            return ContextStatus(name: context, pods: [], error: error.localizedDescription, fetchedAt: now, info: await detail?.info)
        }
    }

    func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw RancherError.network(error.localizedDescription)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            if code == 401 { throw RancherError.unauthorized }
            throw RancherError.http(code, Self.message(from: data))
        }
        return data
    }

    static func message(from data: Data) -> String {
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data), let message = body.message, !message.isEmpty {
            return message.count > 200 ? String(message.prefix(200)) + "…" : message
        }
        return ""
    }

    private struct ClusterCollection: Decodable {
        let data: [RancherCluster]
    }

    private struct SteveCollection: Decodable {
        struct Pagination: Decodable {
            let next: String?
        }

        let data: [PodList.Pod]
        let pagination: Pagination?
    }

    private struct ErrorBody: Decodable {
        let message: String?
    }
}

public enum RancherKubeconfig {
    public struct Entry: Sendable, Equatable {
        public let context: String
        public let clusterID: String

        public init(context: String, clusterID: String) {
            self.context = context
            self.clusterID = clusterID
        }
    }

    public static func render(baseURL: URL, token: String, entries: [Entry]) -> String {
        let base = baseURL.absoluteString.hasSuffix("/") ? String(baseURL.absoluteString.dropLast()) : baseURL.absoluteString
        var lines = ["apiVersion: v1", "kind: Config", "clusters:"]
        for entry in entries {
            lines += [
                "- name: \(quote(entry.context))",
                "  cluster:",
                "    server: \(quote("\(base)/k8s/clusters/\(entry.clusterID)"))",
            ]
        }
        lines.append("users:")
        for entry in entries {
            lines += [
                "- name: \(quote(entry.context))",
                "  user:",
                "    token: \(quote(token))",
            ]
        }
        lines.append("contexts:")
        for entry in entries {
            lines += [
                "- name: \(quote(entry.context))",
                "  context:",
                "    cluster: \(quote(entry.context))",
                "    user: \(quote(entry.context))",
            ]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func quote(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(value), let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return json
    }
}

struct KubeconfigView: Decodable {
    struct NamedCluster: Decodable {
        struct Cluster: Decodable {
            let server: String?
        }

        let name: String
        let cluster: Cluster?
    }

    struct NamedUser: Decodable {
        struct User: Decodable {
            let token: String?
        }

        let name: String
        let user: User?
    }

    struct NamedContext: Decodable {
        struct Context: Decodable {
            let cluster: String?
            let user: String?
        }

        let name: String
        let context: Context?
    }

    let clusters: [NamedCluster]?
    let users: [NamedUser]?
    let contexts: [NamedContext]?

    static func rancherEndpoints(from data: Data) -> [String: RancherEndpoint] {
        guard let view = try? JSONDecoder().decode(KubeconfigView.self, from: data) else { return [:] }
        var servers: [String: String] = [:]
        for cluster in view.clusters ?? [] where servers[cluster.name] == nil {
            servers[cluster.name] = cluster.cluster?.server
        }
        var tokens: [String: String] = [:]
        for user in view.users ?? [] where tokens[user.name] == nil {
            tokens[user.name] = user.user?.token
        }
        var endpoints: [String: RancherEndpoint] = [:]
        for context in view.contexts ?? [] where endpoints[context.name] == nil {
            guard let cluster = context.context?.cluster, let user = context.context?.user,
                  let endpoint = RancherEndpoint.detect(server: servers[cluster], token: tokens[user]) else { continue }
            endpoints[context.name] = endpoint
        }
        return endpoints
    }
}
