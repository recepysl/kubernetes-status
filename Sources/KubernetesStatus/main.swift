import Foundation
import KubeStatusKit

if CommandLine.arguments.contains("--selftest") {
    let failures = SelfCheck.run()
    if failures.isEmpty {
        print("✓ selftest passed")
        exit(0)
    }
    FileHandle.standardError.write(("✗ selftest failed:\n" + failures.joined(separator: "\n") + "\n").data(using: .utf8)!)
    exit(1)
} else if let flag = CommandLine.arguments.firstIndex(of: "--render-screenshots") {
    let next = CommandLine.arguments.index(after: flag)
    let output = next < CommandLine.arguments.endIndex ? CommandLine.arguments[next] : "docs/images"
    MainActor.assumeIsolated { ScreenshotMode.run(outputPath: output) }
} else if CommandLine.arguments.contains("--once") {
    MainActor.assumeIsolated { OnceMode.run() }
} else {
    KubernetesStatusApp.main()
}
