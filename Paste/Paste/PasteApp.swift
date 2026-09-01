import SwiftUI
import SwiftData

@main
struct PasteApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([ClipboardItem.self, ClipboardBoard.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: [local])
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        MenuBarExtra("Paste", systemImage: "doc.on.clipboard") {
            MenuBarPanel()
                .environmentObject(appState)
                .modelContainer(sharedModelContainer)
                .frame(width: 420, height: 560)
        }
        .menuBarExtraStyle(.window)

        Window("Paste", id: "main") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 880, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Clipboard") {
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        GlobalHotKeyManager.shared.onHotKey = {
            NSApp.activate(ignoringOtherApps: true)
            // Prefer revealing an existing Paste window; MenuBarExtra also stays available.
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "Paste" }) {
                NSApp.setActivationPolicy(.regular)
                window.makeKeyAndOrderFront(nil)
            }
        }
        GlobalHotKeyManager.shared.registerDefault()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openMainWindow()
        }
        return true
    }

    private func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            for window in NSApp.windows where window.title == "Paste" {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
    }
}
