import Foundation

struct DocumentTab: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var customTitle: String?
    var content: String
    var language: CodeLanguage
    var isLanguageAutoDetected: Bool
    var fileURL: URL?
    var isDirty: Bool
    var cursorLocation: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        customTitle: String? = nil,
        content: String = "",
        language: CodeLanguage = .plainText,
        isLanguageAutoDetected: Bool = true,
        fileURL: URL? = nil,
        isDirty: Bool = false,
        cursorLocation: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.customTitle = customTitle
        self.content = content
        self.language = language
        self.isLanguageAutoDetected = isLanguageAutoDetected
        self.fileURL = fileURL
        self.isDirty = isDirty
        self.cursorLocation = cursorLocation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Sublime-style smart tab title: saved filename > customTitle > first meaningful non-empty line > "Untitled".
    var displayTitle: String {
        if let fileURL {
            return fileURL.lastPathComponent
        }
        if let customTitle, !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customTitle
        }
        let firstLine = content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        if let firstLine {
            var cleaned = firstLine
            while cleaned.hasPrefix("#") || cleaned.hasPrefix("//") || cleaned.hasPrefix("/*") || cleaned.hasPrefix("<!--") {
                if cleaned.hasPrefix("<!--") {
                    cleaned.removeFirst(4)
                } else if cleaned.hasPrefix("//") || cleaned.hasPrefix("/*") {
                    cleaned.removeFirst(2)
                } else {
                    cleaned.removeFirst()
                }
                cleaned = cleaned.trimmingCharacters(in: .whitespaces)
            }
            if cleaned.hasSuffix("-->") {
                cleaned = String(cleaned.dropLast(3)).trimmingCharacters(in: .whitespaces)
            }
            if !cleaned.isEmpty {
                let truncated = String(cleaned.prefix(28))
                return cleaned.count > 28 ? "\(truncated)…" : truncated
            }
        }
        return "Untitled.\(language.defaultExtension)"
    }

    var suggestedBaseFilename: String {
        if let fileURL {
            return fileURL.deletingPathExtension().lastPathComponent
        }
        let raw = displayTitle
            .replacingOccurrences(of: ".\(language.defaultExtension)", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "…", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "CodePad-Document" : raw
    }

    var lineCount: Int {
        guard !content.isEmpty else { return 1 }
        var count = 1
        for ch in content where ch == "\n" {
            count += 1
        }
        return count
    }

    var characterCount: Int {
        content.count
    }

    var wordCount: Int {
        content.split { $0.isWhitespace || $0.isNewline }.count
    }
}

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf = "pdf"
    case docx = "docx"
    case html = "html"
    case rtf = "rtf"
    case odt = "odt"
    case pngCard = "png"
    case sourceFile = "source"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pdf: return "Tài liệu PDF (.pdf)"
        case .docx: return "Microsoft Word (.docx)"
        case .html: return "Trang Web độc lập (.html)"
        case .rtf: return "Rich Text (.rtf)"
        case .odt: return "OpenDocument (.odt)"
        case .pngCard: return "Ảnh chụp Code sắc nét (.png)"
        case .sourceFile: return "Tệp mã nguồn gốc"
        }
    }

    var shortLabel: String {
        switch self {
        case .pdf: return "PDF"
        case .docx: return "DOCX"
        case .html: return "HTML"
        case .rtf: return "RTF"
        case .odt: return "ODT"
        case .pngCard: return "PNG"
        case .sourceFile: return "Mã nguồn"
        }
    }

    var sfSymbol: String {
        switch self {
        case .pdf: return "doc.richtext.fill"
        case .docx: return "doc.text.fill"
        case .html: return "safari.fill"
        case .rtf: return "text.alignleft"
        case .odt: return "doc.fill"
        case .pngCard: return "photo.artframe"
        case .sourceFile: return "chevron.left.forwardslash.chevron.right"
        }
    }

    func fileExtension(for language: CodeLanguage) -> String {
        switch self {
        case .pdf: return "pdf"
        case .docx: return "docx"
        case .html: return "html"
        case .rtf: return "rtf"
        case .odt: return "odt"
        case .pngCard: return "png"
        case .sourceFile: return language.defaultExtension
        }
    }
}

struct EditorPreferences: Codable, Equatable, Sendable {
    var themeID: EditorThemeID = .monokaiPro
    var followSystemAppearance: Bool = false
    var fontFamily: String = "SF Mono"
    var fontSize: Double = 13.5
    var tabWidth: Int = 4
    var useSpacesForTabs: Bool = true
    var wordWrap: Bool = true
    var showLineNumbers: Bool = true
    var showMinimap: Bool = true
    var showStatusBar: Bool = true
    var showSidebar: Bool = false
    var autoOpenPreviewForMarkup: Bool = true
    var syncPreviewScroll: Bool = true
    var exportUseLightTheme: Bool = true
    var exportIncludeLineNumbers: Bool = true
    var exportIncludeHeaderMetadata: Bool = true
}

struct WorkspaceToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let revealFileURL: URL?
    let isError: Bool

    init(message: String, revealFileURL: URL? = nil, isError: Bool = false) {
        self.message = message
        self.revealFileURL = revealFileURL
        self.isError = isError
    }
}
