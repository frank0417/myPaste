import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @StateObject private var syncService = SyncService()
    @State private var store: ClipboardStore?
    @State private var showClearConfirm = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            HStack(spacing: 0) {
                ClipboardHistoryPane(store: store)
                    .frame(minWidth: 320)
                Divider()
                PreviewPane(store: store)
                    .frame(minWidth: 280, ideal: 340)
            }
        }
        .background(PasteTheme.backgroundGradient.ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SyncStatusBadge(status: syncService.status)
                Button {
                    appState.isMonitoringEnabled.toggle()
                    appState.savePreferences()
                    if appState.isMonitoringEnabled {
                        store?.startMonitoringIfNeeded()
                    } else {
                        store?.stopMonitoring()
                    }
                } label: {
                    Label(
                        appState.isMonitoringEnabled ? "监听中" : "已暂停",
                        systemImage: appState.isMonitoringEnabled ? "waveform.badge.mic" : "pause.circle"
                    )
                }
                .help(appState.isMonitoringEnabled ? "暂停剪贴板监听" : "恢复剪贴板监听")
            }
        }
        .searchable(text: $appState.searchQuery, prompt: "搜索已复制的一切…")
        .onAppear {
            if store == nil {
                let created = ClipboardStore(modelContext: modelContext, appState: appState)
                store = created
                created.startMonitoringIfNeeded()
            }
            syncService.startStatusHeartbeat()
            SeedData.ensureDemoBoards(in: modelContext)
        }
        .onChange(of: appState.requestClearHistory) { _, requested in
            if requested {
                showClearConfirm = true
                appState.requestClearHistory = false
            }
        }
        .alert("清空历史？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空（保留置顶）", role: .destructive) {
                store?.clearHistory(keepPinned: true)
            }
            Button("全部清空", role: .destructive) {
                store?.clearHistory(keepPinned: false)
            }
        } message: {
            Text("此操作无法撤销。置顶条目可选择保留。")
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Query(sort: \ClipboardBoard.sortOrder) private var boards: [ClipboardBoard]

    var body: some View {
        List {
            Section("资料库") {
                ForEach(AppState.ContentFilter.allCases) { filter in
                    Button {
                        appState.selectedFilter = filter
                        appState.showOnlyPinned = (filter == .pinned)
                    } label: {
                        Label(filter.title, systemImage: filter.systemImage)
                            .foregroundStyle(appState.selectedFilter == filter ? PasteTheme.accent : .primary)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        appState.selectedFilter == filter
                        ? PasteTheme.accent.opacity(0.12)
                        : Color.clear
                    )
                }
            }

            if !boards.isEmpty {
                Section("看板") {
                    ForEach(boards) { board in
                        Label(board.name, systemImage: "square.grid.2x2")
                            .foregroundStyle(Color(hex: board.colorHex) ?? PasteTheme.accent)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Paste")
    }
}

struct SyncStatusBadge: View {
    let status: SyncService.Status

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var color: Color {
        switch status {
        case .synced: return Color(hex: "#0D9488") ?? .green
        case .syncing: return Color(hex: "#F59E0B") ?? .orange
        case .error: return .red
        case .offline: return .gray
        case .idle: return .secondary
        }
    }
}

enum SeedData {
    static func ensureDemoBoards(in context: ModelContext) {
        let descriptor = FetchDescriptor<ClipboardBoard>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }
        let boards = [
            ClipboardBoard(name: "工作", sortOrder: 0, colorHex: "#0D9488"),
            ClipboardBoard(name: "灵感", sortOrder: 1, colorHex: "#EE6C4D"),
            ClipboardBoard(name: "代码片段", sortOrder: 2, colorHex: "#059669")
        ]
        boards.forEach { context.insert($0) }
        try? context.save()
    }
}
