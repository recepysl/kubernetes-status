import SwiftUI
import AppKit

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(monitor: .shared, preferences: .shared, rancher: .shared, login: .shared))
            let newWindow = NSWindow(contentViewController: controller)
            newWindow.title = "Kubernetes Status Settings"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var monitor: StatusMonitor
    @ObservedObject var preferences: Preferences
    @ObservedObject var rancher: RancherAccounts
    @ObservedObject var login: LoginItem

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Kubeconfig") {
                TextEditor(text: $preferences.kubeconfigText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))
                Text("One file or folder per line. Folders include every .yaml and .yml file inside.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("kubectl").font(.callout)
                    TextField("Detected automatically", text: $preferences.kubectlPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    Button("Reload") { monitor.refreshNow() }
                }
            }

            section("Rancher") {
                if !preferences.rancherServers.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(preferences.rancherServers, id: \.self) { server in
                            rancherRow(server)
                        }
                    }
                }
                HStack {
                    TextField("https://rancher.example.com", text: $rancher.newURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    SecureField("token-xxxxx:…", text: $rancher.newToken)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 170)
                    Button(rancher.isAdding ? "Checking…" : "Add") {
                        Task { await rancher.add() }
                    }
                    .disabled(rancher.isAdding || rancher.newURL.isEmpty || rancher.newToken.isEmpty)
                }
                if let error = rancher.formError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Every cluster the API token can see is added as a context. Pods and cluster capacity come from Rancher, so only namespaces you have access to are listed — no cluster-wide permission needed. The token is kept in your Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("Contexts") {
                if monitor.contexts.isEmpty {
                    Text("No contexts found yet.").font(.callout).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(monitor.contexts, id: \.self) { context in
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { preferences.isWatched(context) },
                                    set: { preferences.setWatched(context, $0) }
                                )) {
                                    Text(context).font(.system(size: 12, design: .monospaced))
                                }
                                .toggleStyle(.checkbox)
                                Spacer()
                                TextField("all namespaces", text: Binding(
                                    get: { preferences.namespaceFilters[context] ?? "" },
                                    set: { preferences.namespaceFilters[context] = $0.isEmpty ? nil : $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 190)
                            }
                        }
                    }
                    Text("Limit a context to specific namespaces (comma-separated) when you can't list pods cluster-wide.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            section("General") {
                Picker("Refresh every", selection: $preferences.interval) {
                    ForEach(Preferences.intervals, id: \.self) { Text(Format.interval($0)).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Toggle("Notify when a pod starts failing", isOn: $preferences.notificationsEnabled)
                    .toggleStyle(.checkbox)
                Toggle("Open at Login", isOn: Binding(get: { login.isEnabled }, set: { login.setEnabled($0) }))
                    .toggleStyle(.checkbox)
                if let error = login.lastError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func rancherRow(_ server: String) -> some View {
        let state = rancher.states[server]
        return HStack(spacing: 8) {
            Image(systemName: "server.rack").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(string: server)?.host ?? server)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                if let error = state?.error {
                    Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2)
                } else if let clusters = state?.clusters {
                    Text("\(clusters.count) cluster\(clusters.count == 1 ? "" : "s"): \(clusters.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
            }
            Spacer()
            Button("Remove") { rancher.remove(server) }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }
}
