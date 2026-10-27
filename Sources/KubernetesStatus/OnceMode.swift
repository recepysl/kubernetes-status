import Foundation
import KubeStatusKit

@MainActor
enum OnceMode {
    static func run() -> Never {
        let preferences = Preferences.shared
        let arguments = CommandLine.arguments
        var entries = preferences.kubeconfigEntries
        if let flag = arguments.firstIndex(of: "--kubeconfig"), arguments.indices.contains(flag + 1) {
            entries = [arguments[flag + 1]]
        }

        guard let executable = Kubectl.locate(override: preferences.kubectlPath) else {
            fail(KubectlError.notFound)
        }
        let kubectl = Kubectl(executable: executable, kubeconfigs: Kubectl.resolveKubeconfigs(entries))

        let contexts: [String]
        do {
            contexts = try kubectl.contexts()
        } catch {
            fail(error)
        }

        let watched = contexts.filter(preferences.isWatched).map { ($0, preferences.namespaces(for: $0)) }
        let results = ResultBox(count: watched.count)
        DispatchQueue.concurrentPerform(iterations: watched.count) { index in
            let (context, namespaces) = watched[index]
            results.set(index, kubectl.status(context: context, namespaces: namespaces))
        }
        let statuses = results.values

        for status in statuses {
            if let error = status.error {
                print("⚠ \(status.name)  unreachable — \(error)")
                continue
            }
            let mark = status.unhealthy.isEmpty ? "✓" : "✗"
            print("\(mark) \(status.name)  \(status.healthyCount)/\(status.pods.count) healthy")
            for pod in status.unhealthy {
                let restarts = pod.restarts > 0 ? "  restarts=\(pod.restarts)" : ""
                print("    \(pod.namespace)/\(pod.name)  \(pod.reason)\(restarts)")
            }
        }

        let summary = ClusterSummary(contexts: statuses)
        exit(summary.severity == .healthy ? 0 : 1)
    }

    private static func fail(_ error: Error) -> Never {
        FileHandle.standardError.write((error.localizedDescription + "\n").data(using: .utf8)!)
        exit(2)
    }
}

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ContextStatus?]

    init(count: Int) {
        storage = Array(repeating: nil, count: count)
    }

    func set(_ index: Int, _ status: ContextStatus) {
        lock.lock()
        storage[index] = status
        lock.unlock()
    }

    var values: [ContextStatus] {
        lock.lock()
        defer { lock.unlock() }
        return storage.compactMap { $0 }
    }
}
