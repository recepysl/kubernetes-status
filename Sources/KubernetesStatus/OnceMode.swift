import Foundation
import KubeStatusKit

@MainActor
enum OnceMode {
    static func run() -> Never {
        Task { @MainActor in
            let arguments = CommandLine.arguments
            if let flag = arguments.firstIndex(of: "--kubeconfig"), arguments.indices.contains(flag + 1) {
                report(entries: [arguments[flag + 1]])
            }
            await RancherAccounts.shared.sync()
            report(entries: Preferences.shared.kubeconfigEntries + RancherAccounts.shared.kubeconfigEntries)
        }
        RunLoop.main.run()
        exit(2)
    }

    private static func report(entries: [String]) -> Never {
        let preferences = Preferences.shared

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

        let rancher = kubectl.rancherEndpoints()
        let watched = contexts.filter(preferences.isWatched).map { ($0, preferences.namespaces(for: $0)) }
        let results = ResultBox(count: watched.count)
        DispatchQueue.concurrentPerform(iterations: watched.count) { index in
            let (context, namespaces) = watched[index]
            guard let endpoint = rancher[context] else {
                results.set(index, kubectl.status(context: context, namespaces: namespaces))
                return
            }
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                let status = await RancherClient(endpoint: endpoint).status(context: context, clusterID: endpoint.clusterID, namespaces: namespaces)
                results.set(index, status)
                done.signal()
            }
            done.wait()
        }
        let statuses = results.values

        for status in statuses {
            if let error = status.error {
                print("⚠ \(status.name)  unreachable — \(error)")
                continue
            }
            let mark = status.unhealthy.isEmpty ? "✓" : "✗"
            print("\(mark) \(status.name)  \(status.healthyCount)/\(status.pods.count) healthy")
            if let info = status.info {
                print("    \(describe(info))")
            }
            for pod in status.unhealthy {
                let restarts = pod.restarts > 0 ? "  restarts=\(pod.restarts)" : ""
                print("    \(pod.namespace)/\(pod.name)  \(pod.reason)\(restarts)")
            }
        }

        let summary = ClusterSummary(contexts: statuses)
        exit(summary.severity == .healthy ? 0 : 1)
    }

    private static func describe(_ info: ClusterInfo) -> String {
        var parts = info.headline.isEmpty ? [] : [info.headline]
        for (title, allocation) in [("cpu", info.cpu), ("memory", info.memory), ("pods", info.pods)] {
            if let fraction = allocation?.fraction {
                parts.append("\(title) \(Int((fraction * 100).rounded()))%")
            }
        }
        return parts.joined(separator: " · ")
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
