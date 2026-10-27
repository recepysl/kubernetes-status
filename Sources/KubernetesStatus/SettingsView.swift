import SwiftUI
import AppKit

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(monitor: .shared, preferences: .shared, login: .shared))
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

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }
}
