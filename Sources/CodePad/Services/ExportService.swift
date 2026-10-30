import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers
import WebKit

@MainActor
final class ExportService {
    static let shared = ExportService()

    private var activePDFExporter: OffscreenWebPDFExporter?

    private init() {}

    // MARK: - Interactive Save Panel Export

    func promptAndExport(tab: DocumentTab, format: ExportFormat, preferences: EditorPreferences) {
        let ext = format.fileExtension(for: tab.language)
        let panel = NSSavePanel()
        panel.title = "Xuất tài liệu — \(format.displayName)"
        panel.nameFieldLabel = "Tên tệp xuất:"
        panel.nameFieldStringValue = "\(tab.suggestedBaseFilename).\(ext)"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let utType = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [utType]
        }

        let response = panel.runModal()
        guard response == .OK, let destinationURL = panel.url else { return }

        WorkspaceStore.shared.showToast("Đang xuất tệp \(destinationURL.lastPathComponent)...")

        Task { @MainActor in
            do {
                try await exportDocument(
                    tab: tab,
                    format: format,
                    to: destinationURL,
                    preferences: preferences
                )
                WorkspaceStore.shared.showToast(
                    "Đã xuất thành công: \(destinationURL.lastPathComponent)",
                    revealURL: destinationURL
                )
            } catch {
                WorkspaceStore.shared.showToast(
                    "Xuất tệp thất bại: \(error.localizedDescription)",
                    isError: true
                )
            }
        }
    }

    // MARK: - Programmatic / Direct Export Engine

    func exportDocument(
        tab: DocumentTab,
        format: ExportFormat,
        to destinationURL: URL,
        preferences: EditorPreferences
    ) async throws {
        let exportPalette: EditorThemePalette = {
            if preferences.exportUseLightTheme && format != .pngCard {
                return EditorThemeID.githubLight.palette
            }
            return WorkspaceStore.shared.effectivePalette
        }()

        switch format {
        case .sourceFile:
            try tab.content.write(to: destinationURL, atomically: true, encoding: .utf8)

        case .html:
            let html = MarkdownHTMLRenderer.buildExportHTML(
                content: tab.content,
                language: tab.language,
                palette: exportPalette,
                title: tab.displayTitle,
                includeLineNumbers: preferences.exportIncludeLineNumbers,
                includeHeaderMetadata: preferences.exportIncludeHeaderMetadata,
                wordCompatible: false
            )
            try html.write(to: destinationURL, atomically: true, encoding: .utf8)

        case .docx:
            try await convertHTMLViaTextUtil(
                tab: tab,
                palette: EditorThemeID.githubLight.palette,
                preferences: preferences,
                textUtilFormat: "docx",
                destinationURL: destinationURL
            )

        case .rtf:
            try await convertHTMLViaTextUtil(
                tab: tab,
                palette: EditorThemeID.githubLight.palette,
                preferences: preferences,
                textUtilFormat: "rtf",
                destinationURL: destinationURL
            )

        case .odt:
            try await convertHTMLViaTextUtil(
                tab: tab,
                palette: EditorThemeID.githubLight.palette,
                preferences: preferences,
                textUtilFormat: "odt",
                destinationURL: destinationURL
            )

        case .pdf:
            let html = MarkdownHTMLRenderer.buildExportHTML(
                content: tab.content,
                language: tab.language,
                palette: exportPalette,
                title: tab.displayTitle,
                includeLineNumbers: preferences.exportIncludeLineNumbers,
                includeHeaderMetadata: preferences.exportIncludeHeaderMetadata,
                wordCompatible: false
            )
            try await exportHTMLToPDF(html: html, baseURL: tab.fileURL?.deletingLastPathComponent(), destinationURL: destinationURL)

        case .pngCard:
            let pngData = try renderRetinaCodeCardPNG(
                code: tab.content,
                language: tab.language,
                title: tab.displayTitle,
                palette: WorkspaceStore.shared.effectivePalette,
                fontFamily: preferences.fontFamily,
                fontSize: CGFloat(preferences.fontSize)
            )
            try pngData.write(to: destinationURL, options: .atomic)
        }
    }

    // MARK: - Rich Clipboard Helpers (Copy Highlighted RTF & Copy Code Card Image)

    func copyHighlightedRichTextToClipboard(tab: DocumentTab, preferences: EditorPreferences) {
        let palette = preferences.exportUseLightTheme ? EditorThemeID.githubLight.palette : WorkspaceStore.shared.effectivePalette
        let attr = SyntaxHighlighter.attributedString(
            for: tab.content,
            language: tab.language,
            palette: palette,
            fontFamily: preferences.fontFamily,
            fontSize: CGFloat(preferences.fontSize)
        )
        let pb = NSPasteboard.general
        pb.clearContents()
        if let rtfData = try? attr.data(
            from: NSRange(location: 0, length: attr.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            pb.setData(rtfData, forType: .rtf)
        }
        pb.setString(tab.content, forType: .string)
        WorkspaceStore.shared.showToast("Đã chép Rich Text giữ nguyên màu Highlight (dán thẳng vào Word / Mail / Pages)")
    }

    func copyCodeCardImageToClipboard(tab: DocumentTab, preferences: EditorPreferences) {
        do {
            let pngData = try renderRetinaCodeCardPNG(
                code: tab.content,
                language: tab.language,
                title: tab.displayTitle,
                palette: WorkspaceStore.shared.effectivePalette,
                fontFamily: preferences.fontFamily,
                fontSize: CGFloat(preferences.fontSize)
            )
            guard let img = NSImage(data: pngData) else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([img])
            WorkspaceStore.shared.showToast("Đã chép ảnh chụp Code sắc nét vào Clipboard!")
        } catch {
            WorkspaceStore.shared.showToast("Không thể tạo ảnh Code: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - Native macOS textutil HTML -> DOCX / RTF / ODT

    private func convertHTMLViaTextUtil(
        tab: DocumentTab,
        palette: EditorThemePalette,
        preferences: EditorPreferences,
        textUtilFormat: String,
        destinationURL: URL
    ) async throws {
        let wordHTML = MarkdownHTMLRenderer.buildExportHTML(
            content: tab.content,
            language: tab.language,
            palette: palette,
            title: tab.displayTitle,
            includeLineNumbers: preferences.exportIncludeLineNumbers,
            includeHeaderMetadata: preferences.exportIncludeHeaderMetadata,
            wordCompatible: true
        )

        let tempHTMLURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CodePadExport-\(UUID().uuidString).html")
        try wordHTML.write(to: tempHTMLURL, atomically: true, encoding: .utf8)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                defer { try? FileManager.default.removeItem(at: tempHTMLURL) }

                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
                proc.arguments = [
                    "-format", "html",
                    "-inputencoding", "UTF-8",
                    "-convert", textUtilFormat,
                    tempHTMLURL.path,
                    "-output", destinationURL.path
                ]
                let errPipe = Pipe()
                proc.standardError = errPipe

                do {
                    try proc.run()
                    proc.waitUntilExit()
                    if proc.terminationStatus == 0 && FileManager.default.fileExists(atPath: destinationURL.path) {
                        continuation.resume()
                    } else {
                        let errStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        throw NSError(
                            domain: "CodePadExport",
                            code: Int(proc.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "Bộ chuyển đổi \(textUtilFormat.uppercased()) báo lỗi: \(errStr)"]
                        )
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Paginated Vector A4 PDF via Offscreen WKWebView

    private func exportHTMLToPDF(html: String, baseURL: URL?, destinationURL: URL) async throws {
        let exporter = OffscreenWebPDFExporter()
        self.activePDFExporter = exporter
        defer { self.activePDFExporter = nil }
        try await exporter.render(html: html, baseURL: baseURL, to: destinationURL)
    }

    // MARK: - Carbon-Style @2x Retina Code Snapshot PNG

    func renderRetinaCodeCardPNG(
        code: String,
        language: CodeLanguage,
        title: String,
        palette: EditorThemePalette,
        fontFamily: String,
        fontSize: CGFloat
    ) throws -> Data {
        // Limit snapshot to first 140 lines so PNG stays crisp and fast
        let allLines = code.components(separatedBy: "\n")
        let clippedCode: String
        if allLines.count > 140 {
            clippedCode = allLines.prefix(140).joined(separator: "\n") + "\n\n// … (đã rút gọn \(allLines.count - 140) dòng tiếp theo)"
        } else {
            clippedCode = code.isEmpty ? "// CodePad" : code
        }

        let attr = SyntaxHighlighter.attributedString(
            for: clippedCode,
            language: language,
            palette: palette,
            fontFamily: fontFamily,
            fontSize: fontSize
        )

        let maxInnerCodeWidth: CGFloat = 760
        let bounding = attr.boundingRect(
            with: NSSize(width: maxInnerCodeWidth, height: 12_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        let cardPaddingX: CGFloat = 28
        let cardPaddingTop: CGFloat = 52
        let cardPaddingBottom: CGFloat = 26
        let outerMargin: CGFloat = 34

        let cardWidth = max(440, min(maxInnerCodeWidth + cardPaddingX * 2, ceil(bounding.width) + cardPaddingX * 2 + 12))
        let cardHeight = ceil(bounding.height) + cardPaddingTop + cardPaddingBottom
        let totalWidth = cardWidth + outerMargin * 2
        let totalHeight = cardHeight + outerMargin * 2

        let scale: CGFloat = 2.0
        let pxW = Int(totalWidth * scale)
        let pxH = Int(totalHeight * scale)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pxW,
            pixelsHigh: pxH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "CodePadExport", code: -20, userInfo: [NSLocalizedDescriptionKey: "Không thể khởi tạo bộ đệm ảnh PNG"])
        }
        rep.size = NSSize(width: totalWidth, height: totalHeight)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        // Outer macOS wallpaper gradient backdrop
        let fullRect = NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)
        let bgGradient = NSGradient(colors: [
            NSColor(srgbRed: 0.14, green: 0.18, blue: 0.28, alpha: 1.0),
            NSColor(srgbRed: 0.25, green: 0.16, blue: 0.34, alpha: 1.0),
            NSColor(srgbRed: 0.10, green: 0.26, blue: 0.36, alpha: 1.0)
        ])!
        bgGradient.draw(in: fullRect, angle: -38)

        // Window card with soft drop shadow
        let cardRect = NSRect(x: outerMargin, y: outerMargin, width: cardWidth, height: cardHeight)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.shadowBlurRadius = 24
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 14, yRadius: 14)
        palette.editorBackgroundNS.setFill()
        cardPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Subtle window border
        NSColor.white.withAlphaComponent(palette.isDark ? 0.12 : 0.35).setStroke()
        cardPath.lineWidth = 1.0
        cardPath.stroke()

        // macOS traffic lights at top-left of card
        let headerY = cardRect.maxY - 24
        let trafficColors: [NSColor] = [
            NSColor.fromHex("#FF5F56"),
            NSColor.fromHex("#FFBD2E"),
            NSColor.fromHex("#27C93F")
        ]
        for (i, col) in trafficColors.enumerated() {
            let dotRect = NSRect(x: cardRect.minX + 18 + CGFloat(i) * 20, y: headerY - 6, width: 12, height: 12)
            col.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }

        // Title + Language badge in card header
        let headerTitle = "\(title) — \(language.displayName)"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: palette.gutterTextNS
        ]
        let titleSize = (headerTitle as NSString).size(withAttributes: titleAttrs)
        (headerTitle as NSString).draw(
            at: NSPoint(x: cardRect.midX - titleSize.width / 2, y: headerY - titleSize.height / 2),
            withAttributes: titleAttrs
        )

        // Draw syntax-highlighted code
        let textRect = NSRect(
            x: cardRect.minX + cardPaddingX,
            y: cardRect.minY + cardPaddingBottom,
            width: cardWidth - cardPaddingX * 2,
            height: ceil(bounding.height) + 4
        )
        attr.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "CodePadExport", code: -21, userInfo: [NSLocalizedDescriptionKey: "Mã hoá dữ liệu PNG thất bại"])
        }
        return png
    }
}

// MARK: - Offscreen WKWebView Paginated A4 PDF Renderer

@MainActor
private final class OffscreenWebPDFExporter: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let hostWindow: NSWindow
    private var continuation: CheckedContinuation<Void, Error>?
    private var destinationURL: URL?

    override init() {
        let rect = NSRect(x: -10_000, y: -10_000, width: 794, height: 1123)
        let config = WKWebViewConfiguration()
        self.webView = WKWebView(frame: NSRect(origin: .zero, size: rect.size), configuration: config)
        self.hostWindow = NSWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.hostWindow.isReleasedWhenClosed = false
        self.hostWindow.contentView = self.webView
        super.init()
        self.webView.navigationDelegate = self
    }

    func render(html: String, baseURL: URL?, to url: URL) async throws {
        self.destinationURL = url
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            self.webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Brief settle delay so web fonts / inline scripts finish layout
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.runPaginatedPrintOrFallback()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    private func runPaginatedPrintOrFallback() {
        guard let outURL = destinationURL else { return }

        let pInfo = NSPrintInfo()
        pInfo.paperSize = NSSize(width: 595.28, height: 841.89) // ISO A4
        pInfo.topMargin = 34
        pInfo.bottomMargin = 34
        pInfo.leftMargin = 34
        pInfo.rightMargin = 34
        pInfo.isHorizontallyCentered = true
        pInfo.isVerticallyCentered = false
        pInfo.jobDisposition = .save
        pInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = outURL

        let op = webView.printOperation(with: pInfo)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.runModal(
            for: hostWindow,
            delegate: self,
            didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
            contextInfo: nil
        )
    }

    @objc private func printOperationDidRun(
        _ printOperation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        guard let outURL = destinationURL else { return }
        if success,
           let attrs = try? FileManager.default.attributesOfItem(atPath: outURL.path),
           let size = attrs[.size] as? Int, size > 200,
           PDFDocument(url: outURL) != nil {
            finish(with: .success(()))
            return
        }

        // Secondary fallback using WKWebView.createPDF
        let pdfConfig = WKPDFConfiguration()
        webView.createPDF(configuration: pdfConfig) { [weak self] result in
            Task { @MainActor in
                switch result {
                case let .success(data):
                    do {
                        try data.write(to: outURL, options: .atomic)
                        self?.finish(with: .success(()))
                    } catch {
                        self?.finish(with: .failure(error))
                    }
                case let .failure(err):
                    self?.finish(with: .failure(err))
                }
            }
        }
    }

    private func finish(with result: Result<Void, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        hostWindow.orderOut(nil)
        cont.resume(with: result)
    }
}
