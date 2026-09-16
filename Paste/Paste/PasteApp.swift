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

        // Optional main window — closing it must NOT quit the agent app.
        Window("PasteNest", id: "main") {
            ContentView()
                .environmentObject(appState)
                .modelContainer(sharedModelContainer)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 880, height: 600)

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
    private var retentionObserver: NSObjectProtocol?
    private var didInstallStatusItem = false
    private var didPrepareSearchIndex = false
    private weak var appState: AppState?

    @MainActor
    func configure(container: ModelContainer, appState: AppState) {
        self.appState = appState
        if clipboardStore == nil {
            let store = ClipboardStore(modelContext: container.mainContext, appState: appState, ownsMonitor: true)
            clipboardStore = store
            store.startMonitoringIfNeeded()
            // Items that expired while the app was closed go away on launch, so the
            // history never shows records the policy already dropped.
            store.enforceRetention()
            // Screenshots bypass the pasteboard poll, so file them through the same
            // store that owns monitoring — otherwise they land twice or not at all.
            ScreenshotService.shared.onCaptured = { [weak self] payload in
                self?.clipboardStore?.ingest(payload)
            }
            ScreenshotService.shared.onRecognized = { [weak self] hash, text in
                self?.clipboardStore?.attachRecognizedText(text, toContentHash: hash)
            }
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
            retentionObserver = NotificationCenter.default.addObserver(
                forName: .pasteRetentionSweepRequested,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                let delegate = self
                Task { @MainActor in
                    delegate?.clipboardStore?.enforceRetention()
                }
            }
            AutoTagService.backfillIfNeeded(in: container.mainContext)
            store.scheduleImageCompaction()
        }

        if !didInstallStatusItem {
            didInstallStatusItem = true
            StatusItemController.shared.install(container: container, appState: appState)
        }

        if !didPrepareSearchIndex {
            didPrepareSearchIndex = true
            EmbeddingIndex.shared.onDidUpdate = { [weak appState] in
                guard let appState else { return }
                appState.embeddingRevision += 1
            }
            EmbeddingIndex.shared.prepare()
            // Do not fetch the whole history here: that materializes every screenshot
            // blob on the main context before the user has even opened the shelf.
            // The panel / main window backfill once they actually load items.
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar agent: no Dock icon. Closing the shelf only hides UI.
        NSApp.setActivationPolicy(.accessory)

        GlobalHotKeyManager.shared.onHotKey = { action in
            switch action {
            case .panel:
                StatusItemController.shared.togglePanel()
            case .mainWindow:
                StatusItemController.shared.toggleMainWindow()
            case .screenshot:
                ScreenshotService.shared.capture(.region)
            }
        }
        // Bind right away so the hotkeys work even before the scene hands us AppState,
        // then sync AppState (which reports a fallback if a combo was taken).
        for action in HotKeyAction.allCases {
            GlobalHotKeyManager.shared.apply(HotKeyShortcut.load(action), for: action)
        }
        Task { @MainActor [weak self] in
            self?.appState?.registerStoredHotkeys()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Critical: keep running in the background after the panel/main window is closed.
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        StatusItemController.shared.showPanel()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKeyManager.shared.unregister()
    }
}
