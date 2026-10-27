import AppKit
import KubeStatusKit

enum TerminalActions {
    @MainActor
    static func logs(_ pod: PodStatus, context: String) {
        run(context: context, ["--namespace", pod.namespace, "logs", pod.name, "--all-containers", "--tail=200", "--follow"])
    }

    @MainActor
    static func describe(_ pod: PodStatus, context: String) {
        run(context: context, ["--namespace", pod.namespace, "describe", "pod", pod.name])
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @MainActor
    private static func run(context: String, _ arguments: [String]) {
        guard let kubectl = StatusMonitor.shared.kubectl() else { return }
        let command = [
            "export KUBECONFIG=\(quote(kubectl.kubeconfigs.joined(separator: ":")));",
            ([kubectl.executable.path, "--context", context] + arguments).map(quote).joined(separator: " "),
        ].joined(separator: " ")
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
