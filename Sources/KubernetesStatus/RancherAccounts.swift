import Foundation
import Security
import KubeStatusKit

@MainActor
final class RancherAccounts: ObservableObject {
    static let shared = RancherAccounts(preferences: .shared)

    struct ServerState: Equatable {
        var clusters: [String] = []
        var error: String?
    }

    @Published var newURL = ""
    @Published var newToken = ""
    @Published private(set) var formError: String?
    @Published private(set) var isAdding = false
    @Published private(set) var states: [String: ServerState] = [:]

    private let preferences: Preferences
    private let persistent: Bool

    init(preferences: Preferences, persistent: Bool = true) {
        self.preferences = preferences
        self.persistent = persistent
    }

    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundle = Bundle.main.bundleIdentifier ?? "io.github.recepysl.kubernetes-status"
        return base.appendingPathComponent(bundle, isDirectory: true).appendingPathComponent("rancher", isDirectory: true)
    }()

    var kubeconfigEntries: [String] {
        preferences.rancherServers.isEmpty ? [] : [Self.directory.path]
    }

    func preview(_ url: String, clusters: [String]) {
        states[url] = ServerState(clusters: clusters)
    }

    func add() async {
        guard let url = RancherEndpoint.normalize(newURL) else {
            formError = RancherError.invalidURL.localizedDescription
            return
        }
        let token = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            formError = "Paste an API token (token-xxxxx:…) from Rancher."
            return
        }
        isAdding = true
        defer { isAdding = false }
        do {
            let clusters = try await RancherClient(baseURL: url, token: token).clusters()
            try Keychain.set(token, account: url.absoluteString)
            if !preferences.rancherServers.contains(url.absoluteString) {
                preferences.rancherServers.append(url.absoluteString)
            }
            try write(url: url, token: token, clusters: clusters)
            newURL = ""
            newToken = ""
            formError = nil
            StatusMonitor.shared.refreshNow()
        } catch {
            formError = error.localizedDescription
        }
    }

    func remove(_ server: String) {
        Keychain.delete(account: server)
        if let url = URL(string: server) {
            try? FileManager.default.removeItem(at: file(for: url))
        }
        preferences.rancherServers.removeAll { $0 == server }
        states[server] = nil
        StatusMonitor.shared.refreshNow()
    }

    func sync() async {
        guard persistent else { return }
        for server in preferences.rancherServers {
            guard let url = URL(string: server) else { continue }
            guard let token = Keychain.get(account: server) else {
                states[server] = ServerState(error: "API token missing from the Keychain. Remove and add this server again.")
                continue
            }
            do {
                let clusters = try await RancherClient(baseURL: url, token: token).clusters()
                try write(url: url, token: token, clusters: clusters)
            } catch {
                states[server, default: ServerState()].error = error.localizedDescription
            }
        }
    }

    private func write(url: URL, token: String, clusters: [RancherCluster]) throws {
        let taken = Set(states.filter { $0.key != url.absoluteString }.flatMap(\.value.clusters))
        let entries = clusters.map { cluster -> RancherKubeconfig.Entry in
            let name = taken.contains(cluster.name) ? "\(cluster.name)@\(url.host ?? "rancher")" : cluster.name
            return RancherKubeconfig.Entry(context: name, clusterID: cluster.id)
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: Self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let target = file(for: url)
        let contents = Data(RancherKubeconfig.render(baseURL: url, token: token, entries: entries).utf8)
        if (try? Data(contentsOf: target)) != contents {
            try contents.write(to: target, options: .atomic)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        states[url.absoluteString] = ServerState(clusters: entries.map(\.context))
    }

    private func file(for url: URL) -> URL {
        let host = (url.host ?? "rancher") + (url.port.map { "-\($0)" } ?? "") + url.path.replacingOccurrences(of: "/", with: "-")
        let safe = host.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "-" }
        return Self.directory.appendingPathComponent(String(safe) + ".yaml")
    }
}

enum Keychain {
    private static let service = (Bundle.main.bundleIdentifier ?? "io.github.recepysl.kubernetes-status") + ".rancher"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query(account)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrLabel as String] = "Kubernetes Status — Rancher API token"
            let added = SecItemAdd(attributes as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    static func get(account: String) -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
            return "Couldn't save the token to the Keychain: \(message)"
        }
    }
}
