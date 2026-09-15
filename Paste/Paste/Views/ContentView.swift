import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers


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
                    .frame(minWidth: 280, idealWidth: 340)
            }
        }
        .background(PasteTheme.backgroundGradient.ignoresSafeArea())
        .background(MainWindowAccessor())
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SyncStatusBadge(status: syncService.status)
                Menu {
                    ForEach(ScreenshotMode.allCases) { mode in
                        Button {
                            ScreenshotService.shared.capture(mode)
                        } label: {
                            Label(mode.title, systemImage: mode.systemImage)
                        }
                    }
                } label: {
                    Label("截图", systemImage: "camera.viewfinder")
                } primaryAction: {
                    ScreenshotService.shared.capture(.region)
                }
                .help("截图（\(appState.screenshotHotkeyDisplay)）— 结果自动存入历史")
                Button {
                    appState.isMonitoringEnabled.toggle()
                    appState.savePreferences()
                    NotificationCenter.default.post(
                        name: .pasteMonitoringPreferenceChanged,
                        object: nil,
                        userInfo: ["enabled": appState.isMonitoringEnabled]
                    )
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
                // UI-only store — AppDelegate owns pasteboard monitoring.
                store = ClipboardStore(modelContext: modelContext, appState: appState, ownsMonitor: false)
            }
            syncService.startStatusHeartbeat()
            SeedData.ensureDemoContent(in: modelContext)
        }
        .onChange(of: appState.requestClearHistory) { _, requested in
            if requested {
                showClearConfirm = true
                appState.requestClearHistory = false
            }
        }
        .onChange(of: appState.requestPinSelected) { _, requested in
            if requested {
                if let id = appState.selectedItemID {
                    // Pin is handled via store when row/action is available; flag consumed here.
                    _ = id
                }
                appState.requestPinSelected = false
            }
        }
        .onChange(of: appState.requestExportJSON) { _, requested in
            if requested {
                exportHistory()
                appState.requestExportJSON = false
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

    private func exportHistory() {
        guard let data = store?.exportJSON() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PasteNest-History.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
            syncService.markSyncing()
        }
    }
}

/// Hands the hosting window to `StatusItemController`, which shows the main window and
/// the floating shelf exclusively.
private struct MainWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                StatusItemController.shared.registerMainWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        StatusItemController.shared.registerMainWindow(window)
    }
}

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Query(sort: \ClipboardBoard.sortOrder) private var boards: [ClipboardBoard]
    @Query(
        filter: #Predicate<ClipboardItem> { $0.isFavorite },
        sort: \ClipboardItem.updatedAt,
        order: .reverse
    ) private var favorites: [ClipboardItem]

    var body: some View {
        List {
            Section("收藏夹") {
                Button {
                    appState.mainHistoryMode = .favorites
                    appState.showFavorites(scope: .all)
                } label: {
                    HStack {
                        Label("全部收藏", systemImage: "star.fill")
                            .foregroundStyle(
                                appState.mainHistoryMode == .favorites && appState.favoriteScope == .all
                                ? PasteTheme.accent
                                : .primary
                            )
                        Spacer()
                        Text("\(favorites.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                ForEach(favorites.favoriteTagCounts) { tag in
                    Button {
                        appState.mainHistoryMode = .favorites
                        appState.showFavorites(scope: .tag(tag.name))
                    } label: {
                        HStack {
                            Label(tag.name, systemImage: "tag.fill")
                                .foregroundStyle(
                                    appState.mainHistoryMode == .favorites
                                    && appState.favoriteScope == .tag(tag.name)
                                    ? (Color(hex: tag.accentHex) ?? PasteTheme.accent)
                                    : .primary
                                )
                            Spacer()
                            Text("\(tag.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Text("收藏的内容长期保存，未收藏的只保留 \(appState.keepUnfavoritedDays) 天。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("自动标签") {
                ForEach(AutoTag.allCases) { tag in
                    Button {
                        appState.selectedAutoTag = tag.rawValue
                        appState.selectedFilter = .all
                        appState.showOnlyPinned = false
                        appState.leaveFavorites()
                        if appState.mainHistoryMode == .favorites {
                            appState.mainHistoryMode = .list
                        }
                    } label: {
                        Label(tag.displayName, systemImage: tag.systemImage)
                            .foregroundStyle(
                                appState.selectedAutoTag == tag.rawValue
                                ? (Color(hex: tag.accentHex) ?? PasteTheme.accent)
                                : .primary
                            )
                    }
                    .buttonStyle(.plain)
                }
                if appState.selectedAutoTag != nil {
                    Button("清除标签筛选") {
                        appState.selectedAutoTag = nil
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("视图") {
                Button {
                    appState.mainHistoryMode = .list
                    appState.leaveFavorites()
                } label: {
                    Label("列表", systemImage: "list.bullet")
                        .foregroundStyle(appState.mainHistoryMode == .list ? PasteTheme.accent : .primary)
                }
                .buttonStyle(.plain)
                Button {
                    appState.mainHistoryMode = .timeline
                    appState.leaveFavorites()
                } label: {
                    Label("时间线大纲", systemImage: "calendar.day.timeline.leading")
                        .foregroundStyle(appState.mainHistoryMode == .timeline ? PasteTheme.accent : .primary)
                }
                .buttonStyle(.plain)
            }

            Section("资料库") {
                ForEach(AppState.ContentFilter.allCases) { filter in
                    Button {
                        appState.selectedFilter = filter
                        appState.showOnlyPinned = (filter == .pinned)
                        if filter == .favorite {
                            appState.mainHistoryMode = .favorites
                            appState.showFavorites(scope: .all)
                        } else {
                            appState.leaveFavorites()
                            if appState.mainHistoryMode == .favorites {
                                appState.mainHistoryMode = .list
                            }
                        }
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
        .navigationTitle("PasteNest")
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
    static func ensureDemoContent(in context: ModelContext) {
        let boardDescriptor = FetchDescriptor<ClipboardBoard>()
        let boardCount = (try? context.fetchCount(boardDescriptor)) ?? 0
        if boardCount == 0 {
            let boards = [
                ClipboardBoard(name: "工作", sortOrder: 0, colorHex: "#0D9488"),
                ClipboardBoard(name: "灵感", sortOrder: 1, colorHex: "#EE6C4D"),
                ClipboardBoard(name: "代码片段", sortOrder: 2, colorHex: "#059669")
            ]
            boards.forEach { context.insert($0) }
        }

        let itemDescriptor = FetchDescriptor<ClipboardItem>()
        let itemCount = (try? context.fetchCount(itemDescriptor)) ?? 0
        guard itemCount == 0 else {
            try? context.save()
            return
        }

        let demos: [(ClipboardContentType, String, String?)] = [
            (.link, "https://developer.apple.com/documentation/swiftdata", "Safari"),
            (.code, "import SwiftUI\n\nstruct HelloView: View {\n  var body: some View { Text(\"PasteNest\") }\n}", "Xcode"),
            (.text, "明天下午三点同步剪贴板方案，优先做搜索与置顶。", "Notes"),
            (.color, "#0F766E", "Figma"),
            (.snippet, "PasteNest 会自动保存你复制的文本、链接、图片与文件，并支持 iCloud 同步与全文搜索。", "Slack")
        ]

        for (type, text, app) in demos {
            let title = ContentTypeDetector.previewTitle(for: text, type: type)
            let subtitle = ContentTypeDetector.previewSubtitle(for: text, type: type, sourceApp: app)
            let item = ClipboardItem(
                contentType: type,
                plainText: text,
                sourceAppName: app,
                contentHash: ClipboardMonitor.hashString(text + title),
                previewTitle: title,
                previewSubtitle: subtitle,
                colorHex: type == .color ? text : nil
            )
            if type == .link { item.isPinned = true }
            // One favorite out of the box so the folder shows what it is for.
            if type == .code {
                item.isFavorite = true
                item.favoritedAt = .now
                item.favoriteTags = ["代码"]
            }
            AutoTagService.apply(to: item)
            context.insert(item)
            EmbeddingIndex.shared.upsert(id: item.id, text: item.searchableText)
        }
        try? context.save()
    }
}

