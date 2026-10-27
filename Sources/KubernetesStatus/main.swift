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
} else {
    KubernetesStatusApp.main()
}
