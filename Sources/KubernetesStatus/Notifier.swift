import Foundation
import UserNotifications
import KubeStatusKit

@MainActor
final class Notifier {
    static let shared = Notifier()

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(_ pods: [PodStatus], context: String) {
        guard let center, !pods.isEmpty else { return }
        let content = UNMutableNotificationContent()
        if pods.count == 1, let pod = pods.first {
            content.title = "\(pod.name) is failing"
            content.body = "\(context) · \(pod.namespace) — \(pod.reason)"
        } else {
            content.title = "\(pods.count) pods are failing in \(context)"
            content.body = pods.prefix(3).map { "\($0.name) — \($0.reason)" }.joined(separator: "\n")
        }
        content.sound = .default
        let identifier = "\(context)|\(pods.map(\.id).sorted().joined(separator: ","))"
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
}
