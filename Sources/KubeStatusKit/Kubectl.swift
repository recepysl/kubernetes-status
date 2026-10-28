import Foundation

public enum KubectlError: Error, LocalizedError, Equatable {
    case notFound
    case noKubeconfig
    case failed(String)
    case timedOut
    case decode(String)

    public var errorDescription: String? {
        switch self {
        case .notFound: return "kubectl was not found. Install it (e.g. `brew install kubectl`) or set its path in Settings."
        case .noKubeconfig: return "No kubeconfig found. Add a file or folder in Settings."
        case .failed(let message): return message
        case .timedOut: return "Timed out talking to the cluster."
        case .decode(let message): return "Unexpected kubectl output: \(message)"
        }
    }
}

public struct Kubectl: Sendable {
    public let executable: URL
    public let kubeconfigs: [String]
    public let timeout: TimeInterval

    public init(executable: URL, kubeconfigs: [String], timeout: TimeInterval = 20) {
        self.executable = executable
        self.kubeconfigs = kubeconfigs
        self.timeout = timeout
    }

    public static let searchDirectories: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "~/.rd/bin",
        "~/.local/bin",
        "~/bin",
        "/usr/bin",
        "/bin",
    ]

    public static func locate(override: String? = nil) -> URL? {
        let fileManager = FileManager.default
        if let override, !override.isEmpty {
            let path = expandTilde(override)
            return fileManager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for directory in searchDirectories.map(expandTilde) + pathEntries {
            let candidate = (directory as NSString).appendingPathComponent("kubectl")
            if fileManager.isExecutableFile(atPath: candidate) { return URL(fileURLWithPath: candidate) }
        }
        return nil
    }

    public static func resolveKubeconfigs(_ entries: [String]) -> [String] {
        let fileManager = FileManager.default
        var result: [String] = []
        for entry in entries {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let path = expandTilde(trimmed)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let names = (try? fileManager.contentsOfDirectory(atPath: path)) ?? []
                result += names
                    .filter { $0.hasSuffix(".yaml") || $0.hasSuffix(".yml") || $0 == "config" }
                    .sorted()
                    .map { (path as NSString).appendingPathComponent($0) }
            } else {
                result.append(path)
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    public static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    public func contexts() throws -> [String] {
        let output = try run(["config", "get-contexts", "-o", "name"])
        return String(decoding: output, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public func currentContext() -> String? {
        guard let output = try? run(["config", "current-context"]) else { return nil }
        let name = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    public func rancherEndpoints() -> [String: RancherEndpoint] {
        guard let output = try? run(["config", "view", "--raw", "--output", "json"]) else { return [:] }
        return KubeconfigView.rancherEndpoints(from: output)
    }

    public func status(context: String, namespaces: [String], now: Date = Date()) -> ContextStatus {
        do {
            let pods = try self.pods(context: context, namespaces: namespaces, now: now)
            return ContextStatus(name: context, pods: pods, fetchedAt: now)
        } catch {
            return ContextStatus(name: context, pods: [], error: error.localizedDescription, fetchedAt: now)
        }
    }

    public func pods(context: String, namespaces: [String], now: Date = Date()) throws -> [PodStatus] {
        if namespaces.isEmpty {
            do {
                return try podList(context: context, scope: ["--all-namespaces"], now: now)
            } catch KubectlError.failed(let message) where message.localizedCaseInsensitiveContains("forbidden") {
                let fallback = defaultNamespace(context: context)
                return try podList(context: context, scope: ["--namespace", fallback], now: now)
            }
        }
        return try namespaces.flatMap { try podList(context: context, scope: ["--namespace", $0], now: now) }
    }

    private func podList(context: String, scope: [String], now: Date) throws -> [PodStatus] {
        let output = try run(["--context", context, "get", "pods"] + scope + ["--output", "json"])
        do {
            return try PodClassifier.decode(output, now: now)
        } catch {
            throw KubectlError.decode(error.localizedDescription)
        }
    }

    private func defaultNamespace(context: String) -> String {
        let jsonPath = "{.contexts[?(@.name==\"\(context)\")].context.namespace}"
        guard let output = try? run(["config", "view", "--output", "jsonpath=\(jsonPath)"]) else { return "default" }
        let namespace = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return namespace.isEmpty ? "default" : namespace
    }

    public func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["KUBECONFIG"] = kubeconfigs.joined(separator: ":")
        let extra = Self.searchDirectories.map(Self.expandTilde)
        let existing = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        environment["PATH"] = (existing + extra).filter { seen.insert($0).inserted }.joined(separator: ":")
        return environment
    }

    func run(_ arguments: [String]) throws -> Data {
        guard !kubeconfigs.isEmpty else { throw KubectlError.noKubeconfig }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments + ["--request-timeout=\(Int(timeout))s"]
        process.environment = environment()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw KubectlError.notFound
        }

        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 5, execute: watchdog)

        let errorOutput = OutputBuffer()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errorOutput.data = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        watchdog.cancel()

        if process.terminationReason == .uncaughtSignal {
            throw KubectlError.timedOut
        }
        guard process.terminationStatus == 0 else {
            throw KubectlError.failed(Self.summarize(errorOutput.data))
        }
        return output
    }

    static func summarize(_ data: Data) -> String {
        let lines = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard var line = lines.last(where: { !$0.contains("memcache.go") }) ?? lines.last else {
            return "kubectl failed without an error message."
        }
        if line.hasPrefix("error: ") { line.removeFirst("error: ".count) }
        return line.count > 240 ? String(line.prefix(240)) + "…" : line
    }
}

private final class OutputBuffer: @unchecked Sendable {
    var data = Data()
}
