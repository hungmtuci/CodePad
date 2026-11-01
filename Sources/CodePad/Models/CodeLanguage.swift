import SwiftUI

enum CodeLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case plainText = "plaintext"
    case markdown = "markdown"
    case html = "html"
    case css = "css"
    case javascript = "javascript"
    case typescript = "typescript"
    case python = "python"
    case swift = "swift"
    case json = "json"
    case sql = "sql"
    case shell = "shell"
    case yaml = "yaml"
    case xml = "xml"
    case svg = "svg"
    case mermaid = "mermaid"
    case csv = "csv"
    case go = "go"
    case rust = "rust"
    case cpp = "cpp"
    case java = "java"
    case csharp = "csharp"
    case php = "php"
    case ruby = "ruby"
    case dockerfile = "dockerfile"
    case latex = "latex"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plainText: return "Plain Text"
        case .markdown: return "Markdown"
        case .html: return "HTML"
        case .css: return "CSS"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .python: return "Python"
        case .swift: return "Swift"
        case .json: return "JSON"
        case .sql: return "SQL"
        case .shell: return "Shell / Bash"
        case .yaml: return "YAML"
        case .xml: return "XML"
        case .svg: return "SVG Vector"
        case .mermaid: return "Mermaid Diagram"
        case .csv: return "CSV / TSV"
        case .go: return "Go"
        case .rust: return "Rust"
        case .cpp: return "C / C++"
        case .java: return "Java / Kotlin"
        case .csharp: return "C#"
        case .php: return "PHP"
        case .ruby: return "Ruby"
        case .dockerfile: return "Dockerfile"
        case .latex: return "LaTeX"
        }
    }

    var shortBadge: String {
        switch self {
        case .plainText: return "TXT"
        case .markdown: return "MD"
        case .html: return "HTML"
        case .css: return "CSS"
        case .javascript: return "JS"
        case .typescript: return "TS"
        case .python: return "PY"
        case .swift: return "SWIFT"
        case .json: return "JSON"
        case .sql: return "SQL"
        case .shell: return "SH"
        case .yaml: return "YAML"
        case .xml: return "XML"
        case .svg: return "SVG"
        case .mermaid: return "MMD"
        case .csv: return "CSV"
        case .go: return "GO"
        case .rust: return "RS"
        case .cpp: return "C++"
        case .java: return "JAVA"
        case .csharp: return "C#"
        case .php: return "PHP"
        case .ruby: return "RB"
        case .dockerfile: return "DOCKER"
        case .latex: return "TEX"
        }
    }

    var sfSymbol: String {
        switch self {
        case .plainText: return "doc.plaintext"
        case .markdown: return "text.document"
        case .html: return "globe"
        case .css: return "paintbrush"
        case .javascript, .typescript: return "curlybraces.square"
        case .python: return "terminal"
        case .swift: return "swift"
        case .json: return "curlybraces"
        case .sql: return "cylinder.split.1x2"
        case .shell: return "apple.terminal"
        case .yaml: return "list.bullet.indent"
        case .xml: return "chevron.left.forwardslash.chevron.right"
        case .svg: return "scribble.variable"
        case .mermaid: return "point.3.connected.trianglepath.dotted"
        case .csv: return "tablecells"
        case .go, .rust, .cpp, .java, .csharp, .php, .ruby: return "chevron.left.forwardslash.chevron.right"
        case .dockerfile: return "shippingbox"
        case .latex: return "function"
        }
    }

    var defaultExtension: String {
        switch self {
        case .plainText: return "txt"
        case .markdown: return "md"
        case .html: return "html"
        case .css: return "css"
        case .javascript: return "js"
        case .typescript: return "ts"
        case .python: return "py"
        case .swift: return "swift"
        case .json: return "json"
        case .sql: return "sql"
        case .shell: return "sh"
        case .yaml: return "yml"
        case .xml: return "xml"
        case .svg: return "svg"
        case .mermaid: return "mmd"
        case .csv: return "csv"
        case .go: return "go"
        case .rust: return "rs"
        case .cpp: return "cpp"
        case .java: return "java"
        case .csharp: return "cs"
        case .php: return "php"
        case .ruby: return "rb"
        case .dockerfile: return "dockerfile"
        case .latex: return "tex"
        }
    }

    var allExtensions: [String] {
        switch self {
        case .plainText: return ["txt", "log", "text"]
        case .markdown: return ["md", "markdown", "mdown", "mdx"]
        case .html: return ["html", "htm", "xhtml"]
        case .css: return ["css", "scss", "less"]
        case .javascript: return ["js", "mjs", "cjs", "jsx"]
        case .typescript: return ["ts", "tsx"]
        case .python: return ["py", "pyw", "pyi"]
        case .swift: return ["swift"]
        case .json: return ["json", "jsonl", "geojson"]
        case .sql: return ["sql"]
        case .shell: return ["sh", "bash", "zsh", "command", "env"]
        case .yaml: return ["yml", "yaml"]
        case .xml: return ["xml", "plist", "csproj", "xaml"]
        case .svg: return ["svg"]
        case .mermaid: return ["mmd", "mermaid"]
        case .csv: return ["csv", "tsv"]
        case .go: return ["go"]
        case .rust: return ["rs"]
        case .cpp: return ["c", "h", "cpp", "hpp", "cc", "cxx", "mm"]
        case .java: return ["java", "kt", "kts"]
        case .csharp: return ["cs"]
        case .php: return ["php"]
        case .ruby: return ["rb", "rake"]
        case .dockerfile: return ["dockerfile"]
        case .latex: return ["tex", "sty", "bib"]
        }
    }

    /// Languages that can render a rich visual Live Preview pane / window.
    var supportsLivePreview: Bool {
        switch self {
        case .markdown, .html, .svg, .mermaid, .csv, .json, .latex:
            return true
        default:
            return false
        }
    }

    /// Markup languages where pasting or opening should automatically pop open the Live Preview split pane.
    var autoOpenPreviewOnDetect: Bool {
        switch self {
        case .markdown, .html, .svg, .mermaid:
            return true
        default:
            return false
        }
    }

    var lineCommentPrefix: String? {
        switch self {
        case .plainText, .html, .css, .json, .xml, .svg, .csv, .markdown:
            return nil
        case .sql:
            return "-- "
        case .python, .shell, .yaml, .ruby, .dockerfile:
            return "# "
        case .mermaid:
            return "%% "
        case .latex:
            return "% "
        default:
            return "// "
        }
    }

    var blockCommentPair: (open: String, close: String)? {
        switch self {
        case .html, .xml, .svg, .markdown:
            return ("<!-- ", " -->")
        case .css, .javascript, .typescript, .swift, .sql, .go, .rust, .cpp, .java, .csharp, .php:
            return ("/* ", " */")
        default:
            return nil
        }
    }

    var accentColor: Color {
        switch self {
        case .plainText: return .secondary
        case .markdown: return Color(red: 0.28, green: 0.62, blue: 0.98)
        case .html: return Color(red: 0.94, green: 0.40, blue: 0.22)
        case .css: return Color(red: 0.22, green: 0.58, blue: 0.96)
        case .javascript: return Color(red: 0.95, green: 0.80, blue: 0.18)
        case .typescript: return Color(red: 0.19, green: 0.47, blue: 0.78)
        case .python: return Color(red: 0.25, green: 0.68, blue: 0.45)
        case .swift: return Color(red: 0.96, green: 0.38, blue: 0.22)
        case .json: return Color(red: 0.66, green: 0.52, blue: 0.98)
        case .sql: return Color(red: 0.92, green: 0.56, blue: 0.18)
        case .shell: return Color(red: 0.34, green: 0.82, blue: 0.55)
        case .yaml: return Color(red: 0.88, green: 0.36, blue: 0.48)
        case .xml: return Color(red: 0.86, green: 0.54, blue: 0.24)
        case .svg: return Color(red: 0.98, green: 0.66, blue: 0.15)
        case .mermaid: return Color(red: 0.96, green: 0.32, blue: 0.62)
        case .csv: return Color(red: 0.22, green: 0.74, blue: 0.52)
        case .go: return Color(red: 0.00, green: 0.68, blue: 0.85)
        case .rust: return Color(red: 0.87, green: 0.45, blue: 0.26)
        case .cpp: return Color(red: 0.35, green: 0.54, blue: 0.88)
        case .java: return Color(red: 0.90, green: 0.44, blue: 0.20)
        case .csharp: return Color(red: 0.56, green: 0.38, blue: 0.88)
        case .php: return Color(red: 0.48, green: 0.52, blue: 0.78)
        case .ruby: return Color(red: 0.85, green: 0.22, blue: 0.28)
        case .dockerfile: return Color(red: 0.15, green: 0.60, blue: 0.92)
        case .latex: return Color(red: 0.18, green: 0.68, blue: 0.62)
        }
    }

    private static let extensionLookup: [String: CodeLanguage] = {
        var map: [String: CodeLanguage] = [:]
        for lang in Self.allCases where lang != .plainText {
            for ext in lang.allExtensions {
                map[ext] = lang
            }
        }
        for ext in Self.plainText.allExtensions where map[ext] == nil {
            map[ext] = .plainText
        }
        return map
    }()

    private static let fenceAliasLookup: [String: CodeLanguage] = {
        var map = extensionLookup
        for lang in Self.allCases {
            map[lang.rawValue] = lang
        }
        map["bash"] = .shell
        map["zsh"] = .shell
        map["console"] = .shell
        map["terminal"] = .shell
        map["golang"] = .go
        map["c"] = .cpp
        map["c++"] = .cpp
        map["cxx"] = .cpp
        map["objc"] = .cpp
        map["objective-c"] = .cpp
        map["kotlin"] = .java
        map["kt"] = .java
        map["cs"] = .csharp
        map["dotnet"] = .csharp
        map["yml"] = .yaml
        map["docker"] = .dockerfile
        map["tex"] = .latex
        map["math"] = .latex
        return map
    }()

    static func fromFileURL(_ url: URL) -> CodeLanguage? {
        let filename = url.lastPathComponent.lowercased()
        if filename == "dockerfile" || filename.hasPrefix("dockerfile.") {
            return .dockerfile
        }
        if filename == "makefile" || filename == "zshrc" || filename == ".zshrc" || filename == ".bashrc" {
            return .shell
        }
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return extensionLookup[ext]
    }

    /// Maps fence alias (e.g. ```js, ```py, ```sh, ```c++) inside Markdown to `CodeLanguage`.
    static func fromFenceAlias(_ raw: String) -> CodeLanguage {
        let clean = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ")
            .first
            .map(String.init) ?? ""
        guard !clean.isEmpty else { return .plainText }
        return fenceAliasLookup[clean] ?? .plainText
    }
}
