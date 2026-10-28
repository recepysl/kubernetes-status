import SwiftUI
import AppKit
import KubeStatusKit

struct MenuBarLabel: View {
    @ObservedObject var monitor: StatusMonitor

    var body: some View {
        let summary = monitor.summary
        HStack(spacing: 3) {
            if !monitor.hasLoaded {
                Image(systemName: "steeringwheel")
            } else if monitor.setupError != nil {
                Image(systemName: "exclamationmark.triangle")
            } else {
                Image(systemName: "steeringwheel")
                if summary.unhealthyCount > 0 {
                    Text("\(summary.unhealthyCount)")
                } else if summary.unreachableCount > 0 {
                    Image(systemName: "bolt.horizontal.circle").imageScale(.small)
                }
            }
        }
        .foregroundStyle(monitor.setupError == nil ? summary.severity.color : .orange)
    }
}

struct MenuBarView: View {
    @ObservedObject var monitor: StatusMonitor
    @ObservedObject var preferences = Preferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 360)
    }

    private var header: some View {
        let summary = monitor.summary
        return HStack(spacing: 10) {
            Image(systemName: "steeringwheel")
                .font(.title2)
                .foregroundStyle(summary.severity.color)
            VStack(alignment: .leading, spacing: 1) {
                Text("Kubernetes Status").font(.system(size: 13, weight: .semibold))
                Text(subtitle(summary)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if monitor.hasLoaded && monitor.setupError == nil {
                badge(summary)
            }
        }
    }

    private func subtitle(_ summary: ClusterSummary) -> String {
        let contexts = summary.contexts.count
        return "\(contexts) context\(contexts == 1 ? "" : "s") · \(summary.podCount) pods"
    }

    private func badge(_ summary: ClusterSummary) -> some View {
        let text: String
        if summary.unhealthyCount > 0 {
            text = "\(summary.unhealthyCount) unhealthy"
        } else if summary.unreachableCount > 0 {
            text = "\(summary.unreachableCount) unreachable"
        } else {
            text = "All healthy"
        }
        let color = summary.severity.color
        return Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }

    @ViewBuilder
    private var content: some View {
        if let error = monitor.setupError {
            VStack(alignment: .leading, spacing: 10) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings…") { SettingsWindow.show() }
            }
        } else if !monitor.hasLoaded {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking clusters…").foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else if monitor.watchedStatuses.isEmpty {
            Text("No contexts are being watched. Choose some in Settings.")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(monitor.watchedStatuses) { status in
                    ContextRow(
                        status: status,
                        isCurrent: status.name == monitor.currentContext,
                        isExpanded: monitor.isExpanded(status.name),
                        toggle: { monitor.toggle(status.name) }
                    )
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(monitor.lastUpdated.map { "Updated \(Format.ago($0))" } ?? " ")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { monitor.refreshNow() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(monitor.isRefreshing)
            .help("Refresh now")
            Button { SettingsWindow.show() } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
    }
}

struct ContextRow: View {
    let status: ContextStatus
    let isCurrent: Bool
    let isExpanded: Bool
    let toggle: () -> Void

    private let visibleLimit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10)
                    Circle().fill(status.severity.color).frame(width: 7, height: 7)
                    Text(status.name)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                    if isCurrent {
                        Text("current")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    trailing
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                details.padding(.leading, 18)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var trailing: some View {
        if status.error != nil {
            Text("unreachable").font(.caption).foregroundStyle(.orange)
        } else {
            Text("\(status.healthyCount)/\(status.pods.count)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(status.unhealthy.isEmpty ? Color.secondary : status.severity.color)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info = status.info {
                ClusterInfoView(info: info)
            }
            podDetails
        }
    }

    @ViewBuilder
    private var podDetails: some View {
        if let error = status.error {
            Text(error)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        } else if status.unhealthy.isEmpty {
            Label(healthySummary, systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(status.unhealthy.prefix(visibleLimit)) { pod in
                    PodRow(pod: pod, context: status.name)
                }
                if status.unhealthy.count > visibleLimit {
                    Text("+ \(status.unhealthy.count - visibleLimit) more")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var healthySummary: String {
        let namespaces = Set(status.pods.map(\.namespace)).count
        let pods = "All \(status.pods.count) pod\(status.pods.count == 1 ? "" : "s") healthy"
        return namespaces > 1 ? "\(pods) across \(namespaces) namespaces" : pods
    }
}

struct ClusterInfoView: View {
    let info: ClusterInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !info.headline.isEmpty {
                Label(info.headline, systemImage: "server.rack")
                    .font(.caption)
                    .foregroundStyle(info.isActive ? Color.secondary : Color.orange)
                    .lineLimit(1)
            }
            if info.cpu != nil || info.memory != nil || info.pods != nil {
                HStack(spacing: 12) {
                    meter("CPU", info.cpu)
                    meter("Memory", info.memory)
                    meter("Pods", info.pods)
                }
                .help("Requested by pods, as a share of what the nodes can allocate")
            }
        }
    }

    @ViewBuilder
    private func meter(_ title: String, _ allocation: ClusterInfo.Allocation?) -> some View {
        if let fraction = allocation?.fraction {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 2) {
                    Text(title)
                    Spacer(minLength: 2)
                    Text("\(Int((fraction * 100).rounded()))%").monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(color(for: fraction))
                                .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 4 : 0))
                        }
                    }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func color(for fraction: Double) -> Color {
        if fraction >= 0.9 { return .red }
        if fraction >= 0.75 { return .orange }
        return .accentColor
    }
}

struct PodRow: View {
    let pod: PodStatus
    let context: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(pod.severity.color).frame(width: 6, height: 6).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(pod.name)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                Text(meta).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(pod.reason)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(pod.severity.color.opacity(0.15)))
                .foregroundStyle(pod.severity.color)
                .lineLimit(1)
            Button { TerminalActions.logs(pod, context: context) } label: {
                Image(systemName: "text.alignleft")
            }
            .buttonStyle(.borderless)
            .help("Follow logs in Terminal")
            Button { TerminalActions.describe(pod, context: context) } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("Describe in Terminal")
        }
        .contextMenu {
            Button("Copy Pod Name") { TerminalActions.copy(pod.name) }
            Button("Copy Namespace/Name") { TerminalActions.copy(pod.id) }
        }
    }

    private var meta: String {
        var parts = [pod.namespace, "\(pod.ready)/\(pod.total) ready"]
        if pod.restarts > 0 { parts.append("\(pod.restarts) restart\(pod.restarts == 1 ? "" : "s")") }
        if let age = Format.age(since: pod.createdAt) { parts.append(age) }
        return parts.joined(separator: " · ")
    }
}
