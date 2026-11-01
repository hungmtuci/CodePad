import Foundation

struct DocumentTab: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var customTitle: String?
    var content: String {
        didSet {
            if content != oldValue {
                recomputeMetrics()
            }
        }
    }
    var language: CodeLanguage
    var isLanguageAutoDetected: Bool
    var fileURL: URL?
    var isDirty: Bool
    var cursorLocation: Int
    var createdAt: Date
    var updatedAt: Date

    // Cached O(1) document metrics & smart first-line title (recomputed once per content mutation)
    private(set) var lineCount: Int = 1
    private(set) var characterCount: Int = 0
    private(set) var wordCount: Int = 0
    private var cachedAutoTitle: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case customTitle
        case content
        case language
        case isLanguageAutoDetected
        case fileURL
        case isDirty
        case cursorLocation
        case createdAt
        case updatedAt
    }

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
        self.recomputeMetrics()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        self.content = try container.decode(String.self, forKey: .content)
        self.language = try container.decode(CodeLanguage.self, forKey: .language)
        self.isLanguageAutoDetected = try container.decode(Bool.self, forKey: .isLanguageAutoDetected)
        self.fileURL = try container.decodeIfPresent(URL.self, forKey: .fileURL)
        self.isDirty = try container.decode(Bool.self, forKey: .isDirty)
        self.cursorLocation = try container.decode(Int.self, forKey: .cursorLocation)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.recomputeMetrics()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(customTitle, forKey: .customTitle)
        try container.encode(content, forKey: .content)
        try container.encode(language, forKey: .language)
        try container.encode(isLanguageAutoDetected, forKey: .isLanguageAutoDetected)
        try container.encodeIfPresent(fileURL, forKey: .fileURL)
        try container.encode(isDirty, forKey: .isDirty)
        try container.encode(cursorLocation, forKey: .cursorLocation)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private mutating func recomputeMetrics() {
        guard !content.isEmpty else {
            lineCount = 1
            characterCount = 0
            wordCount = 0
            cachedAutoTitle = nil
            return
        }

        // Single-pass zero-allocation scan for lineCount, wordCount, characterCount, and first non-empty line
        var lines = 1
        var chars = 0
        var words = 0
        var inWord = false
        var firstNonEmptyStart: String.Index?
        var firstNonEmptyEnd: String.Index?
        var currentLineHasNonSpace = false

        var idx = content.startIndex
        let end = content.endIndex
        while idx < end {
            let ch = content[idx]
            chars += 1

            if ch == "\n" {
                lines += 1
                inWord = false
                if currentLineHasNonSpace && firstNonEmptyEnd == nil {
                    firstNonEmptyEnd = idx
                }
            } else if ch == "\r" {
                inWord = false
                if currentLineHasNonSpace && firstNonEmptyEnd == nil {
                    firstNonEmptyEnd = idx
                }
            } else if ch.isWhitespace {
                inWord = false
            } else {
                if !inWord {
                    words += 1
                    inWord = true
                }
                if firstNonEmptyStart == nil {
                    firstNonEmptyStart = idx
                    currentLineHasNonSpace = true
                }
            }
            content.formIndex(after: &idx)
        }

        if currentLineHasNonSpace && firstNonEmptyEnd == nil {
            firstNonEmptyEnd = end
        }

        self.lineCount = lines
        self.characterCount = chars
        self.wordCount = words

        if let s = firstNonEmptyStart, let e = firstNonEmptyEnd, s < e {
            var cleaned = content[s..<e].trimmingCharacters(in: .whitespaces)
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
                self.cachedAutoTitle = cleaned.count > 28 ? "\(truncated)…" : truncated
            } else {
                self.cachedAutoTitle = nil
            }
        } else {
            self.cachedAutoTitle = nil
        }
    }

    /// Sublime-style smart tab title: saved filename > customTitle > first meaningful non-empty line > "Untitled".
    var displayTitle: String {
        if let fileURL {
            return fileURL.lastPathComponent
        }
        if let customTitle, !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customTitle
        }
        if let cachedAutoTitle {
            return cachedAutoTitle
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

    static func == (lhs: DocumentTab, rhs: DocumentTab) -> Bool {
        lhs.id == rhs.id
            && lhs.isDirty == rhs.isDirty
            && lhs.language == rhs.language
            && lhs.isLanguageAutoDetected == rhs.isLanguageAutoDetected
            && lhs.characterCount == rhs.characterCount
            && lhs.lineCount == rhs.lineCount
            && lhs.customTitle == rhs.customTitle
            && lhs.fileURL == rhs.fileURL
            && lhs.cursorLocation == rhs.cursorLocation
            && lhs.content == rhs.content
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
