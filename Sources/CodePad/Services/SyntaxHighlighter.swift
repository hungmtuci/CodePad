import AppKit
import Foundation

enum SyntaxTokenKind: Sendable {
    case comment
    case string
    case number
    case keyword
    case type
    case function
    case property
    case tag
    case attribute
    case operatorSymbol
    case decorator
    case heading
    case emphasisBold
    case emphasisItalic
    case link
}

struct SyntaxTokenSpan: Sendable {
    let range: NSRange
    let kind: SyntaxTokenKind
}

enum SyntaxHighlighter {
    private static let maxFullHighlightUTF16Length = 220_000

    private struct CompiledTokenRule: @unchecked Sendable {
        let regex: NSRegularExpression
        let kind: SyntaxTokenKind
        let captureGroup: Int
    }

    private struct OccupiedBitset {
        private var words: [UInt64]

        init(utf16Length: Int) {
            self.words = [UInt64](repeating: 0, count: max(1, (utf16Length + 63) >> 6))
        }

        @inline(__always)
        func hasAnySet(in range: NSRange) -> Bool {
            let start = range.location
            let end = start + range.length
            let firstWord = start >> 6
            let lastWord = (end - 1) >> 6
            let startMask = UInt64.max << (start & 63)
            let endMask = UInt64.max >> (63 - ((end - 1) & 63))

            if firstWord == lastWord {
                return (words[firstWord] & startMask & endMask) != 0
            }
            if (words[firstWord] & startMask) != 0 || (words[lastWord] & endMask) != 0 {
                return true
            }
            for w in (firstWord + 1)..<lastWord where words[w] != 0 {
                return true
            }
            return false
        }

        @inline(__always)
        mutating func setRange(_ range: NSRange) {
            let start = range.location
            let end = start + range.length
            let firstWord = start >> 6
            let lastWord = (end - 1) >> 6
            let startMask = UInt64.max << (start & 63)
            let endMask = UInt64.max >> (63 - ((end - 1) & 63))

            if firstWord == lastWord {
                words[firstWord] |= (startMask & endMask)
                return
            }
            words[firstWord] |= startMask
            for w in (firstWord + 1)..<lastWord {
                words[w] = UInt64.max
            }
            words[lastWord] |= endMask
        }
    }

    private static let compiledRulesByLanguage: [CodeLanguage: [CompiledTokenRule]] = {
        var table: [CodeLanguage: [CompiledTokenRule]] = [:]
        for lang in CodeLanguage.allCases {
            let rawRules = syntaxRules(for: lang)
            table[lang] = rawRules.compactMap { rule in
                guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else {
                    return nil
                }
                return CompiledTokenRule(regex: regex, kind: rule.kind, captureGroup: rule.captureGroup)
            }
        }
        return table
    }()

    // MARK: - Core Tokenizer

    static func tokenize(code: String, language: CodeLanguage) -> [SyntaxTokenSpan] {
        guard language != .plainText, !code.isEmpty else { return [] }
        let nsString = code as NSString
        let fullLength = nsString.length
        guard fullLength > 0 else { return [] }
        let targetRange = NSRange(location: 0, length: min(fullLength, maxFullHighlightUTF16Length))

        guard let rules = compiledRulesByLanguage[language], !rules.isEmpty else { return [] }

        // Compact 64-bit word bitset over UTF-16 code units (64x smaller & faster than [Bool])
        // so higher-priority tokens (comments, strings) never get overwritten by inner keywords/numbers.
        var occupied = OccupiedBitset(utf16Length: targetRange.length)
        var spans: [SyntaxTokenSpan] = []
        spans.reserveCapacity(min(targetRange.length / 8, 8192))

        for rule in rules {
            rule.regex.enumerateMatches(in: code, options: [], range: targetRange) { match, _, _ in
                guard let match else { return }
                let r = rule.captureGroup < match.numberOfRanges ? match.range(at: rule.captureGroup) : match.range
                guard r.location != NSNotFound, r.length > 0, r.location + r.length <= targetRange.length else { return }

                if occupied.hasAnySet(in: r) {
                    return
                }
                occupied.setRange(r)
                spans.append(SyntaxTokenSpan(range: r, kind: rule.kind))
            }
        }

        spans.sort { $0.range.location < $1.range.location }
        return spans
    }

    // MARK: - Apply Directly to NSTextStorage (Zero-Flicker, Preserves Cursor & Undo)

    @MainActor
    @discardableResult
    static func applyHighlighting(
        to textStorage: NSTextStorage,
        language: CodeLanguage,
        palette: EditorThemePalette,
        regularFont: NSFont,
        boldFont: NSFont,
        italicFont: NSFont,
        paragraphStyle: NSParagraphStyle
    ) -> [SyntaxTokenSpan] {
        let code = textStorage.string
        let fullRange = NSRange(location: 0, length: (code as NSString).length)
        guard fullRange.length > 0 else { return [] }

        let spans = tokenize(code: code, language: language)

        textStorage.beginEditing()
        textStorage.setAttributes(
            [
                .font: regularFont,
                .foregroundColor: palette.plainTextNS,
                .paragraphStyle: paragraphStyle
            ],
            range: fullRange
        )

        for span in spans where span.range.location + span.range.length <= fullRange.length {
            textStorage.addAttribute(.foregroundColor, value: palette.tokenNSColor(for: span.kind), range: span.range)

            switch span.kind {
            case .comment, .emphasisItalic:
                textStorage.addAttribute(.font, value: italicFont, range: span.range)
            case .keyword, .heading, .emphasisBold, .tag:
                textStorage.addAttribute(.font, value: boldFont, range: span.range)
            default:
                break
            }
        }
        textStorage.endEditing()
        return spans
    }

    // MARK: - Rich NSAttributedString (Clipboard Rich Copy & PNG Card Snapshot)

    static func attributedString(
        for code: String,
        language: CodeLanguage,
        palette: EditorThemePalette,
        fontFamily: String,
        fontSize: CGFloat
    ) -> NSAttributedString {
        let regFont = resolveMonoFont(family: fontFamily, size: fontSize, weight: .regular, italic: false)
        let boldFont = resolveMonoFont(family: fontFamily, size: fontSize, weight: .semibold, italic: false)
        let italicFont = resolveMonoFont(family: fontFamily, size: fontSize, weight: .regular, italic: true)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.32

        let attr = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: regFont,
                .foregroundColor: palette.plainTextNS,
                .backgroundColor: palette.editorBackgroundNS,
                .paragraphStyle: paragraph
            ]
        )

        let fullLen = (code as NSString).length
        let spans = tokenize(code: code, language: language)
        for span in spans where span.range.location + span.range.length <= fullLen {
            attr.addAttribute(.foregroundColor, value: palette.tokenNSColor(for: span.kind), range: span.range)
            switch span.kind {
            case .comment, .emphasisItalic:
                attr.addAttribute(.font, value: italicFont, range: span.range)
            case .keyword, .heading, .emphasisBold, .tag:
                attr.addAttribute(.font, value: boldFont, range: span.range)
            default:
                break
            }
        }
        return attr
    }

    // MARK: - HTML Highlighted Code Emitter (Preview, PDF, Standalone HTML & Word DOCX)

    static func highlightedHTML(
        for code: String,
        language: CodeLanguage,
        palette: EditorThemePalette,
        includeLineNumbers: Bool = false,
        wordCompatible: Bool = false
    ) -> String {
        let nsString = code as NSString
        let totalLen = nsString.length
        guard totalLen > 0 else { return "" }

        let spans = tokenize(code: code, language: language)

        // Build inline styled segments
        var rawPieces: [(text: String, style: String?)] = []
        rawPieces.reserveCapacity(spans.count * 2 + 1)

        var cursor = 0
        for span in spans where span.range.location >= cursor && span.range.location + span.range.length <= totalLen {
            if span.range.location > cursor {
                let plain = nsString.substring(with: NSRange(location: cursor, length: span.range.location - cursor))
                rawPieces.append((plain, nil))
            }
            let tokText = nsString.substring(with: span.range)
            let hex = palette.tokenHex(for: span.kind)
            var css = "color:\(hex);"
            switch span.kind {
            case .keyword, .heading, .emphasisBold, .tag:
                css += "font-weight:600;"
            case .comment, .emphasisItalic:
                css += "font-style:italic;"
            default:
                break
            }
            rawPieces.append((tokText, css))
            cursor = span.range.location + span.range.length
        }
        if cursor < totalLen {
            rawPieces.append((nsString.substring(with: NSRange(location: cursor, length: totalLen - cursor)), nil))
        }

        if !includeLineNumbers && !wordCompatible {
            var out = ""
            out.reserveCapacity(totalLen + spans.count * 36)
            for piece in rawPieces {
                let esc = escapeHTML(piece.text)
                if let style = piece.style {
                    out += "<span style=\"\(style)\">\(esc)</span>"
                } else {
                    out += esc
                }
            }
            return out
        }

        // Split into per-line HTML while keeping multi-line comment/string styles active across line breaks
        var linesHTML: [String] = [""]
        for piece in rawPieces {
            let parts = piece.text.components(separatedBy: "\n")
            for (idx, part) in parts.enumerated() {
                if idx > 0 {
                    linesHTML.append("")
                }
                guard !part.isEmpty else { continue }
                let cleanedPart = part.replacingOccurrences(of: "\r", with: "")
                let esc = wordCompatible ? escapeHTMLPreservingLeadingSpaces(cleanedPart) : escapeHTML(cleanedPart)
                if let style = piece.style {
                    linesHTML[linesHTML.count - 1] += "<span style=\"\(style)\">\(esc)</span>"
                } else {
                    linesHTML[linesHTML.count - 1] += esc
                }
            }
        }

        if wordCompatible {
            let digits = max(2, String(linesHTML.count).count)
            var out = ""
            for (idx, lineHTML) in linesHTML.enumerated() {
                if includeLineNumbers {
                    let numStr = String(repeating: "\u{00A0}", count: max(0, digits - String(idx + 1).count)) + "\(idx + 1)"
                    out += "<span style=\"color:\(palette.gutterTextHex);\">\(numStr)\u{00A0}\u{00A0}</span>"
                }
                out += lineHTML.isEmpty ? "\u{00A0}" : lineHTML
                if idx < linesHTML.count - 1 {
                    out += "<br>\n"
                }
            }
            return out
        } else {
            var out = "<table class=\"code-lines\" cellspacing=\"0\" cellpadding=\"0\"><tbody>"
            for (idx, lineHTML) in linesHTML.enumerated() {
                out += "<tr>"
                if includeLineNumbers {
                    out += "<td class=\"ln\">\(idx + 1)</td>"
                }
                out += "<td class=\"lc\">\(lineHTML.isEmpty ? " " : lineHTML)</td></tr>"
            }
            out += "</tbody></table>"
            return out
        }
    }

    static func resolveMonoFont(family: String, size: CGFloat, weight: NSFont.Weight, italic: Bool) -> NSFont {
        var base: NSFont
        if family == "SF Mono" {
            base = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        } else if let custom = NSFont(name: family, size: size) {
            base = custom
            if weight == .semibold || weight == .bold {
                base = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
            }
        } else {
            base = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
        if italic {
            base = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
        }
        return base
    }

    static func escapeHTML(_ text: String) -> String {
        guard text.utf8.contains(where: { $0 == 38 || $0 == 60 || $0 == 62 || $0 == 34 }) else {
            return text
        }
        var out = ""
        out.reserveCapacity(text.utf8.count + 16)
        for ch in text {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(ch)
            }
        }
        return out
    }

    private static func escapeHTMLPreservingLeadingSpaces(_ text: String) -> String {
        let expanded = text.contains("\t") ? text.replacingOccurrences(of: "\t", with: "    ") : text
        let escaped = escapeHTML(expanded)
        return escaped.contains("  ") ? escaped.replacingOccurrences(of: "  ", with: "\u{00A0} ") : escaped
    }

    @inline(__always)
    static func nsColor(for kind: SyntaxTokenKind, in palette: EditorThemePalette) -> NSColor {
        palette.tokenNSColor(for: kind)
    }

    @inline(__always)
    static func hexColor(for kind: SyntaxTokenKind, in palette: EditorThemePalette) -> String {
        palette.tokenHex(for: kind)
    }

    // MARK: - Language Grammar Rules

    private struct TokenRule {
        let pattern: String
        let kind: SyntaxTokenKind
        let options: NSRegularExpression.Options
        let captureGroup: Int

        init(
            _ pattern: String,
            kind: SyntaxTokenKind,
            options: NSRegularExpression.Options = [],
            captureGroup: Int = 0
        ) {
            self.pattern = pattern
            self.kind = kind
            self.options = options
            self.captureGroup = captureGroup
        }
    }

    private static func syntaxRules(for language: CodeLanguage) -> [TokenRule] {
        switch language {
        case .plainText:
            return []

        case .markdown:
            return [
                TokenRule(#"<!--[\s\S]*?-->"#, kind: .comment),
                TokenRule(#"```[\s\S]*?```"#, kind: .string),
                TokenRule(#"`[^`\n]+`"#, kind: .string),
                TokenRule(#"(?m)^#{1,6}\s+.*$"#, kind: .heading),
                TokenRule(#"!?\[[^\]]*\]\([^)]+\)"#, kind: .link),
                TokenRule(#"\*\*[^*\n]+\*\*|__[^_\n]+__"#, kind: .emphasisBold),
                TokenRule(#"(?<!\*)\*[^*\n]+\*(?!\*)"#, kind: .emphasisItalic),
                TokenRule(#"(?m)^\s*>\s+.*$"#, kind: .comment),
                TokenRule(#"(?m)^\s*([-*+]|\d+\.)\s"#, kind: .keyword)
            ]

        case .html, .xml, .svg:
            return [
                TokenRule(#"<!--[\s\S]*?-->"#, kind: .comment),
                TokenRule(#"(?i)<!DOCTYPE[^>]*>"#, kind: .decorator),
                TokenRule(#""[^"]*"|'[^']*'"#, kind: .string),
                TokenRule(#"</?[\w:\-]+"#, kind: .tag),
                TokenRule(#"/?\s*>"#, kind: .tag),
                TokenRule(#"\b[\w:\-]+(?=\s*=)"#, kind: .attribute),
                TokenRule(#"&[\w#]+;"#, kind: .number)
            ]

        case .json:
            return [
                TokenRule(#""(?:\\.|[^"\\])*"(?=\s*:)"#, kind: .property),
                TokenRule(#""(?:\\.|[^"\\])*""#, kind: .string),
                TokenRule(#"\b(true|false|null)\b"#, kind: .keyword),
                TokenRule(#"-?\b\d+(\.\d+)?([eE][+-]?\d+)?\b"#, kind: .number)
            ]

        case .css:
            return [
                TokenRule(#"/\*[\s\S]*?\*/"#, kind: .comment),
                TokenRule(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, kind: .string),
                TokenRule(#"@[\w\-]+"#, kind: .keyword),
                TokenRule(#"#[0-9a-fA-F]{3,8}\b"#, kind: .number),
                TokenRule(#"\b\d+(\.\d+)?(px|rem|em|vh|vw|%|s|ms|deg|fr)?\b"#, kind: .number),
                TokenRule(#"[\w\-]+(?=\s*:)"#, kind: .property),
                TokenRule(#"[.#][\w\-]+"#, kind: .function),
                TokenRule(#"\b(important|flex|grid|none|block|inline|absolute|relative|fixed|solid|auto|inherit|transparent)\b"#, kind: .type)
            ]

        case .yaml:
            return [
                TokenRule(#"#.*$"#, kind: .comment, options: [.anchorsMatchLines]),
                TokenRule(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, kind: .string),
                TokenRule(#"(?m)^\s*[\w.\-]+(?=\s*:)"#, kind: .property),
                TokenRule(#"\b(true|false|yes|no|null|on|off)\b"#, kind: .keyword, options: [.caseInsensitive]),
                TokenRule(#"\b\d+(\.\d+)?\b"#, kind: .number)
            ]

        case .sql:
            return [
                TokenRule(#"--.*$"#, kind: .comment, options: [.anchorsMatchLines]),
                TokenRule(#"/\*[\s\S]*?\*/"#, kind: .comment),
                TokenRule(#"'(?:''|[^'])*'|"(?:\\.|[^"\\])*""#, kind: .string),
                TokenRule(#"\b(SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|ALTER|DROP|TABLE|VIEW|INDEX|DATABASE|JOIN|INNER|LEFT|RIGHT|FULL|OUTER|ON|AS|AND|OR|NOT|NULL|IS|IN|EXISTS|BETWEEN|LIKE|ILIKE|ORDER|BY|GROUP|HAVING|LIMIT|OFFSET|DISTINCT|UNION|ALL|CASE|WHEN|THEN|ELSE|END|PRIMARY|KEY|FOREIGN|REFERENCES|DEFAULT|CONSTRAINT|BEGIN|COMMIT|ROLLBACK|WITH|RETURNING|ASC|DESC)\b"#, kind: .keyword, options: [.caseInsensitive]),
                TokenRule(#"\b(INT|INTEGER|BIGINT|SMALLINT|VARCHAR|TEXT|CHAR|BOOLEAN|BOOL|DATE|DATETIME|TIMESTAMP|NUMERIC|DECIMAL|FLOAT|DOUBLE|UUID|JSON|JSONB|SERIAL)\b"#, kind: .type, options: [.caseInsensitive]),
                TokenRule(#"\b(COUNT|SUM|AVG|MIN|MAX|COALESCE|NOW|LOWER|UPPER|ROUND|CAST|CONCAT)\s*(?=\()"#, kind: .function, options: [.caseInsensitive]),
                TokenRule(#"\b\d+(\.\d+)?\b"#, kind: .number)
            ]

        case .python:
            return [
                TokenRule(#"#.*$"#, kind: .comment, options: [.anchorsMatchLines]),
                TokenRule(#"\"\"\"[\s\S]*?\"\"\"|'''[\s\S]*?'''"#, kind: .string),
                TokenRule(#"[fFrRbBuU]{0,2}"(?:\\.|[^"\\\n])*"|[fFrRbBuU]{0,2}'(?:\\.|[^'\\\n])*'"#, kind: .string),
                TokenRule(#"@[\w.]+"#, kind: .decorator),
                TokenRule(#"\b(def|class)\s+([A-Za-z_]\w*)"#, kind: .function, captureGroup: 2),
                TokenRule(#"\b(and|as|assert|async|await|break|class|continue|def|del|elif|else|except|False|finally|for|from|global|if|import|in|is|lambda|None|nonlocal|not|or|pass|raise|return|True|try|while|with|yield|match|case)\b"#, kind: .keyword),
                TokenRule(#"\b(int|float|str|bool|list|dict|set|tuple|bytes|object|Optional|Any|List|Dict|Tuple|Callable|self|cls)\b"#, kind: .type),
                TokenRule(#"\b([A-Za-z_]\w*)(?=\s*\()"#, kind: .function),
                TokenRule(#"\b(0x[0-9a-fA-F_]+|\d[\d_]*(\.[\d_]+)?)\b"#, kind: .number)
            ]

        case .swift:
            return [
                TokenRule(#"//.*$"#, kind: .comment, options: [.anchorsMatchLines]),
                TokenRule(#"/\*[\s\S]*?\*/"#, kind: .comment),
                TokenRule(#"\"\"\"[\s\S]*?\"\"\""#, kind: .string),
                TokenRule(#""(?:\\.|[^"\\\n])*""#, kind: .string),
                TokenRule(#"@[A-Za-z_]\w*"#, kind: .decorator),
                TokenRule(#"\b(import|class|struct|enum|protocol|extension|func|init|deinit|var|let|if|else|guard|switch|case|default|for|in|while|repeat|break|continue|return|throw|throws|rethrows|try|catch|do|async|await|actor|some|any|where|as|is|nil|true|false|self|Self|super|private|fileprivate|internal|public|open|static|final|override|mutating|nonisolated|weak|unowned|inout|defer|typealias)\b"#, kind: .keyword),
                TokenRule(#"\b([A-Z][A-Za-z0-9_]*)\b"#, kind: .type),
                TokenRule(#"\b([a-z_][A-Za-z0-9_]*)(?=\s*\()"#, kind: .function),
                TokenRule(#"\b(0x[0-9a-fA-F_]+|\d[\d_]*(\.[\d_]+)?)\b"#, kind: .number)
            ]

        case .javascript, .typescript:
            return [
                TokenRule(#"//.*$"#, kind: .comment, options: [.anchorsMatchLines]),
                TokenRule(#"/\*[\s\S]*?\*/"#, kind: .comment),
                TokenRule(#"`(?:\\.|[^`\\])*`"#, kind: .string),
                TokenRule(#""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'"#, kind: .string),
                TokenRule(#"@[A-Za-z_]\w*"#, kind: .decorator),
                TokenRule(#"\b(async|await|break|case|catch|class|const|continue|debugger|default|delete|do|else|enum|export|extends|false|finally|for|from|function|if|implements|import|in|instanceof|interface|let|new|null|of|package|private|protected|public|readonly|return|static|super|switch|this|throw|true|try|type|typeof|undefined|var|void|while|with|yield|as|satisfies|keyof)\b"#, kind: .keyword),
                TokenRule(#"\b(string|number|boolean|any|unknown|never|Promise|Array|Record|Map|Set|Object|Date|Math|JSON|console|window|document)\b"#, kind: .type),
                TokenRule(#"\b([A-Z][A-Za-z0-9_]*)\b"#, kind: .type),
                TokenRule(#"\b([a-zA-Z_$][\w$]*)(?=\s*\()"#, kind: .function),
                TokenRule(#"\b(0x[0-9a-fA-F_]+|\d[\d_]*(\.[\d_]+)?n?)\b"#, kind: .number)
            ]

        case .shell, .dockerfile:
            return [
                TokenRule(#"#.*$"#, kind: .comment, options: [.anchorsMatchLines]),
                TokenRule(#""(?:\\.|[^"\\])*"|'[^']*'"#, kind: .string),
                TokenRule(#"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"#, kind: .property),
                TokenRule(#"\b(if|then|else|elif|fi|for|in|do|done|case|esac|while|until|function|return|exit|export|local|readonly|set|unset|shift|source|echo|cd|pwd|mkdir|rm|cp|mv|chmod|chown|grep|sed|awk|curl|git|swift|FROM|RUN|CMD|ENTRYPOINT|WORKDIR|ENV|ARG|COPY|ADD|EXPOSE|VOLUME|USER|LABEL)\b"#, kind: .keyword),
                TokenRule(#"(?<=\s)-[A-Za-z\-]+"#, kind: .attribute),
                TokenRule(#"\b\d+(\.\d+)?\b"#, kind: .number)
            ]

        case .mermaid:
            return [
                TokenRule(#"%%.*$"#, kind: .comment, options: [.anchorsMatchLines]),
                TokenRule(#""[^"]*""#, kind: .string),
                TokenRule(#"\b(flowchart|graph|sequenceDiagram|classDiagram|stateDiagram|stateDiagram-v2|erDiagram|gantt|pie|subgraph|end|participant|actor|loop|alt|opt|par|TD|TB|BT|RL|LR)\b"#, kind: .keyword),
                TokenRule(#"-->|---|-\.->|==>|-\>>|-->>"#, kind: .operatorSymbol)
            ]

        case .csv:
            return [
                TokenRule(#"\A[^\r\n]+"#, kind: .heading),
                TokenRule(#""(?:""|[^"])*""#, kind: .string),
                TokenRule(#"-?\b\d+(\.\d+)?\b"#, kind: .number),
                TokenRule(#"[,;\t]"#, kind: .operatorSymbol)
            ]

        case .latex:
            return [
                TokenRule(#"%.*$"#, kind: .comment, options: [.anchorsMatchLines]),
                TokenRule(#"\$\$[\s\S]*?\$\$|\$[^$\n]+\$"#, kind: .string),
                TokenRule(#"\\[A-Za-z@]+"#, kind: .keyword),
                TokenRule(#"[{}]"#, kind: .operatorSymbol),
                TokenRule(#"\b\d+(\.\d+)?\b"#, kind: .number)
            ]

        case .go, .rust, .cpp, .java, .csharp, .php, .ruby:
            return genericCStyleRules(for: language)
        }
    }

    private static func genericCStyleRules(for language: CodeLanguage) -> [TokenRule] {
        var rules: [TokenRule] = []
        if language == .ruby || language == .php {
            rules.append(TokenRule(#"#.*$"#, kind: .comment, options: [.anchorsMatchLines]))
        }
        if language != .ruby {
            rules.append(TokenRule(#"//.*$"#, kind: .comment, options: [.anchorsMatchLines]))
            rules.append(TokenRule(#"/\*[\s\S]*?\*/"#, kind: .comment))
        }
        if language == .cpp {
            rules.append(TokenRule(#"(?m)^\s*#\s*\w+.*$"#, kind: .decorator))
        }
        rules.append(TokenRule(#""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'"#, kind: .string))
        if language == .php {
            rules.append(TokenRule(#"\$[A-Za-z_]\w*"#, kind: .property))
        }
        rules.append(TokenRule(#"@[A-Za-z_]\w*"#, kind: .decorator))
        rules.append(TokenRule(
            #"\b(abstract|alignof|as|async|await|auto|begin|bool|break|case|catch|char|class|const|constexpr|continue|crate|def|default|defer|delete|do|double|dyn|else|elsif|end|ensure|enum|extern|false|final|finally|float|fn|for|friend|func|go|goto|if|impl|implements|import|in|inline|int|interface|internal|let|long|loop|match|mod|module|move|mut|namespace|new|nil|null|nullptr|object|operator|override|package|php|private|protected|pub|public|range|readonly|ref|register|require|return|rescue|select|self|short|signed|sizeof|static|struct|super|switch|synchronized|template|then|this|throw|throws|trait|true|try|type|typedef|typename|uint|union|unless|unsafe|unsigned|use|using|val|var|virtual|void|volatile|where|while|yield)\b"#,
            kind: .keyword
        ))
        rules.append(TokenRule(#"\b([A-Z][A-Za-z0-9_]*)\b"#, kind: .type))
        rules.append(TokenRule(#"\b([a-z_][A-Za-z0-9_]*)(?=\s*\()"#, kind: .function))
        rules.append(TokenRule(#"\b(0x[0-9a-fA-F_]+|\d[\d_]*(\.[\d_]+)?)\b"#, kind: .number))
        return rules
    }
}
