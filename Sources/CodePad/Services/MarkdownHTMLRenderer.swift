import Foundation

enum MarkdownHTMLRenderer {
    // MARK: - Live Preview HTML Builder (WKWebView)

    static func buildLivePreviewHTML(
        content: String,
        language: CodeLanguage,
        palette: EditorThemePalette,
        title: String
    ) -> String {
        switch language {
        case .html:
            return ensureUTF8HTMLDocument(rawHTML: content)
        case .svg:
            return buildSVGPreviewDocument(svgSource: content, palette: palette, title: title)
        case .mermaid:
            let wrappedMD = "```mermaid\n\(content)\n```"
            return buildMarkdownDocument(markdown: wrappedMD, palette: palette, title: title, forPrintOrExport: false, wordCompatible: false)
        case .csv:
            return buildCSVPreviewDocument(csvSource: content, palette: palette, title: title, wordCompatible: false)
        case .json:
            return buildJSONPreviewDocument(jsonSource: content, palette: palette, title: title)
        case .latex:
            return buildLaTeXPreviewDocument(latexSource: content, palette: palette, title: title)
        case .markdown:
            return buildMarkdownDocument(markdown: content, palette: palette, title: title, forPrintOrExport: false, wordCompatible: false)
        default:
            return buildCodeDocumentHTML(
                code: content,
                language: language,
                palette: palette,
                title: title,
                includeLineNumbers: true,
                includeHeaderMetadata: true,
                wordCompatible: false
            )
        }
    }

    // MARK: - Export HTML Builder (PDF / Standalone HTML / Word DOCX / RTF / ODT)

    static func buildExportHTML(
        content: String,
        language: CodeLanguage,
        palette: EditorThemePalette,
        title: String,
        includeLineNumbers: Bool,
        includeHeaderMetadata: Bool,
        wordCompatible: Bool
    ) -> String {
        switch language {
        case .markdown:
            return buildMarkdownDocument(
                markdown: content,
                palette: palette,
                title: title,
                forPrintOrExport: true,
                wordCompatible: wordCompatible
            )
        case .html:
            if wordCompatible {
                return ensureUTF8HTMLDocument(rawHTML: content)
            }
            return ensureUTF8PrintFriendlyHTML(rawHTML: content)
        case .svg:
            if wordCompatible {
                // Word textutil prefers source + summary if raw SVG inline isn't supported by textutil
                return buildCodeDocumentHTML(
                    code: content,
                    language: .svg,
                    palette: palette,
                    title: title,
                    includeLineNumbers: includeLineNumbers,
                    includeHeaderMetadata: includeHeaderMetadata,
                    wordCompatible: true
                )
            }
            return buildSVGExportDocument(svgSource: content, title: title)
        case .mermaid:
            if wordCompatible {
                return buildCodeDocumentHTML(
                    code: content,
                    language: .mermaid,
                    palette: palette,
                    title: title,
                    includeLineNumbers: includeLineNumbers,
                    includeHeaderMetadata: includeHeaderMetadata,
                    wordCompatible: true
                )
            }
            return buildMarkdownDocument(
                markdown: "```mermaid\n\(content)\n```",
                palette: palette,
                title: title,
                forPrintOrExport: true,
                wordCompatible: false
            )
        case .csv:
            return buildCSVPreviewDocument(csvSource: content, palette: palette, title: title, wordCompatible: wordCompatible)
        case .latex:
            if wordCompatible {
                return buildLaTeXWordDocument(latexSource: content, palette: palette, title: title)
            }
            return buildLaTeXPreviewDocument(latexSource: content, palette: palette, title: title)
        default:
            return buildCodeDocumentHTML(
                code: content,
                language: language,
                palette: palette,
                title: title,
                includeLineNumbers: includeLineNumbers,
                includeHeaderMetadata: includeHeaderMetadata,
                wordCompatible: wordCompatible
            )
        }
    }

    // MARK: - Full GitHub-Flavored Markdown (GFM) Parser & Renderer

    static func buildMarkdownDocument(
        markdown: String,
        palette: EditorThemePalette,
        title: String,
        forPrintOrExport: Bool,
        wordCompatible: Bool
    ) -> String {
        let bodyHTML = parseMarkdownToHTML(markdown, palette: palette, wordCompatible: wordCompatible)

        if wordCompatible {
            let fg = palette.isDark ? "#1E293B" : palette.plainTextHex
            return """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <title>\(SyntaxHighlighter.escapeHTML(title))</title>
            </head>
            <body style="font-family: -apple-system, 'Helvetica Neue', Arial, sans-serif; font-size: 11pt; line-height: 1.55; color: \(fg);">
            \(bodyHTML)
            </body>
            </html>
            """
        }

        let isDark = palette.isDark
        let bg = isDark ? palette.editorBackgroundHex : "#FFFFFF"
        let fg = isDark ? palette.plainTextHex : "#1F2328"
        let muted = isDark ? palette.commentHex : "#656D76"
        let cardBg = isDark ? palette.chromeBackgroundHex : "#F6F8FA"
        let border = isDark ? "#3D444D" : "#D0D7DE"
        let accent = palette.accentHex
        let hasMermaid = markdown.contains("```mermaid")
        let hasMath = markdown.contains("$$") || markdown.contains("\\(") || markdown.contains("\\[")

        let extraHeadScripts: String = {
            var scripts = ""
            if hasMath {
                scripts += """
                <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
                <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
                <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js"
                  onload="renderMathInElement(document.body,{delimiters:[{left:'$$',right:'$$',display:true},{left:'$',right:'$',display:false},{left:'\\\\[',right:'\\\\]',display:true},{left:'\\\\(',right:'\\\\)',display:false}]});"></script>
                """
            }
            if hasMermaid {
                let mTheme = isDark ? "dark" : "default"
                scripts += """
                <script type="module">
                import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
                mermaid.initialize({ startOnLoad: true, theme: '\(mTheme)' });
                </script>
                """
            }
            return scripts
        }()

        return """
        <!DOCTYPE html>
        <html lang="vi">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(SyntaxHighlighter.escapeHTML(title))</title>
        \(extraHeadScripts)
        <style>
        :root { color-scheme: \(isDark ? "dark" : "light"); }
        * { box-sizing: border-box; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        body {
            margin: 0;
            padding: \(forPrintOrExport ? "20px 28px" : "28px 36px 56px");
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
            font-size: 15px;
            line-height: 1.68;
            background: \(bg);
            color: \(fg);
            word-wrap: break-word;
        }
        .markdown-body { max-width: 880px; margin: 0 auto; }
        h1, h2, h3, h4, h5, h6 {
            margin-top: 1.45em;
            margin-bottom: 0.55em;
            font-weight: 650;
            line-height: 1.28;
            letter-spacing: -0.015em;
        }
        h1 { font-size: 1.95em; padding-bottom: 0.28em; border-bottom: 1px solid \(border); margin-top: 0.2em; }
        h2 { font-size: 1.48em; padding-bottom: 0.24em; border-bottom: 1px solid \(border); }
        h3 { font-size: 1.22em; }
        h4 { font-size: 1.05em; }
        p, ul, ol, blockquote, table, .code-block-wrap, .md-alert { margin-top: 0; margin-bottom: 1.05em; }
        a { color: \(accent); text-decoration: none; }
        a:hover { text-decoration: underline; }
        hr { border: 0; border-top: 1px solid \(border); margin: 1.8em 0; }
        code.inline-code {
            font-family: "SF Mono", Menlo, Monaco, Consolas, monospace;
            font-size: 0.87em;
            padding: 0.18em 0.42em;
            border-radius: 6px;
            background: \(cardBg);
            border: 1px solid \(border);
        }
        .code-block-wrap {
            border-radius: 10px;
            background: \(cardBg);
            border: 1px solid \(border);
            overflow: hidden;
            page-break-inside: avoid;
            break-inside: avoid;
        }
        .code-block-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 6px 12px;
            font-size: 11.5px;
            font-weight: 600;
            color: \(muted);
            border-bottom: 1px solid \(border);
            text-transform: uppercase;
            letter-spacing: 0.04em;
        }
        .copy-btn {
            display: \(forPrintOrExport ? "none" : "inline-block");
            background: transparent;
            border: 1px solid \(border);
            color: \(muted);
            border-radius: 5px;
            padding: 2px 8px;
            font-size: 11px;
            cursor: pointer;
        }
        .copy-btn:hover { color: \(fg); border-color: \(accent); }
        pre.code-pre {
            margin: 0;
            padding: 13px 16px;
            overflow-x: auto;
            font-family: "SF Mono", Menlo, Monaco, Consolas, monospace;
            font-size: 13px;
            line-height: 1.52;
            tab-size: 4;
            white-space: pre-wrap;
            word-break: break-word;
        }
        blockquote {
            margin-left: 0;
            padding: 0.55em 1.1em;
            color: \(muted);
            border-left: 4px solid \(accent);
            background: \(cardBg);
            border-radius: 0 8px 8px 0;
        }
        blockquote > :last-child { margin-bottom: 0; }
        .md-alert {
            padding: 12px 16px;
            border-left: 4px solid \(accent);
            background: \(cardBg);
            border-radius: 0 8px 8px 0;
            page-break-inside: avoid;
        }
        .md-alert-title { font-weight: 700; margin-bottom: 4px; font-size: 0.92em; }
        .md-alert-note { border-left-color: #0969DA; }
        .md-alert-tip { border-left-color: #1A7F37; }
        .md-alert-important { border-left-color: #8250DF; }
        .md-alert-warning { border-left-color: #9A6700; }
        .md-alert-caution { border-left-color: #CF222E; }
        table.md-table {
            width: 100%;
            border-collapse: collapse;
            border-spacing: 0;
            font-size: 14px;
            page-break-inside: auto;
        }
        table.md-table th, table.md-table td {
            border: 1px solid \(border);
            padding: 8px 12px;
        }
        table.md-table th {
            background: \(cardBg);
            font-weight: 600;
        }
        ul.task-list { list-style: none; padding-left: 0.4em; }
        li.task-item input[type="checkbox"] { margin-right: 8px; accent-color: \(accent); transform: scale(1.08); }
        img { max-width: 100%; border-radius: 8px; }
        .mermaid { background: \(cardBg); padding: 16px; border-radius: 10px; border: 1px solid \(border); text-align: center; }
        </style>
        <script>
        function copyCodeBlock(btn) {
            const pre = btn.closest('.code-block-wrap').querySelector('pre');
            if (!pre) return;
            navigator.clipboard?.writeText(pre.innerText);
            const old = btn.textContent;
            btn.textContent = 'Đã chép ✓';
            setTimeout(() => { btn.textContent = old; }, 1400);
        }
        </script>
        </head>
        <body>
        <article class="markdown-body">
        \(bodyHTML)
        </article>
        </body>
        </html>
        """
    }

    private static func parseMarkdownToHTML(
        _ markdown: String,
        palette: EditorThemePalette,
        wordCompatible: Bool
    ) -> String {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var html = ""
        var i = 0

        // Strip optional YAML frontmatter at top if present
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            if let endIdx = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
                i = endIdx + 1
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 1. Blank line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // 2. Fenced code block (``` or ~~~)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fenceMarker = trimmed.hasPrefix("```") ? "```" : "~~~"
                let langHint = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fenceMarker) {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                let rawCode = codeLines.joined(separator: "\n")
                let fenceLang = CodeLanguage.fromFenceAlias(langHint)

                if fenceLang == .mermaid && !wordCompatible {
                    html += "<div class=\"mermaid\">\(SyntaxHighlighter.escapeHTML(rawCode))</div>\n"
                } else if wordCompatible {
                    let wordPal = EditorThemeID.githubLight.palette
                    let highlighted = SyntaxHighlighter.highlightedHTML(
                        for: rawCode,
                        language: fenceLang,
                        palette: wordPal,
                        includeLineNumbers: false,
                        wordCompatible: true
                    )
                    html += """
                    <table width="100%" cellpadding="10" cellspacing="0" style="background-color:#F6F8FA;border:1px solid #D0D7DE;margin-bottom:12px;">
                    <tr><td style="background-color:#F6F8FA;font-family:Menlo,Consolas,monospace;font-size:9.5pt;color:#24292F;">
                    \(highlighted)
                    </td></tr></table>
                    """
                } else {
                    let highlighted = SyntaxHighlighter.highlightedHTML(
                        for: rawCode,
                        language: fenceLang,
                        palette: palette,
                        includeLineNumbers: false,
                        wordCompatible: false
                    )
                    let badge = langHint.isEmpty ? "CODE" : SyntaxHighlighter.escapeHTML(langHint)
                    html += """
                    <div class="code-block-wrap">
                      <div class="code-block-header">
                        <span>\(badge)</span>
                        <button class="copy-btn" onclick="copyCodeBlock(this)">Sao chép</button>
                      </div>
                      <pre class="code-pre"><code>\(highlighted)</code></pre>
                    </div>
                    """
                }
                continue
            }

            // 3. Display Math Block $$ ... $$
            if trimmed.hasPrefix("$$") {
                if trimmed.count > 4 && trimmed.hasSuffix("$$") {
                    html += "<p>\(SyntaxHighlighter.escapeHTML(trimmed))</p>\n"
                    i += 1
                    continue
                }
                var mathLines = [line]
                i += 1
                while i < lines.count {
                    mathLines.append(lines[i])
                    if lines[i].trimmingCharacters(in: .whitespaces).hasSuffix("$$") {
                        i += 1
                        break
                    }
                    i += 1
                }
                html += "<p>\(SyntaxHighlighter.escapeHTML(mathLines.joined(separator: "\n")))</p>\n"
                continue
            }

            // 4. ATX Headings (# ... ######)
            if let headingMatch = matchATXHeading(trimmed) {
                let tag = "h\(headingMatch.level)"
                let inner = renderInlineMarkdown(headingMatch.text, wordCompatible: wordCompatible)
                html += "<\(tag)>\(inner)</\(tag)>\n"
                i += 1
                continue
            }

            // 5. Horizontal Rule (---, ***, ___)
            if isHorizontalRule(trimmed) {
                html += "<hr>\n"
                i += 1
                continue
            }

            // 6. GFM Pipe Table
            if trimmed.contains("|"), i + 1 < lines.count, isTableSeparatorRow(lines[i + 1]) {
                let headerCells = splitPipeRow(lines[i])
                let alignments = parseTableAlignments(lines[i + 1], columnCount: headerCells.count)
                i += 2
                var bodyRows: [[String]] = []
                while i < lines.count {
                    let rowTrim = lines[i].trimmingCharacters(in: .whitespaces)
                    guard !rowTrim.isEmpty && rowTrim.contains("|") else { break }
                    bodyRows.append(splitPipeRow(lines[i]))
                    i += 1
                }
                if wordCompatible {
                    html += "<table width=\"100%\" cellpadding=\"6\" cellspacing=\"0\" border=\"1\" style=\"border-collapse:collapse;border:1px solid #D0D7DE;margin-bottom:12px;\"><thead><tr>"
                } else {
                    html += "<table class=\"md-table\"><thead><tr>"
                }
                for (colIdx, cell) in headerCells.enumerated() {
                    let align = colIdx < alignments.count ? alignments[colIdx] : "left"
                    let bgAttr = wordCompatible ? "background-color:#F6F8FA;border:1px solid #D0D7DE;padding:6px 10px;" : ""
                    html += "<th style=\"text-align:\(align);\(bgAttr)\">\(renderInlineMarkdown(cell, wordCompatible: wordCompatible))</th>"
                }
                html += "</tr></thead><tbody>"
                for row in bodyRows {
                    html += "<tr>"
                    for colIdx in 0..<headerCells.count {
                        let cell = colIdx < row.count ? row[colIdx] : ""
                        let align = colIdx < alignments.count ? alignments[colIdx] : "left"
                        let tdStyle = wordCompatible ? "border:1px solid #D0D7DE;padding:6px 10px;" : ""
                        html += "<td style=\"text-align:\(align);\(tdStyle)\">\(renderInlineMarkdown(cell, wordCompatible: wordCompatible))</td>"
                    }
                    html += "</tr>"
                }
                html += "</tbody></table>\n"
                continue
            }

            // 7. Blockquote & GitHub Alerts (> [!NOTE], > [!TIP], ...)
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let qt = lines[i].trimmingCharacters(in: .whitespaces)
                    guard qt.hasPrefix(">") else { break }
                    var stripped = String(qt.dropFirst())
                    if stripped.hasPrefix(" ") { stripped.removeFirst() }
                    quoteLines.append(stripped)
                    i += 1
                }
                if let firstQ = quoteLines.first,
                   let alertKind = parseGitHubAlertHeader(firstQ) {
                    let bodyText = quoteLines.dropFirst().joined(separator: " ")
                    let inner = renderInlineMarkdown(bodyText, wordCompatible: wordCompatible)
                    if wordCompatible {
                        html += "<p style=\"margin-left:14px;color:#334155;\"><b>[\(alertKind.title)]</b> \(inner)</p>\n"
                    } else {
                        html += """
                        <div class="md-alert md-alert-\(alertKind.cssSlug)">
                          <div class="md-alert-title">\(alertKind.title)</div>
                          <div>\(inner)</div>
                        </div>
                        """
                    }
                } else {
                    let inner = quoteLines.map { renderInlineMarkdown($0, wordCompatible: wordCompatible) }.joined(separator: "<br>")
                    html += "<blockquote><p>\(inner)</p></blockquote>\n"
                }
                continue
            }

            // 8. Unordered / Task List (- , * , + )
            if isUnorderedListItem(trimmed) != nil {
                var itemsHTML = ""
                var hasTasks = false
                while i < lines.count, let itemBody = isUnorderedListItem(lines[i].trimmingCharacters(in: .whitespaces)) {
                    if itemBody.hasPrefix("[x] ") || itemBody.hasPrefix("[X] ") {
                        hasTasks = true
                        let text = renderInlineMarkdown(String(itemBody.dropFirst(4)), wordCompatible: wordCompatible)
                        itemsHTML += wordCompatible
                            ? "<li>☑ \(text)</li>"
                            : "<li class=\"task-item\"><input type=\"checkbox\" checked disabled>\(text)</li>"
                    } else if itemBody.hasPrefix("[ ] ") {
                        hasTasks = true
                        let text = renderInlineMarkdown(String(itemBody.dropFirst(4)), wordCompatible: wordCompatible)
                        itemsHTML += wordCompatible
                            ? "<li>☐ \(text)</li>"
                            : "<li class=\"task-item\"><input type=\"checkbox\" disabled>\(text)</li>"
                    } else {
                        itemsHTML += "<li>\(renderInlineMarkdown(itemBody, wordCompatible: wordCompatible))</li>"
                    }
                    i += 1
                }
                let cls = (hasTasks && !wordCompatible) ? " class=\"task-list\"" : ""
                html += "<ul\(cls)>\(itemsHTML)</ul>\n"
                continue
            }

            // 9. Ordered List (1. , 2. , ...)
            if isOrderedListItem(trimmed) != nil {
                var itemsHTML = ""
                while i < lines.count, let itemBody = isOrderedListItem(lines[i].trimmingCharacters(in: .whitespaces)) {
                    itemsHTML += "<li>\(renderInlineMarkdown(itemBody, wordCompatible: wordCompatible))</li>"
                    i += 1
                }
                html += "<ol>\(itemsHTML)</ol>\n"
                continue
            }

            // 10. Raw safe HTML block passthrough (e.g. <details>, <div>, <table>)
            if !wordCompatible && trimmed.hasPrefix("<") && !trimmed.hasPrefix("<http") {
                html += "\(line)\n"
                i += 1
                continue
            }

            // 11. Standard Paragraph (merge consecutive prose lines)
            var paraLines: [String] = []
            while i < lines.count {
                let pTrim = lines[i].trimmingCharacters(in: .whitespaces)
                if pTrim.isEmpty
                    || pTrim.hasPrefix("```")
                    || pTrim.hasPrefix("~~~")
                    || pTrim.hasPrefix(">")
                    || matchATXHeading(pTrim) != nil
                    || isHorizontalRule(pTrim)
                    || isUnorderedListItem(pTrim) != nil
                    || isOrderedListItem(pTrim) != nil
                    || (pTrim.contains("|") && i + 1 < lines.count && isTableSeparatorRow(lines[i + 1])) {
                    break
                }
                paraLines.append(pTrim)
                i += 1
            }
            let joined = paraLines.map { renderInlineMarkdown($0, wordCompatible: wordCompatible) }.joined(separator: " ")
            html += "<p>\(joined)</p>\n"
        }

        return html
    }

    private static func renderInlineMarkdown(_ raw: String, wordCompatible: Bool) -> String {
        // Protect inline code spans (`...`) with placeholders before escaping/styling
        var codePlaceholders: [String] = []
        var working = raw

        if let codeRegex = CachedRegex.get(#"`([^`]+)`"#) {
            let matches = codeRegex.matches(in: working, options: [], range: NSRange(working.startIndex..<working.endIndex, in: working)).reversed()
            for m in matches {
                guard let fullR = Range(m.range, in: working),
                      let innerR = Range(m.range(at: 1), in: working) else { continue }
                let codeContent = SyntaxHighlighter.escapeHTML(String(working[innerR]))
                let token = "\u{0002}CODE\(codePlaceholders.count)\u{0003}"
                let rendered = wordCompatible
                    ? "<span style=\"font-family:Menlo,Consolas,monospace;font-size:9.5pt;background-color:#F1F5F9;color:#0F172A;\">\(codeContent)</span>"
                    : "<code class=\"inline-code\">\(codeContent)</code>"
                codePlaceholders.append(rendered)
                working.replaceSubrange(fullR, with: token)
            }
        }

        var escaped = SyntaxHighlighter.escapeHTML(working)

        // Images ![alt](url)
        if let imgRegex = CachedRegex.get(#"!\[([^\]]*)\]\(([^)]+)\)"#) {
            escaped = imgRegex.stringByReplacingMatches(
                in: escaped,
                options: [],
                range: NSRange(escaped.startIndex..<escaped.endIndex, in: escaped),
                withTemplate: #"<img src="$2" alt="$1">"#
            )
        }

        // Links [label](url)
        if let linkRegex = CachedRegex.get(#"\[([^\]]+)\]\(([^)]+)\)"#) {
            escaped = linkRegex.stringByReplacingMatches(
                in: escaped,
                options: [],
                range: NSRange(escaped.startIndex..<escaped.endIndex, in: escaped),
                withTemplate: #"<a href="$2" target="_blank" rel="noopener">$1</a>"#
            )
        }

        // Bold + Italic ***text***
        if let biRegex = CachedRegex.get(#"\*\*\*([^*]+)\*\*\*"#) {
            escaped = biRegex.stringByReplacingMatches(
                in: escaped,
                options: [],
                range: NSRange(escaped.startIndex..<escaped.endIndex, in: escaped),
                withTemplate: "<strong><em>$1</em></strong>"
            )
        }

        // Bold **text** or __text__
        if let boldRegex = CachedRegex.get(#"\*\*([^*]+)\*\*|__([^_]+)__"#) {
            escaped = boldRegex.stringByReplacingMatches(
                in: escaped,
                options: [],
                range: NSRange(escaped.startIndex..<escaped.endIndex, in: escaped),
                withTemplate: "<strong>$1$2</strong>"
            )
        }

        // Italic *text*
        if let italicRegex = CachedRegex.get(#"(?<!\*)\*([^*]+)\*(?!\*)"#) {
            escaped = italicRegex.stringByReplacingMatches(
                in: escaped,
                options: [],
                range: NSRange(escaped.startIndex..<escaped.endIndex, in: escaped),
                withTemplate: "<em>$1</em>"
            )
        }

        // Strikethrough ~~text~~
        if let strikeRegex = CachedRegex.get(#"~~([^~]+)~~"#) {
            escaped = strikeRegex.stringByReplacingMatches(
                in: escaped,
                options: [],
                range: NSRange(escaped.startIndex..<escaped.endIndex, in: escaped),
                withTemplate: "<del>$1</del>"
            )
        }

        // Restore inline code placeholders
        for (idx, htmlSnippet) in codePlaceholders.enumerated() {
            escaped = escaped.replacingOccurrences(of: "\u{0002}CODE\(idx)\u{0003}", with: htmlSnippet)
        }
        return escaped
    }

    // MARK: - Code Document HTML Builder (For Source Code -> PDF / DOCX / RTF / HTML)

    static func buildCodeDocumentHTML(
        code: String,
        language: CodeLanguage,
        palette: EditorThemePalette,
        title: String,
        includeLineNumbers: Bool,
        includeHeaderMetadata: Bool,
        wordCompatible: Bool
    ) -> String {
        let lineCount = max(1, code.components(separatedBy: "\n").count)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "vi_VN")
        dateFormatter.dateFormat = "HH:mm • dd/MM/yyyy"
        let timestamp = dateFormatter.string(from: Date())

        if wordCompatible {
            let highlighted = SyntaxHighlighter.highlightedHTML(
                for: code,
                language: language,
                palette: palette,
                includeLineNumbers: includeLineNumbers,
                wordCompatible: true
            )
            let headerHTML = includeHeaderMetadata ? """
            <h2 style="margin-bottom:4px;color:#0F172A;">\(SyntaxHighlighter.escapeHTML(title))</h2>
            <p style="margin-top:0;margin-bottom:14px;font-size:9.5pt;color:#64748B;">
            Ngôn ngữ: <b>\(SyntaxHighlighter.escapeHTML(language.displayName))</b> &nbsp;•&nbsp; \(lineCount) dòng &nbsp;•&nbsp; Xuất từ CodePad lúc \(timestamp)
            </p>
            """ : ""

            return """
            <!DOCTYPE html>
            <html>
            <head><meta charset="utf-8"><title>\(SyntaxHighlighter.escapeHTML(title))</title></head>
            <body style="font-family:'Helvetica Neue',Arial,sans-serif;font-size:10.5pt;color:\(palette.plainTextHex);">
            \(headerHTML)
            <table width="100%" cellpadding="12" cellspacing="0" style="background-color:\(palette.editorBackgroundHex);border:1px solid #CBD5E1;">
            <tr><td style="background-color:\(palette.editorBackgroundHex);font-family:Menlo,Consolas,monospace;font-size:9.5pt;line-height:1.45;color:\(palette.plainTextHex);">
            \(highlighted)
            </td></tr>
            </table>
            </body>
            </html>
            """
        }

        let highlightedTable = SyntaxHighlighter.highlightedHTML(
            for: code,
            language: language,
            palette: palette,
            includeLineNumbers: includeLineNumbers,
            wordCompatible: false
        )
        let border = palette.isDark ? "#3B4048" : "#D0D7DE"
        let headerHTML = includeHeaderMetadata ? """
        <div class="doc-meta">
          <div class="doc-title">\(SyntaxHighlighter.escapeHTML(title))</div>
          <div class="doc-sub">\(SyntaxHighlighter.escapeHTML(language.displayName)) • \(lineCount) dòng • \(timestamp)</div>
        </div>
        """ : ""

        return """
        <!DOCTYPE html>
        <html lang="vi">
        <head>
        <meta charset="utf-8">
        <title>\(SyntaxHighlighter.escapeHTML(title))</title>
        <style>
        * { box-sizing: border-box; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        body {
            margin: 0;
            padding: 24px 28px;
            background: \(palette.isDark ? palette.chromeBackgroundHex : "#FFFFFF");
            color: \(palette.plainTextHex);
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
        }
        .doc-meta {
            display: flex;
            align-items: baseline;
            justify-content: space-between;
            margin-bottom: 14px;
            padding-bottom: 10px;
            border-bottom: 1px solid \(border);
        }
        .doc-title { font-size: 16px; font-weight: 650; }
        .doc-sub { font-size: 12px; color: \(palette.gutterTextHex); }
        .code-card {
            background: \(palette.editorBackgroundHex);
            border: 1px solid \(border);
            border-radius: 10px;
            padding: 14px 12px;
            overflow-x: auto;
        }
        table.code-lines {
            width: 100%;
            border-collapse: collapse;
            font-family: "SF Mono", Menlo, Monaco, Consolas, monospace;
            font-size: 12px;
            line-height: 1.5;
        }
        table.code-lines td.ln {
            width: 1%;
            white-space: nowrap;
            text-align: right;
            padding: 0 14px 0 4px;
            color: \(palette.gutterTextHex);
            user-select: none;
            vertical-align: top;
        }
        table.code-lines td.lc {
            white-space: pre-wrap;
            word-break: break-word;
            color: \(palette.plainTextHex);
            vertical-align: top;
        }
        </style>
        </head>
        <body>
        \(headerHTML)
        <div class="code-card">
        \(highlightedTable)
        </div>
        </body>
        </html>
        """
    }

    // MARK: - Specialized Previews (HTML, SVG, CSV, JSON, LaTeX)

    private static func ensureUTF8HTMLDocument(rawHTML: String) -> String {
        let lower = rawHTML.lowercased()
        if lower.contains("<meta charset") || lower.contains("charset=") {
            return rawHTML
        }
        if let headRange = rawHTML.range(of: "<head>", options: [.caseInsensitive]) {
            var copy = rawHTML
            copy.insert(contentsOf: "<meta charset=\"utf-8\">", at: headRange.upperBound)
            return copy
        }
        return """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body>
        \(rawHTML)
        </body>
        </html>
        """
    }

    private static func ensureUTF8PrintFriendlyHTML(rawHTML: String) -> String {
        let base = ensureUTF8HTMLDocument(rawHTML: rawHTML)
        let printCSS = "<style>*{-webkit-print-color-adjust:exact;print-color-adjust:exact;}</style>"
        if let headClose = base.range(of: "</head>", options: [.caseInsensitive]) {
            var copy = base
            copy.insert(contentsOf: printCSS, at: headClose.lowerBound)
            return copy
        }
        return printCSS + base
    }

    private static func buildSVGPreviewDocument(svgSource: String, palette: EditorThemePalette, title: String) -> String {
        let bg = palette.isDark ? "#1E1F1C" : "#F8FAFC"
        let fg = palette.plainTextHex
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(SyntaxHighlighter.escapeHTML(title))</title>
        <style>
        body {
            margin: 0;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            background: \(bg);
            color: \(fg);
            font-family: -apple-system, sans-serif;
        }
        .toolbar {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 8px 14px;
            font-size: 12px;
            border-bottom: 1px solid rgba(128,128,128,0.22);
        }
        .canvas {
            flex: 1;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 28px;
            overflow: auto;
            background-image: linear-gradient(45deg, rgba(128,128,128,0.09) 25%, transparent 25%),
                              linear-gradient(-45deg, rgba(128,128,128,0.09) 25%, transparent 25%),
                              linear-gradient(45deg, transparent 75%, rgba(128,128,128,0.09) 75%),
                              linear-gradient(-45deg, transparent 75%, rgba(128,128,128,0.09) 75%);
            background-size: 20px 20px;
            background-position: 0 0, 0 10px, 10px -10px, -10px 0px;
        }
        #svg-wrap { transition: transform 0.12s ease; transform-origin: center center; }
        #svg-wrap svg { max-width: 100%; height: auto; }
        </style>
        </head>
        <body>
        <div class="toolbar">
          <span><strong>SVG Vector Preview</strong></span>
          <label style="margin-left:auto;">Thu phóng:
            <input type="range" min="25" max="300" value="100" oninput="document.getElementById('svg-wrap').style.transform='scale('+(this.value/100)+')';document.getElementById('zv').textContent=this.value+'%';">
          </label>
          <span id="zv">100%</span>
        </div>
        <div class="canvas">
          <div id="svg-wrap">\(svgSource)</div>
        </div>
        </body>
        </html>
        """
    }

    private static func buildSVGExportDocument(svgSource: String, title: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><title>\(SyntaxHighlighter.escapeHTML(title))</title>
        <style>body{margin:32px;display:flex;justify-content:center;align-items:center;}svg{max-width:100%;height:auto;}</style>
        </head>
        <body>\(svgSource)</body>
        </html>
        """
    }

    private static func buildCSVPreviewDocument(
        csvSource: String,
        palette: EditorThemePalette,
        title: String,
        wordCompatible: Bool
    ) -> String {
        let rows = parseCSVRows(csvSource)
        guard let header = rows.first else {
            return "<p>Chưa có dữ liệu bảng CSV/TSV.</p>"
        }
        let dataRows = Array(rows.dropFirst())

        if wordCompatible {
            var tbl = "<h2>\(SyntaxHighlighter.escapeHTML(title))</h2><table width=\"100%\" cellpadding=\"6\" cellspacing=\"0\" border=\"1\" style=\"border-collapse:collapse;border:1px solid #CBD5E1;font-family:'Helvetica Neue',Arial,sans-serif;font-size:10pt;\"><thead><tr>"
            for col in header {
                tbl += "<th style=\"background-color:#F1F5F9;border:1px solid #CBD5E1;text-align:left;\">\(SyntaxHighlighter.escapeHTML(col))</th>"
            }
            tbl += "</tr></thead><tbody>"
            for row in dataRows {
                tbl += "<tr>"
                for i in 0..<header.count {
                    let val = i < row.count ? row[i] : ""
                    tbl += "<td style=\"border:1px solid #CBD5E1;\">\(SyntaxHighlighter.escapeHTML(val))</td>"
                }
                tbl += "</tr>"
            }
            tbl += "</tbody></table>"
            return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>\(tbl)</body></html>"
        }

        let isDark = palette.isDark
        let bg = isDark ? palette.editorBackgroundHex : "#FFFFFF"
        let fg = isDark ? palette.plainTextHex : "#1E293B"
        let headBg = isDark ? palette.chromeBackgroundHex : "#F8FAFC"
        let border = isDark ? "#3D444D" : "#E2E8F0"

        var tableHTML = "<table><thead><tr>"
        for col in header {
            tableHTML += "<th>\(SyntaxHighlighter.escapeHTML(col))</th>"
        }
        tableHTML += "</tr></thead><tbody>"
        for row in dataRows {
            tableHTML += "<tr>"
            for idx in 0..<header.count {
                let cell = idx < row.count ? row[idx] : ""
                tableHTML += "<td>\(SyntaxHighlighter.escapeHTML(cell))</td>"
            }
            tableHTML += "</tr>"
        }
        tableHTML += "</tbody></table>"

        return """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8">
        <style>
        body { margin: 0; padding: 20px 24px; background: \(bg); color: \(fg); font-family: -apple-system, sans-serif; font-size: 13.5px; }
        .meta { margin-bottom: 12px; font-size: 12px; opacity: 0.72; }
        table { width: 100%; border-collapse: collapse; }
        th, td { border: 1px solid \(border); padding: 8px 11px; text-align: left; }
        th { background: \(headBg); position: sticky; top: 0; font-weight: 600; }
        tr:nth-child(even) td { background: rgba(128,128,128,0.05); }
        </style>
        </head>
        <body>
        <div class="meta">Bảng CSV/TSV • \(header.count) cột × \(dataRows.count) hàng dữ liệu</div>
        \(tableHTML)
        </body>
        </html>
        """
    }

    private static func buildJSONPreviewDocument(jsonSource: String, palette: EditorThemePalette, title: String) -> String {
        var pretty = jsonSource
        var statusBadge = "<span style=\"color:#22C55E;font-weight:600;\">✓ JSON Hợp lệ</span>"
        if let data = jsonSource.data(using: .utf8) {
            do {
                let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
                let formatted = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                pretty = String(data: formatted, encoding: .utf8) ?? jsonSource
            } catch {
                statusBadge = "<span style=\"color:#EF4444;font-weight:600;\">⚠ Lỗi cú pháp JSON: \(SyntaxHighlighter.escapeHTML(error.localizedDescription))</span>"
            }
        }
        let highlighted = SyntaxHighlighter.highlightedHTML(for: pretty, language: .json, palette: palette, includeLineNumbers: true, wordCompatible: false)
        return """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8">
        <style>
        body { margin: 0; padding: 18px 22px; background: \(palette.editorBackgroundHex); color: \(palette.plainTextHex); font-family: -apple-system, sans-serif; }
        .bar { font-size: 12.5px; margin-bottom: 12px; padding-bottom: 8px; border-bottom: 1px solid rgba(128,128,128,0.22); }
        table.code-lines { width: 100%; border-collapse: collapse; font-family: "SF Mono", Menlo, monospace; font-size: 12.5px; line-height: 1.5; }
        td.ln { width: 1%; text-align: right; padding-right: 14px; color: \(palette.gutterTextHex); user-select: none; vertical-align: top; }
        td.lc { white-space: pre-wrap; word-break: break-word; }
        </style>
        </head>
        <body>
        <div class="bar">\(statusBadge) &nbsp;•&nbsp; Định dạng Pretty-Print tự động</div>
        \(highlighted)
        </body>
        </html>
        """
    }

    private static func buildLaTeXPreviewDocument(latexSource: String, palette: EditorThemePalette, title: String) -> String {
        let converted = convertBasicLaTeXToHTML(latexSource)
        let isDark = palette.isDark
        let bg = isDark ? palette.editorBackgroundHex : "#FFFFFF"
        let fg = isDark ? palette.plainTextHex : "#111827"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js"
          onload="renderMathInElement(document.body,{delimiters:[{left:'$$',right:'$$',display:true},{left:'$',right:'$',display:false},{left:'\\\\[',right:'\\\\]',display:true},{left:'\\\\(',right:'\\\\)',display:false}]});"></script>
        <style>
        body { margin: 0; padding: 36px 44px; background: \(bg); color: \(fg); font-family: Georgia, "Times New Roman", serif; font-size: 16px; line-height: 1.72; max-width: 820px; margin-inline: auto; }
        h1, h2, h3 { font-family: -apple-system, "Helvetica Neue", sans-serif; }
        </style>
        </head>
        <body>\(converted)</body>
        </html>
        """
    }

    private static func buildLaTeXWordDocument(latexSource: String, palette: EditorThemePalette, title: String) -> String {
        let converted = convertBasicLaTeXToHTML(latexSource)
        return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body style=\"font-family:Georgia,serif;font-size:11.5pt;\">\(converted)</body></html>"
    }

    private static func convertBasicLaTeXToHTML(_ src: String) -> String {
        var text = src
        if let docRange = text.range(of: "\\begin{document}"),
           let endRange = text.range(of: "\\end{document}") {
            text = String(text[docRange.upperBound..<endRange.lowerBound])
        }
        var html = SyntaxHighlighter.escapeHTML(text)
        let replacements: [(String, String)] = [
            (#"\\section\*?\{([^}]+)\}"#, "<h2>$1</h2>"),
            (#"\\subsection\*?\{([^}]+)\}"#, "<h3>$1</h3>"),
            (#"\\subsubsection\*?\{([^}]+)\}"#, "<h4>$1</h4>"),
            (#"\\textbf\{([^}]+)\}"#, "<strong>$1</strong>"),
            (#"\\textit\{([^}]+)\}"#, "<em>$1</em>"),
            (#"\\emph\{([^}]+)\}"#, "<em>$1</em>"),
            (#"\\begin\{itemize\}"#, "<ul>"),
            (#"\\end\{itemize\}"#, "</ul>"),
            (#"\\begin\{enumerate\}"#, "<ol>"),
            (#"\\end\{enumerate\}"#, "</ol>"),
            (#"\\item\s+"#, "<li>"),
            (#"\n\n+"#, "</p><p>")
        ]
        for (pat, tpl) in replacements {
            if let rx = CachedRegex.get(pat) {
                html = rx.stringByReplacingMatches(in: html, options: [], range: NSRange(html.startIndex..<html.endIndex, in: html), withTemplate: tpl)
            }
        }
        return "<p>\(html)</p>"
    }

    // MARK: - Markdown Block Helpers

    private static func matchATXHeading(_ trimmed: String) -> (level: Int, text: String)? {
        var hashes = 0
        for ch in trimmed {
            if ch == "#" { hashes += 1 } else { break }
        }
        guard (1...6).contains(hashes), trimmed.count > hashes else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.first == " " || rest.first == "\t" else { return nil }
        return (hashes, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy({ $0 == "-" })
            || compact.allSatisfy({ $0 == "*" })
            || compact.allSatisfy({ $0 == "_" })
    }

    private static func isUnorderedListItem(_ trimmed: String) -> String? {
        for prefix in ["- ", "* ", "+ "] {
            if trimmed.hasPrefix(prefix) {
                return String(trimmed.dropFirst(2))
            }
        }
        return nil
    }

    private static func isOrderedListItem(_ trimmed: String) -> String? {
        guard let dotIdx = trimmed.firstIndex(of: ".") else { return nil }
        let numPart = trimmed[..<dotIdx]
        guard !numPart.isEmpty, numPart.allSatisfy(\.isNumber) else { return nil }
        let afterDot = trimmed[trimmed.index(after: dotIdx)...]
        guard afterDot.first == " " else { return nil }
        return String(afterDot.dropFirst())
    }

    private static func isTableSeparatorRow(_ line: String) -> Bool {
        let cells = splitPipeRow(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let t = cell.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return false }
            let stripped = t.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
            return stripped.isEmpty && t.contains("-")
        }
    }

    private static func splitPipeRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseTableAlignments(_ sepLine: String, columnCount: Int) -> [String] {
        let raw = splitPipeRow(sepLine)
        return (0..<columnCount).map { idx in
            guard idx < raw.count else { return "left" }
            let c = raw[idx].trimmingCharacters(in: .whitespaces)
            if c.hasPrefix(":") && c.hasSuffix(":") { return "center" }
            if c.hasSuffix(":") { return "right" }
            return "left"
        }
    }

    private static func parseGitHubAlertHeader(_ firstLine: String) -> (cssSlug: String, title: String)? {
        let upper = firstLine.trimmingCharacters(in: .whitespaces).uppercased()
        switch upper {
        case "[!NOTE]": return ("note", "Ghi chú")
        case "[!TIP]": return ("tip", "Mẹo hay")
        case "[!IMPORTANT]": return ("important", "Quan trọng")
        case "[!WARNING]": return ("warning", "Cảnh báo")
        case "[!CAUTION]": return ("caution", "Thận trọng")
        default: return nil
        }
    }

    private static func parseCSVRows(_ raw: String) -> [[String]] {
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").split(whereSeparator: \.isNewline).map(String.init)
        guard let first = lines.first else { return [] }
        let delimiter: Character = first.contains("\t") ? "\t" : ","
        return lines.map { line in
            var cols: [String] = []
            var cur = ""
            var inQuotes = false
            for ch in line {
                if ch == "\"" {
                    inQuotes.toggle()
                } else if ch == delimiter && !inQuotes {
                    cols.append(cur.trimmingCharacters(in: .whitespaces))
                    cur = ""
                } else {
                    cur.append(ch)
                }
            }
            cols.append(cur.trimmingCharacters(in: .whitespaces))
            return cols
        }
    }
}
