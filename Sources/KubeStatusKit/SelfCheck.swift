import Foundation

public enum SelfCheck {
    public static func run() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
            if !condition { failures.append(message()) }
        }

        let now = PodClassifier.parseDate("2026-10-27T12:00:00Z")!
        do {
            let pods = try PodClassifier.decode(samplePods, now: now)
            let byName = Dictionary(uniqueKeysWithValues: pods.map { ($0.name, $0) })
            expect(pods.count == 9, "terminating pod should be skipped, got \(pods.count) pods")
            expect(byName["web-1"]?.severity == .healthy, "running and ready is healthy")
            expect(byName["web-1"]?.reason == "Running", "running reason")
            expect(byName["api-1"]?.severity == .critical, "CrashLoopBackOff is critical")
            expect(byName["api-1"]?.reason == "CrashLoopBackOff", "CrashLoopBackOff reason")
            expect(byName["api-1"]?.restarts == 14, "restart count summed, got \(byName["api-1"]?.restarts as Any)")
            expect(byName["api-1"]?.ready == 0 && byName["api-1"]?.total == 1, "ready/total for api-1")
            expect(byName["job-ok"]?.severity == .healthy, "succeeded pod is healthy")
            expect(byName["job-failed"]?.severity == .warning, "failed Job pod is a warning")
            expect(byName["evicted"]?.reason == "Evicted" && byName["evicted"]?.severity == .warning, "evicted pod is a warning")
            expect(byName["pending-old"]?.severity == .warning, "old pending pod is a warning")
            expect(byName["pending-new"]?.severity == .healthy, "pending pod within grace is healthy")
            expect(byName["init-pull"]?.reason == "ImagePullBackOff", "init container pull failure surfaces")
            expect(byName["init-pull"]?.severity == .critical, "init pull failure is critical")
            expect(byName["oom"]?.reason == "OOMKilled" && byName["oom"]?.severity == .critical, "OOMKilled is critical")

            let context = ContextStatus(name: "prod", pods: pods)
            expect(context.severity == .critical, "context severity is the worst pod")
            expect(context.unhealthy.first?.severity == .critical, "unhealthy pods are sorted by severity")
            expect(context.healthyCount == 3, "healthy count should be 3, got \(context.healthyCount)")

            let calm = ContextStatus(name: "prod", pods: pods.filter { $0.severity != .critical })
            let fresh = PodTransitions.newlyFailing(previous: calm, current: context)
            expect(Set(fresh.map(\.name)) == ["api-1", "init-pull", "oom"], "newly failing pods detected: \(fresh.map(\.name))")
            expect(PodTransitions.newlyFailing(previous: context, current: context).isEmpty, "no repeat for already failing pods")
            expect(PodTransitions.newlyFailing(previous: nil, current: context).isEmpty, "no alerts on the first snapshot")

            let summary = ClusterSummary(contexts: [context, ContextStatus(name: "dev", pods: [], error: "Unauthorized")])
            expect(summary.unreachableCount == 1, "one unreachable context")
            expect(summary.podCount == 9, "summary pod count")
            expect(summary.severity == .critical, "summary severity")
        } catch {
            failures.append("decoding sample pods threw: \(error)")
        }

        let noisy = """
        E1026 12:25:04.128431   32532 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list"
        error: You must be logged in to the server (Unauthorized)
        """
        expect(Kubectl.summarize(Data(noisy.utf8)) == "You must be logged in to the server (Unauthorized)",
               "error summary should keep the last meaningful line, got \(Kubectl.summarize(Data(noisy.utf8)))")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kube-status-selfcheck-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for name in ["b.yaml", "a.yml", "notes.txt"] {
                try Data().write(to: directory.appendingPathComponent(name))
            }
            let resolved = Kubectl.resolveKubeconfigs([directory.path, " ", directory.appendingPathComponent("a.yml").path, "/nonexistent/config"])
            expect(resolved.map { ($0 as NSString).lastPathComponent } == ["a.yml", "b.yaml"],
                   "folders expand to sorted yaml files without duplicates, got \(resolved)")
            try? FileManager.default.removeItem(at: directory)
        } catch {
            failures.append("kubeconfig resolution setup threw: \(error)")
        }

        return failures
    }

    static let samplePods = Data("""
    { "items": [
      { "metadata": { "name": "web-1", "namespace": "shop", "creationTimestamp": "2026-10-20T09:00:00Z" },
        "spec": { "containers": [ { "name": "web" }, { "name": "proxy" } ] },
        "status": { "phase": "Running", "containerStatuses": [
          { "ready": true, "restartCount": 0, "state": { "running": {} } },
          { "ready": true, "restartCount": 1, "state": { "running": {} } } ] } },
      { "metadata": { "name": "api-1", "namespace": "shop", "creationTimestamp": "2026-10-27T08:00:00Z" },
        "spec": { "containers": [ { "name": "api" } ] },
        "status": { "phase": "Running", "containerStatuses": [
          { "ready": false, "restartCount": 14, "state": { "waiting": { "reason": "CrashLoopBackOff" } } } ] } },
      { "metadata": { "name": "job-ok", "namespace": "batch", "ownerReferences": [ { "kind": "Job" } ] },
        "status": { "phase": "Succeeded" } },
      { "metadata": { "name": "job-failed", "namespace": "batch", "ownerReferences": [ { "kind": "Job" } ] },
        "status": { "phase": "Failed" } },
      { "metadata": { "name": "evicted", "namespace": "shop" },
        "status": { "phase": "Failed", "reason": "Evicted" } },
      { "metadata": { "name": "pending-old", "namespace": "search", "creationTimestamp": "2026-10-27T10:00:00Z" },
        "spec": { "containers": [ { "name": "indexer" } ] },
        "status": { "phase": "Pending" } },
      { "metadata": { "name": "pending-new", "namespace": "search", "creationTimestamp": "2026-10-27T11:58:00Z" },
        "spec": { "containers": [ { "name": "indexer" } ] },
        "status": { "phase": "Pending", "containerStatuses": [
          { "ready": false, "restartCount": 0, "state": { "waiting": { "reason": "ContainerCreating" } } } ] } },
      { "metadata": { "name": "init-pull", "namespace": "shop", "creationTimestamp": "2026-10-27T11:59:00Z" },
        "spec": { "containers": [ { "name": "app" } ] },
        "status": { "phase": "Pending",
          "initContainerStatuses": [ { "ready": false, "restartCount": 0, "state": { "waiting": { "reason": "ImagePullBackOff" } } } ] } },
      { "metadata": { "name": "oom", "namespace": "shop", "creationTimestamp": "2026-10-27T11:00:00Z" },
        "spec": { "containers": [ { "name": "worker" } ] },
        "status": { "phase": "Running", "containerStatuses": [
          { "ready": false, "restartCount": 3, "state": { "terminated": { "reason": "OOMKilled" } } } ] } },
      { "metadata": { "name": "leaving", "namespace": "shop", "deletionTimestamp": "2026-10-27T12:01:00Z" },
        "status": { "phase": "Running" } }
    ] }
    """.utf8)
}
