import SwiftUI
import SwiftData
import AppKit

@main
struct PasteApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([ClipboardItem.self, ClipboardBoard.self])
        // Local store first. CloudKit needs a team + iCloud entitlements;
        // unsigned CI builds must not depend on it for history to persist.
        let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [local])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        let _ = appDelegate.configure(container: sharedModelContainer, appState: appState)

        // Main history window (opened from the status-item panel).
        Window("Paste", id: "main") {
            ContentView()
                .environmentObject(appState)
                .modelContainer(sharedModelContainer)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 880, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Clipboard") {
                Button("Show Clipboard Panel") {
                    StatusItemController.shared.togglePanel()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Button("Clear History…") {
                    appState.requestClearHistory = true
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Pin Selected") {
                    appState.requestPinSelected = true
                }
                .keyboardShortcut("p", modifiers: [.command])

                Button("Export JSON…") {
                    appState.requestExportJSON = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .modelContainer(sharedModelContainer)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var clipboardStore: ClipboardStore?
    private var monitoringObserver: NSObjectProtocol?
    private var didInstallStatusItem = false

    @MainActor
    func configure(container: ModelContainer, appState: AppState) {
        if clipboardStore == nil {
            let store = ClipboardStore(modelContext: container.mainContext, appState: appState, ownsMonitor: true)
            clipboardStore = store
            store.startMonitoringIfNeeded()
            monitoringObserver = NotificationCenter.default.addObserver(
                forName: .pasteMonitoringPreferenceChanged,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let enabled = (note.userInfo?["enabled"] as? Bool) ?? true
                let delegate = self
                Task { @MainActor in
                    if enabled {
                        delegate?.clipboardStore?.startMonitoringIfNeeded()
                    } else {
                        delegate?.clipboardStore?.stopMonitoring()
                    }
                }
            }
        }

        if !didInstallStatusItem {
            didInstallStatusItem = true
            StatusItemController.shared.install(container: container, appState: appState)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        GlobalHotKeyManager.shared.onHotKey = {
            // Always toggle the floating clipboard panel — do not require an open main window.
            StatusItemController.shared.togglePanel()
        }
        GlobalHotKeyManager.shared.registerDefault()

        // Ensure status item exists even if SwiftUI body configure was delayed.
        // (configure() from body usually runs first.)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        StatusItemController.shared.showPanel()
        return true
    }
}
