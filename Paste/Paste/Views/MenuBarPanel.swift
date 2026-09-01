import SwiftUI
import SwiftData

struct MenuBarPanel: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \ClipboardItem.updatedAt, order: .reverse) private var items: [ClipboardItem]
    @State private var store: ClipboardStore?
    @FocusState private var searchFocused: Bool

    private var filtered: [ClipboardItem] {
        let q = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            guard !q.isEmpty else { return true }
            let hay = [item.previewTitle, item.plainText, item.sourceAppName]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            return hay.contains(q)
        }
        .prefix(40)
        .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(PasteTheme.accent)
                    Text(appState.searchQuery.isEmpty ? "复制任意文本后会出现在这里\n（菜单栏图标或 ⇧⌘V 打开本面板）" : "无搜索结果")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(selection: $appState.selectedItemID) {
                    ForEach(filtered) { item in
                        ClipboardItemRow(
                            item: item,
                            isSelected: appState.selectedItemID == item.id,
                            onSelect: { appState.selectedItemID = item.id },
                            onPaste: { store?.paste(item) },
                            onPin: { store?.togglePin(item) },
                            onDelete: { store?.delete(item) }
                        )
                        .tag(item.id)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            Divider()
            footer
        }
        .background(PasteTheme.backgroundGradient)
        .onAppear {
            if store == nil {
                // UI-only store: must NOT own the monitor callback (AppDelegate owns it).
                store = ClipboardStore(modelContext: modelContext, appState: appState, ownsMonitor: false)
            }
            searchFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Paste")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PasteTheme.ink)

            Spacer()

            TextField("搜索…", text: $appState.searchQuery)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(maxWidth: 220)
                .focused($searchFocused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            Button {
                NSApp.setActivationPolicy(.regular)
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("打开主窗口", systemImage: "macwindow")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isMonitoringEnabled ? Color.green.opacity(0.85) : Color.orange.opacity(0.85))
                    .frame(width: 7, height: 7)
                Text(appState.isMonitoringEnabled ? "监听中" : "已暂停")
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(appState.hotkeyDisplay)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .font(.caption)
    }
}
