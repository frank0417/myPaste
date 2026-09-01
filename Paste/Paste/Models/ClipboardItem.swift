import Foundation
import SwiftData
import AppKit

enum ClipboardContentType: String, Codable, CaseIterable, Identifiable {
    case text
    case richText
    case link
    case image
    case color
    case file
    case code
    case snippet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: return "文本"
        case .richText: return "富文本"
        case .link: return "链接"
        case .image: return "图片"
        case .color: return "颜色"
        case .file: return "文件"
        case .code: return "代码"
        case .snippet: return "片段"
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "text.alignleft"
        case .richText: return "doc.richtext"
        case .link: return "link"
        case .image: return "photo"
        case .color: return "paintpalette"
        case .file: return "doc"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .snippet: return "text.quote"
        }
    }

    var accentHex: String {
        switch self {
        case .text: return "#3D5A80"
        case .richText: return "#EE6C4D"
        case .link: return "#0D9488"
        case .image: return "#7C3AED"
        case .color: return "#F59E0B"
        case .file: return "#64748B"
        case .code: return "#059669"
        case .snippet: return "#2563EB"
        }
    }
}

@Model
final class ClipboardItem {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var contentTypeRaw: String
    var plainText: String?
    var richTextData: Data?
    var imageData: Data?
    var thumbnailData: Data?
    var fileURLsJSON: String?
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var isPinned: Bool
    var isFavorite: Bool
    var pasteCount: Int
    var contentHash: String
    var previewTitle: String
    var previewSubtitle: String?
    var colorHex: String?
    var board: ClipboardBoard?

    var contentType: ClipboardContentType {
        get { ClipboardContentType(rawValue: contentTypeRaw) ?? .text }
        set { contentTypeRaw = newValue.rawValue }
    }

    var fileURLs: [URL] {
        get {
            guard let fileURLsJSON,
                  let data = fileURLsJSON.data(using: .utf8),
                  let strings = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return strings.compactMap(URL.init(string:))
        }
        set {
            let strings = newValue.map(\.absoluteString)
            fileURLsJSON = (try? String(data: JSONEncoder().encode(strings), encoding: .utf8)) ?? "[]"
        }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        contentType: ClipboardContentType,
        plainText: String? = nil,
        richTextData: Data? = nil,
        imageData: Data? = nil,
        thumbnailData: Data? = nil,
        fileURLs: [URL] = [],
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        contentHash: String,
        previewTitle: String,
        previewSubtitle: String? = nil,
        colorHex: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.contentTypeRaw = contentType.rawValue
        self.plainText = plainText
        self.richTextData = richTextData
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.isPinned = false
        self.isFavorite = false
        self.pasteCount = 0
        self.contentHash = contentHash
        self.previewTitle = previewTitle
        self.previewSubtitle = previewSubtitle
        self.colorHex = colorHex
        self.fileURLs = fileURLs
    }
}

@Model
final class ClipboardBoard {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var sortOrder: Int
    var colorHex: String
    @Relationship(deleteRule: .nullify, inverse: \ClipboardItem.board)
    var items: [ClipboardItem]

    init(name: String, sortOrder: Int = 0, colorHex: String = "#0D9488") {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.sortOrder = sortOrder
        self.colorHex = colorHex
        self.items = []
    }
}
