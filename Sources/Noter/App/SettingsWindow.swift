// ABOUTME: The Settings window: a titled macOS window holding one grouped form of preferences.
// ABOUTME: Kept as a single instance; opening it brings the accessory app forward.

import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: Settings
    @Bindable var loginItem: LoginItem
    @Bindable var updater: UpdaterController
    @State private var apiKey = ""
    /// Checked once per window, since it probes the disk and the keychain.
    @State private var availability: [Enricher.Tool: Bool] = Dictionary(
        uniqueKeysWithValues: Enricher.Tool.allCases.map { ($0, $0.isAvailable) }
    )

    private func saveKey() {
        guard let provider = settings.enricherTool.provider else { return }
        APIKey.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: provider)
        availability[settings.enricherTool] = APIKey.load(provider) != nil
    }

    private func loadKey() {
        apiKey = settings.enricherTool.provider.flatMap(APIKey.stored) ?? ""
    }

    private var keyStatus: String {
        guard let provider = settings.enricherTool.provider else { return "" }
        if APIKey.stored(provider) != nil { return "Key stored in your login keychain." }
        if APIKey.fromEnvironment(provider) != nil {
            return "Using \(provider.environmentVariables[0]) from the environment. Paste a key and press Return to store one instead."
        }
        return "No key found. Paste one and press Return; it goes into your login keychain. \(provider.environmentVariables[0]) is also read when Noter starts from a terminal."
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $loginItem.isEnabled)
                Picker("Window level", selection: $settings.windowLevel) {
                    Text("On the desktop, under app windows").tag(WindowLevelChoice.desktop)
                    Text("Above app windows").tag(WindowLevelChoice.floating)
                }
            }
            Section("Rail") {
                Picker("Screen edge", selection: $settings.railSide) {
                    Text("Left").tag(RailSide.left)
                    Text("Right").tag(RailSide.right)
                }
                .pickerStyle(.segmented)
                Stepper("Dots before scrolling: \(settings.visibleDots)", value: $settings.visibleDots, in: Settings.dotRange)
            }
            Section("Summaries") {
                Picker("Written by", selection: $settings.enricherTool) {
                    ForEach(Enricher.Tool.allCases) { tool in
                        Text(tool.binary != nil && availability[tool] == false ? "\(tool.label) (not installed)" : tool.label).tag(tool)
                    }
                }
                .onChange(of: settings.enricherTool) { _, tool in
                    if !tool.models.contains(settings.enricherModel) { settings.enricherModel = "" }
                    loadKey()
                }
                .onAppear(perform: loadKey)
                HStack {
                    TextField("Model", text: $settings.enricherModel, prompt: Text(settings.enricherTool.defaultModel))
                    Menu {
                        ForEach(settings.enricherTool.models, id: \.self) { model in
                            Button(model) { settings.enricherModel = model }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                if settings.enricherTool.provider != nil {
                    SecureField("API key", text: $apiKey)
                        .onSubmit(saveKey)
                    Text(keyStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Runs the chosen command-line tool on this Mac with its own login. No key is stored in Noter.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section("About") {
                HStack(spacing: 12) {
                    Image(nsImage: AppIcon.artwork())
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Noter").font(.headline)
                        Text(AppInfo().label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Sticky notes at the edge of your screen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                Button("Check for Updates\u{2026}") { updater.checkForUpdates() }
                Link("hexul.com", destination: URL(string: "https://hexul.com")!)
                    .font(.caption)
                Text("\u{00A9} hexul")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// While Settings is open the app joins the Dock with its icon, so it behaves like a normal window;
/// on close it goes back to being a menu-bar-only accessory.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(settings: Settings, loginItem: LoginItem, updater: UpdaterController) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(settings: settings, loginItem: loginItem, updater: updater))
            let window = NSWindow(contentViewController: host)
            window.title = "Noter Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
