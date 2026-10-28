import AppKit
import SwiftUI
import KubeStatusKit

@MainActor
enum ScreenshotMode {
    static func run(outputPath: String) -> Never {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for theme in Theme.allCases {
                try write(HeroScene(monitor: DemoData.incident(), theme: theme), to: output, name: "hero", theme: theme)
                try write(StatesScene(theme: theme), to: output, name: "states", theme: theme)
                try write(SettingsScene(theme: theme), to: output, name: "settings", theme: theme)
                try write(MenuBarStripScene(theme: theme), to: output, name: "menubar", theme: theme)
            }
        } catch {
            FileHandle.standardError.write("✗ screenshot rendering failed: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
        print("✓ Rendered screenshots to \(output.path)")
        exit(0)
    }

    private static func write<V: View>(_ view: V, to directory: URL, name: String, theme: Theme) throws {
        let rep = snapshot(view, appearance: theme.appearance)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: directory.appendingPathComponent("\(name)-\(theme.rawValue).png"))
    }

    private static func snapshot<V: View>(_ view: V, appearance: NSAppearance, scale: CGFloat = 2) -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.display()

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }
}

enum Theme: String, CaseIterable {
    case light
    case dark

    var appearance: NSAppearance {
        NSAppearance(named: self == .light ? .aqua : .darkAqua)!
    }

    var backdrop: LinearGradient {
        switch self {
        case .light:
            return LinearGradient(
                colors: [Color(red: 0.78, green: 0.86, blue: 1.00), Color(red: 0.86, green: 0.95, blue: 0.98)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .dark:
            return LinearGradient(
                colors: [Color(red: 0.05, green: 0.10, blue: 0.24), Color(red: 0.06, green: 0.22, blue: 0.33)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    var menuBarFill: Color {
        self == .light ? Color.white.opacity(0.55) : Color.black.opacity(0.35)
    }
}

@MainActor
enum DemoData {
    static let now = Date()

    static func pod(
        _ name: String,
        _ namespace: String,
        _ reason: String,
        _ severity: Severity,
        ready: Int = 1,
        total: Int = 1,
        restarts: Int = 0,
        age: TimeInterval = 3 * 86_400
    ) -> PodStatus {
        PodStatus(
            name: name,
            namespace: namespace,
            reason: reason,
            ready: ready,
            total: total,
            restarts: restarts,
            createdAt: now.addingTimeInterval(-age),
            severity: severity
        )
    }

    static func healthy(_ count: Int, prefix: String) -> [PodStatus] {
        (0..<count).map { pod("\(prefix)-\($0)", "default", "Running", .healthy) }
    }

    static func incident() -> StatusMonitor {
        let production = ContextStatus(
            name: "prod-eu-west",
            pods: healthy(61, prefix: "svc") + [
                pod("checkout-api-7d9f8b6c5-x2kqp", "shop", "CrashLoopBackOff", .critical, ready: 0, restarts: 14, age: 2 * 3_600),
                pod("search-indexer-5c6d7f-9hj2k", "search", "Pending", .warning, ready: 0, age: 25 * 60),
            ],
            fetchedAt: now,
            info: ClusterInfo(
                provider: "eks",
                version: "v1.33.4",
                state: "active",
                nodeCount: 9,
                cpu: .init(requested: 41.6, allocatable: 70),
                memory: .init(requested: 182, allocatable: 236),
                pods: .init(requested: 63, allocatable: 990)
            )
        )
        return StatusMonitor(
            preview: [
                production,
                ContextStatus(name: "prod-us-east", pods: healthy(58, prefix: "svc"), fetchedAt: now),
                ContextStatus(name: "staging", pods: healthy(41, prefix: "svc"), fetchedAt: now),
                ContextStatus(name: "dev", pods: healthy(27, prefix: "svc"), fetchedAt: now),
                ContextStatus(name: "docker-desktop", pods: healthy(9, prefix: "local"), fetchedAt: now),
            ],
            currentContext: "staging",
            lastUpdated: now.addingTimeInterval(-8)
        )
    }

    static func allHealthy() -> StatusMonitor {
        StatusMonitor(
            preview: [
                ContextStatus(name: "prod-eu-west", pods: healthy(63, prefix: "svc"), fetchedAt: now),
                ContextStatus(name: "prod-us-east", pods: healthy(58, prefix: "svc"), fetchedAt: now),
                ContextStatus(name: "staging", pods: healthy(41, prefix: "svc"), fetchedAt: now),
            ],
            currentContext: "staging",
            lastUpdated: now.addingTimeInterval(-8)
        )
    }

    static func degraded() -> StatusMonitor {
        StatusMonitor(
            preview: [
                ContextStatus(name: "prod-eu-west", pods: healthy(63, prefix: "svc"), fetchedAt: now),
                ContextStatus(
                    name: "staging",
                    pods: healthy(38, prefix: "svc") + [
                        pod("worker-6f8d9c7b4-qp7tz", "jobs", "OOMKilled", .critical, ready: 0, restarts: 3, age: 50 * 60),
                        pod("payments-db-migrate-28h4k", "payments", "ImagePullBackOff", .critical, ready: 0, age: 12 * 60),
                        pod("frontend-84c9d5f6b-l8m2n", "web", "NotReady", .warning, ready: 1, total: 2, age: 9 * 60),
                    ],
                    fetchedAt: now
                ),
                ContextStatus(
                    name: "legacy-onprem",
                    pods: [],
                    error: "You must be logged in to the server (Unauthorized)",
                    fetchedAt: now
                ),
            ],
            currentContext: "staging",
            lastUpdated: now.addingTimeInterval(-8)
        )
    }

    static func unreachable() -> StatusMonitor {
        StatusMonitor(
            preview: [
                ContextStatus(name: "prod-eu-west", pods: healthy(63, prefix: "svc"), fetchedAt: now),
                ContextStatus(name: "vpn-only", pods: [], error: "Timed out talking to the cluster.", fetchedAt: now),
            ],
            lastUpdated: now.addingTimeInterval(-8)
        )
    }

    static func preferences() -> Preferences {
        let preferences = Preferences(defaults: UserDefaults(suiteName: "preview-\(UUID().uuidString)")!)
        preferences.kubeconfigText = "~/.kube/config\n~/clusters/"
        preferences.namespaceFilters = ["prod-eu-west": "shop, search"]
        preferences.disabledContexts = ["docker-desktop"]
        preferences.rancherServers = ["https://rancher.example.com"]
        return preferences
    }

    static func rancher(_ preferences: Preferences) -> RancherAccounts {
        let accounts = RancherAccounts(preferences: preferences, persistent: false)
        accounts.preview("https://rancher.example.com", clusters: ["prod-eu-west", "prod-us-east", "staging"])
        return accounts
    }
}

struct DropdownPanel: View {
    let monitor: StatusMonitor

    var body: some View {
        MenuBarView(monitor: monitor)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
    }
}

struct FakeMenuBar: View {
    let monitor: StatusMonitor
    let theme: Theme

    var body: some View {
        HStack(spacing: 18) {
            Spacer()
            MenuBarLabel(monitor: monitor)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.12)))
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Image(systemName: "magnifyingglass")
            Text("Tue 9:41")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .frame(height: 30)
        .background(theme.menuBarFill)
    }
}

struct AppIconView: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(red: 0.20, green: 0.45, blue: 0.95), Color(red: 0.06, green: 0.15, blue: 0.38)],
                startPoint: .top, endPoint: .bottom
            ))
            .overlay(
                Image(systemName: "steeringwheel")
                    .font(.system(size: size * 0.56, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
    }
}

struct HeroScene: View {
    let monitor: StatusMonitor
    let theme: Theme

    var body: some View {
        ZStack(alignment: .top) {
            theme.backdrop
            VStack(spacing: 0) {
                FakeMenuBar(monitor: monitor, theme: theme)
                HStack(alignment: .top) {
                    tagline
                        .padding(.leading, 64)
                        .padding(.top, 110)
                    Spacer()
                    DropdownPanel(monitor: monitor)
                        .padding(.trailing, 130)
                }
                .padding(.top, 8)
                Spacer(minLength: 0)
            }
        }
        .frame(width: 1040, height: 540)
    }

    private var tagline: some View {
        VStack(alignment: .leading, spacing: 18) {
            AppIconView(size: 88)
            Text("Kubernetes Status")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Every cluster's health,\nright in your menu bar.")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                pill("Native SwiftUI")
                pill("Any kubeconfig")
                pill("macOS 14+")
            }
            .padding(.top, 6)
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(theme.menuBarFill))
    }
}

struct StatesScene: View {
    let theme: Theme

    var body: some View {
        ZStack {
            theme.backdrop
            HStack(alignment: .top, spacing: 36) {
                caption("All clusters healthy", DemoData.allHealthy())
                caption("Pods failing, one cluster unreachable", DemoData.degraded())
            }
            .padding(48)
        }
        .fixedSize()
    }

    private func caption(_ title: String, _ monitor: StatusMonitor) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            DropdownPanel(monitor: monitor)
        }
    }
}

struct SettingsScene: View {
    let theme: Theme

    var body: some View {
        let monitor = DemoData.incident()
        let preferences = DemoData.preferences()
        ZStack {
            theme.backdrop
            SettingsView(monitor: monitor, preferences: preferences, rancher: DemoData.rancher(preferences), login: .shared)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                .padding(48)
        }
        .fixedSize()
    }
}

struct MenuBarStripScene: View {
    let theme: Theme

    var body: some View {
        ZStack {
            theme.backdrop
            HStack(spacing: 28) {
                chip(DemoData.allHealthy())
                chip(DemoData.unreachable())
                chip(DemoData.incident())
                chip(DemoData.degraded())
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 22)
        }
        .fixedSize()
    }

    private func chip(_ monitor: StatusMonitor) -> some View {
        MenuBarLabel(monitor: monitor)
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(theme.menuBarFill))
    }
}
