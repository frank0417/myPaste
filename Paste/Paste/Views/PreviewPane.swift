import SwiftUI
import SwiftData
import AppKit

struct PreviewPane: View {
    @EnvironmentObject private var appState: AppState
    @Query(sort: \ClipboardItem.updatedAt, order: .reverse) private var items: [ClipboardItem]
    @Query(sort: \ClipboardBoard.sortOrder) private var boards: [ClipboardBoard]
    var store: ClipboardStore?

    private var selected: ClipboardItem? {
        guard let id = appState.selectedItemID else { return items.first }
        return items.first(where: { $0.id == id }) ?? items.first
    }

    var body: some View {
        Group {
            if let item = selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(item)
                        previewBody(item)
                        metadata(item)
                        actions(item)
                    }
                    .padding(20)
                }
            } else {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "eye")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("选择一条记录以预览")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.primary.opacity(0.02))
    }

    private func header(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(item.contentType.displayName, systemImage: item.contentType.systemImage)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        (Color(hex: item.contentType.accentHex) ?? PasteTheme.accent).opacity(0.14),
                        in: Capsule()
                    )
                    .foregroundStyle(Color(hex: item.contentType.accentHex) ?? PasteTheme.accent)
                Spacer()
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(PasteTheme.accent)
                }
            }
            Text(item.previewTitle)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func previewBody(_ item: ClipboardItem) -> some View {
        switch item.contentType {
        case .image:
            if let data = item.imageData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            }
        case .color:
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: item.colorHex ?? "#888888") ?? .gray)
                .frame(height: 120)
                .overlay(alignment: .bottomLeading) {
                    Text(item.colorHex ?? "")
                        .font(.system(.title3, design: .monospaced).weight(.medium))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(14)
                }
        case .code:
            Text(item.plainText ?? "")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .link:
            VStack(alignment: .leading, spacing: 8) {
                Link(destination: URL(string: item.plainText ?? "") ?? URL(string: "https://")!) {
                    Label(item.plainText ?? "", systemImage: "arrow.up.right.square")
                        .lineLimit(3)
                }
                Text("点击打开链接，或直接粘贴到当前应用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        default:
            Text(item.plainText ?? item.previewTitle)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func metadata(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            metaRow("来源", item.sourceAppName ?? "未知应用")
            metaRow("复制时间", item.createdAt.formatted(date: .abbreviated, time: .shortened))
            metaRow("粘贴次数", "\(item.pasteCount)")
            if item.contentType == .file {
                metaRow("路径", item.fileURLs.map(\.path).joined(separator: "\n"))
            }
        }
        .font(.callout)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func actions(_ item: ClipboardItem) -> some View {
        HStack(spacing: 10) {
            Button {
                store?.paste(item)
            } label: {
                Label("粘贴", systemImage: "return")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(PasteTheme.accent)

            Button {
                store?.copyOnly(item)
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Button {
                store?.togglePin(item)
            } label: {
                Image(systemName: item.isPinned ? "pin.slash" : "pin")
            }
            .buttonStyle(.bordered)

            Menu {
                Button("无看板") { store?.assign(item: item, to: nil) }
                ForEach(boards) { board in
                    Button(board.name) { store?.assign(item: item, to: board) }
                }
            } label: {
                Label(item.board?.name ?? "看板", systemImage: "square.grid.2x2")
            }
        }
        .controlSize(.large)
    }
}
