import Foundation

enum LanguageDetector {
    /// Detects the most likely programming or markup language from raw source/pasted text.
    /// Designed to execute in <1ms so paste & live typing never stutter.
    static func detect(from rawText: String) -> CodeLanguage {
        let sample = String(rawText.prefix(16_000))
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .plainText }

        let lines = trimmed
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .prefix(160)
            .map(String.init)
        let firstLine = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let lowerTrimmed = trimmed.lowercased()

        // 1. Shebang check (#!...)
        if firstLine.hasPrefix("#!") {
            let sb = firstLine.lowercased()
            if sb.contains("python") { return .python }
            if sb.contains("node") || sb.contains("deno") || sb.contains("bun") { return .javascript }
            if sb.contains("ts-node") || sb.contains("tsx") { return .typescript }
            if sb.contains("ruby") { return .ruby }
            if sb.contains("php") { return .php }
            if sb.contains("swift") { return .swift }
            if sb.contains("sh") || sb.contains("bash") || sb.contains("zsh") { return .shell }
        }

        // 2. PHP opening tag
        if lowerTrimmed.hasPrefix("<?php") || sample.contains("<?php") {
            return .php
        }

        // 3. SVG / XML / HTML fast checks
        if lowerTrimmed.hasPrefix("<svg") || (lowerTrimmed.contains("<svg") && lowerTrimmed.contains("</svg>")) {
            return .svg
        }
        if lowerTrimmed.hasPrefix("<!doctype html") || lowerTrimmed.hasPrefix("<html") {
            return .html
        }
        if lowerTrimmed.hasPrefix("<?xml") {
            if lowerTrimmed.contains("<svg") { return .svg }
            return .xml
        }

        // 4. Exact JSON check
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            if let data = rawText.count <= 250_000 ? rawText.data(using: .utf8) : nil,
               (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
                return .json
            }
        }

        // 5. Mermaid diagram check
        let mermaidStarters = [
            "flowchart ", "graph td", "graph lr", "graph tb", "graph bt",
            "sequencediagram", "classdiagram", "statediagram", "erdiagram",
            "gantt", "pie ", "mindmap", "timeline", "xychart-beta"
        ]
        let firstNonComment = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("%%") }?
            .lowercased() ?? ""
        if mermaidStarters.contains(where: { firstNonComment.hasPrefix($0) }) {
            return .mermaid
        }

        // 6. LaTeX check
        if sample.contains("\\documentclass") || sample.contains("\\begin{document}") || sample.contains("\\usepackage") {
            return .latex
        }

        // 7. Weighted multi-language scoring
        var scores: [CodeLanguage: Int] = [:]
        func add(_ lang: CodeLanguage, _ pts: Int) {
            scores[lang, default: 0] += pts
        }

        // HTML tags
        let htmlMarkers = ["<div", "<span", "<p>", "<p ", "<h1", "<h2", "<body", "<head", "<script", "<style", "<section", "<article", "<table", "<tr", "<td", "<form", "<input", "<button", "<a href=", "<ul", "<li", "</html>", "</div>"]
        var htmlHits = 0
        for marker in htmlMarkers where lowerTrimmed.contains(marker) {
            htmlHits += 1
        }
        if htmlHits >= 2 {
            add(.html, htmlHits * 5)
        } else if htmlHits == 1 && trimmed.hasPrefix("<") && trimmed.hasSuffix(">") {
            add(.html, 7)
        }

        // XML generic tags
        if trimmed.hasPrefix("<") && trimmed.contains("</") && htmlHits == 0 {
            add(.xml, 6)
        }

        // Markdown signals
        var mdSignals = 0
        if matchesRegex(#"(?m)^#{1,6}\s+\S+"#, in: sample) { mdSignals += 4 }
        if sample.contains("```") { mdSignals += 6 }
        if matchesRegex(#"\[[^\]]+\]\([^)]+\)"#, in: sample) { mdSignals += 5 }
        if matchesRegex(#"(?m)^\s*[-*+]\s+\[[ xX]\]\s+"#, in: sample) { mdSignals += 5 }
        if matchesRegex(#"(?m)^\|.+\|\s*\n\|[\s:\-|]+\|"#, in: sample) { mdSignals += 6 }
        if matchesRegex(#"\*\*[^*\n]+\*\*"#, in: sample) { mdSignals += 3 }
        if matchesRegex(#"(?m)^>\s+\S+"#, in: sample) { mdSignals += 2 }
        if matchesRegex(#"(?m)^\s*[-*]\s+\S+"#, in: sample) { mdSignals += 2 }
        if matchesRegex(#"(?m)^\s*\d+\.\s+\S+"#, in: sample) { mdSignals += 2 }
        if mdSignals >= 4 {
            add(.markdown, mdSignals * 2)
        }

        // SQL signals
        if matchesRegex(#"(?i)\bSELECT\b[\s\S]{1,200}\bFROM\b"#, in: sample) { add(.sql, 12) }
        if matchesRegex(#"(?i)\b(INSERT\s+INTO|CREATE\s+TABLE|ALTER\s+TABLE|DROP\s+TABLE|UPDATE\s+\w+\s+SET)\b"#, in: sample) { add(.sql, 12) }
        if matchesRegex(#"(?i)\b(LEFT\s+JOIN|INNER\s+JOIN|GROUP\s+BY|ORDER\s+BY|WHERE)\b"#, in: sample) { add(.sql, 5) }

        // Swift signals
        if matchesRegex(#"\bimport\s+(Foundation|SwiftUI|AppKit|UIKit|Combine|WebKit|PDFKit)\b"#, in: sample) { add(.swift, 15) }
        if matchesRegex(#"\b(guard\s+let|if\s+let|@MainActor|@Published|@State|@Binding|@Observable)\b"#, in: sample) { add(.swift, 10) }
        if matchesRegex(#"\bfunc\s+\w+\s*\([^)]*\)\s*(async\s*)?(throws\s*)?->"#, in: sample) { add(.swift, 8) }
        if matchesRegex(#"\b(struct|class|enum|protocol|extension)\s+\w+"#, in: sample) && sample.contains("let ") { add(.swift, 5) }

        // Python signals
        if matchesRegex(#"(?m)^\s*(async\s+)?def\s+\w+\s*\(.*\)\s*(->\s*[^:]+)?\s*:"#, in: sample) { add(.python, 12) }
        if matchesRegex(#"(?m)^\s*from\s+[\w.]+\s+import\s+"#, in: sample) { add(.python, 10) }
        if matchesRegex(#"\b(elif|if\s+__name__\s*==\s*['"]__main__['"]|self\.\w+|None|True|False)\b"#, in: sample) { add(.python, 6) }
        if matchesRegex(#"(?m)^\s*class\s+\w+(\([^)]*\))?\s*:"#, in: sample) { add(.python, 7) }

        // TypeScript & JavaScript signals
        if matchesRegex(#"\b(const|let|var)\s+\w+\s*="#, in: sample) { add(.javascript, 4); add(.typescript, 4) }
        if sample.contains("=>") { add(.javascript, 4); add(.typescript, 4) }
        if matchesRegex(#"\b(console\.(log|error|warn)|document\.\w+|window\.\w+|module\.exports|require\s*\()"#, in: sample) {
            add(.javascript, 8)
            add(.typescript, 5)
        }
        if matchesRegex(#"\b(export\s+(default\s+)?(function|class|const|interface|type)|import\s+.*\s+from\s+['"])"#, in: sample) {
            add(.javascript, 6)
            add(.typescript, 7)
        }
        if matchesRegex(#"\b(interface\s+\w+|type\s+\w+\s*=|readonly\s+\w+|as\s+const|:\s*(string|number|boolean|any|unknown|void)\b)"#, in: sample) {
            add(.typescript, 12)
        }

        // CSS signals
        if matchesRegex(#"[.#]?[\w\-]+\s*\{\s*[\w\-]+\s*:\s*[^;{}]+;"#, in: sample) && !sample.contains("function ") && !sample.contains("const ") {
            add(.css, 10)
        }
        if matchesRegex(#"(@media|@keyframes|:root|--[\w\-]+\s*:|\b(display|padding|margin|background-color|border-radius|flex-direction)\s*:)"#, in: sample) {
            add(.css, 10)
        }

        // Rust signals
        if matchesRegex(#"\b(fn\s+main\s*\(|let\s+mut\s+|pub\s+fn\s+|println!\s*\(|#\[derive\(|use\s+std::|impl\s+\w+)"#, in: sample) {
            add(.rust, 14)
        }

        // Go signals
        if matchesRegex(#"(?m)^package\s+\w+"#, in: sample) { add(.go, 12) }
        if matchesRegex(#"\b(func\s+main\s*\(|fmt\.Print|go\s+func|\w+\s*:=\s*)"#, in: sample) { add(.go, 9) }

        // C / C++ signals
        if matchesRegex(#"(?m)^\s*#include\s*[<"][^>"]+[>"]"#, in: sample) { add(.cpp, 15) }
        if matchesRegex(#"\b(std::\w+|cout\s*<<|int\s+main\s*\(|nullptr|template\s*<|printf\s*\()"#, in: sample) { add(.cpp, 10) }

        // Java / Kotlin signals
        if matchesRegex(#"\b(public\s+(static\s+void\s+main|class\s+\w+)|System\.out\.print|import\s+java\.)"#, in: sample) {
            add(.java, 14)
        }
        if matchesRegex(#"\b(fun\s+main\s*\(|data\s+class\s+\w+|companion\s+object|val\s+\w+\s*:)"#, in: sample) {
            add(.java, 12)
        }

        // C# signals
        if matchesRegex(#"\b(using\s+System|Console\.Write(Line)?|namespace\s+[\w.]+|public\s+async\s+Task)"#, in: sample) {
            add(.csharp, 14)
        }

        // Ruby signals
        if matchesRegex(#"\b(attr_accessor|puts\s+|require\s+['"][\w/]+['"]|do\s*\|[^|]+\|)"#, in: sample) {
            add(.ruby, 12)
        }

        // Dockerfile signals
        if matchesRegex(#"(?m)^(FROM|WORKDIR|ENTRYPOINT|EXPOSE|COPY|ADD)\s+\S+"#, in: sample) && matchesRegex(#"(?m)^FROM\s+\S+"#, in: sample) {
            add(.dockerfile, 16)
        }

        // Shell / Bash signals
        if matchesRegex(#"\b(set\s+-[euo]+|echo\s+['"$]|chmod\s+\+x|mkdir\s+-p|\bif\s+\[\s+|\bfi\b|\bdone\b|export\s+[A-Z_]+=)"#, in: sample) {
            add(.shell, 10)
        }

        // YAML signals
        let yamlKeyLines = lines.filter { matchesRegex(#"^\s*[\w.\-]+\s*:\s*(\S.*)?$"#, in: $0) }
        if yamlKeyLines.count >= 3 && !sample.contains("{") && !sample.contains(";") && !sample.contains("<div") {
            add(.yaml, 8 + min(yamlKeyLines.count, 8))
        }

        // CSV / TSV signals
        if lines.count >= 2 && !sample.contains("{") && !sample.contains("<") && mdSignals < 4 {
            let commaCounts = lines.prefix(10).filter { !$0.isEmpty }.map { $0.filter { $0 == "," }.count }
            if let firstCount = commaCounts.first, firstCount >= 2, commaCounts.count >= 2,
               commaCounts.allSatisfy({ $0 == firstCount }) {
                add(.csv, 11)
            }
            let tabCounts = lines.prefix(10).filter { !$0.isEmpty }.map { $0.filter { $0 == "\t" }.count }
            if let firstTab = tabCounts.first, firstTab >= 2, tabCounts.count >= 2,
               tabCounts.allSatisfy({ $0 == firstTab }) {
                add(.csv, 11)
            }
        }

        // Malformed JSON fallback
        if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")) && matchesRegex(#""[^"]+"\s*:\s*("[^"]*"|\d+|true|false|null|\{|\[)"#, in: sample) {
            add(.json, 9)
        }

        if let best = scores.max(by: { $0.value < $1.value }), best.value >= 5 {
            return best.key
        }

        return .plainText
    }

    private static func matchesRegex(_ pattern: String, in text: String) -> Bool {
        guard let regex = CachedRegex.get(pattern) else { return false }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: nsRange) != nil
    }
}

enum CachedRegex {
    private static let lock = NSLock()
    private static var cache: [String: NSRegularExpression] = [:]

    static func get(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        let key = "\(options.rawValue):\(pattern)"
        lock.lock()
        if let existing = cache[key] {
            lock.unlock()
            return existing
        }
        lock.unlock()

        guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }

        lock.lock()
        cache[key] = compiled
        lock.unlock()
        return compiled
    }
}
