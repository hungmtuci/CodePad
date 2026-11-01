import AppKit
import Combine
import SwiftUI
import WebKit

struct LivePreviewPaneView: View {
    @ObservedObject var store = WorkspaceStore.shared
    let isStandaloneWindow: Bool

    private var previewPalette: EditorThemePalette {
        if store.forceLightPaperPreview {
            return EditorThemeID.githubLight.palette
        }
        return store.effectivePalette
    }

    var body: some View {
        let palette = store.effectivePalette
        VStack(spacing: 0) {
            // Single-row compact Preview Header Bar (never wraps vertically!)
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("Xem trước")
                        .font(.system(size: 11.5, weight: .bold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(palette.plainTextColor.opacity(0.9))

                    if let tab = store.activeTab {
                        Text("• \(tab.language.shortBadge)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(tab.language.accentColor)
                    }
                }

                Spacer(minLength: 4)

                Button {
                    store.forceLightPaperPreview.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: store.forceLightPaperPreview ? "sun.max.fill" : "circle.lefthalf.filled")
                        Text(store.forceLightPaperPreview ? "Giấy sáng" : "Theme")
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.plainTextColor.opacity(0.85))
                .help("Chuyển đổi nền Xem trước giữa Theme hiện tại và Nền giấy trắng chuẩn in ấn")

                if let tab = store.activeTab {
                    Button {
                        ExportService.shared.promptAndExport(tab: tab, format: .pdf, preferences: store.preferences)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.richtext")
                            Text("PDF")
                                .lineLimit(1)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .help("Xuất trực tiếp ra tệp PDF chuẩn A4")

                    Button {
                        ExportService.shared.promptAndExport(tab: tab, format: .docx, preferences: store.preferences)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.text")
                            Text("DOCX")
                                .lineLimit(1)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .help("Xuất trực tiếp ra tệp Microsoft Word (.docx)")
                }

                if !isStandaloneWindow {
                    Button {
                        store.openOrFocusFloatingPreviewWindow()
                    } label: {
                        Image(systemName: "pip.exit")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.plainTextColor.opacity(0.78))
                    .help("Tách Live Preview ra cửa sổ riêng (⌘⇧O)")

                    Button {
                        store.toggleSplitPreview()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.plainTextColor.opacity(0.72))
                    .help("Ẩn khung Xem trước cạnh bên (⌘⌥P)")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(palette.chromeBackgroundColor)

            Divider()
                .overlay(Color.primary.opacity(0.14))

            if let tab = store.activeTab {
                LivePreviewWebRepresentable(
                    content: tab.content,
                    language: tab.language,
                    title: tab.displayTitle,
                    baseURL: tab.fileURL?.deletingLastPathComponent(),
                    palette: previewPalette,
                    syncScrollEnabled: store.preferences.syncPreviewScroll
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
        }
        .background(previewPalette.editorBackgroundColor)
        .clipped()
    }
}

struct FloatingPreviewWindowRootView: View {
    @ObservedObject var store = WorkspaceStore.shared

    var body: some View {
        ZStack {
            store.effectivePalette.chromeBackgroundColor
                .ignoresSafeArea()
            LivePreviewPaneView(isStandaloneWindow: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Debounced Scroll-Preserving & In-Place DOM Morphing WKWebView Wrapper

private struct LivePreviewWebRepresentable: NSViewRepresentable {
    let content: String
    let language: CodeLanguage
    let title: String
    let baseURL: URL?
    let palette: EditorThemePalette
    let syncScrollEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 480), configuration: config)
        wv.wantsLayer = true
        wv.clipsToBounds = true
        wv.navigationDelegate = context.coordinator
        context.coordinator.webView = wv
        return wv
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.configureScrollSync(enabled: syncScrollEnabled)
        context.coordinator.scheduleRenderIfNeeded(
            content: content,
            language: language,
            palette: palette,
            title: title,
            baseURL: baseURL
        )
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?

        private var lastRenderedContent: String?
        private var lastRenderedLanguage: CodeLanguage?
        private var lastRenderedPaletteID: EditorThemeID?
        private var lastRenderedTitle: String?
        private var lastRenderedBaseURL: URL?

        private var isMarkdownShellLoaded = false
        private var loadedMarkdownHasMath = false
        private var debounceItem: DispatchWorkItem?
        private var savedScrollY: Double = 0
        private var lastSyncedFraction: Double = -1
        private var scrollCancellable: AnyCancellable?
        private var isScrollSyncEnabled = false

        func configureScrollSync(enabled: Bool) {
            guard enabled != isScrollSyncEnabled else { return }
            isScrollSyncEnabled = enabled
            if enabled {
                scrollCancellable = EditorTelemetryStore.shared.$scrollFraction
                    .removeDuplicates { abs($0 - $1) < 0.006 }
                    .sink { [weak self] frac in
                        self?.syncScroll(to: frac)
                    }
            } else {
                scrollCancellable?.cancel()
                scrollCancellable = nil
            }
        }

        func scheduleRenderIfNeeded(
            content: String,
            language: CodeLanguage,
            palette: EditorThemePalette,
            title: String,
            baseURL: URL?
        ) {
            // Fast O(1) metadata + string equality check BEFORE running Markdown/HTML parser!
            if lastRenderedLanguage == language,
               lastRenderedPaletteID == palette.id,
               lastRenderedBaseURL == baseURL,
               lastRenderedTitle == title,
               lastRenderedContent == content {
                return
            }

            let isFirstRender = (lastRenderedLanguage == nil)
            debounceItem?.cancel()

            if isFirstRender {
                commitRender(
                    content: content,
                    language: language,
                    palette: palette,
                    title: title,
                    baseURL: baseURL
                )
                return
            }

            let item = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.commitRender(
                        content: content,
                        language: language,
                        palette: palette,
                        title: title,
                        baseURL: baseURL
                    )
                }
            }
            debounceItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.085, execute: item)
        }

        private func commitRender(
            content: String,
            language: CodeLanguage,
            palette: EditorThemePalette,
            title: String,
            baseURL: URL?
        ) {
            guard let wv = webView else { return }

            let sameMarkdownShell = (language == .markdown)
                && (lastRenderedLanguage == .markdown)
                && (lastRenderedPaletteID == palette.id)
                && (lastRenderedBaseURL == baseURL)
                && isMarkdownShellLoaded

            let needsMermaid = content.contains("```mermaid")
            let needsMath = content.contains("$$") || content.contains("\\(") || content.contains("\\[")

            lastRenderedContent = content
            lastRenderedLanguage = language
            lastRenderedPaletteID = palette.id
            lastRenderedTitle = title
            lastRenderedBaseURL = baseURL

            // Fast zero-flicker in-place DOM morph for live Markdown editing (preserves scroll & avoids WebKit reload)
            if sameMarkdownShell && !needsMermaid && (!needsMath || loadedMarkdownHasMath) {
                let bodyHTML = MarkdownHTMLRenderer.renderMarkdownBodyHTML(content, palette: palette)
                wv.callAsyncJavaScript(
                    "return window.__codepadSetMarkdownBody ? window.__codepadSetMarkdownBody(body) : false;",
                    arguments: ["body": bodyHTML],
                    in: nil,
                    in: .page
                ) { [weak self] result in
                    Task { @MainActor in
                        if case let .success(ok as Bool) = result, ok {
                            return
                        }
                        self?.performFullDocumentLoad(
                            content: content,
                            language: language,
                            palette: palette,
                            title: title,
                            baseURL: baseURL
                        )
                    }
                }
                return
            }

            performFullDocumentLoad(
                content: content,
                language: language,
                palette: palette,
                title: title,
                baseURL: baseURL
            )
        }

        private func performFullDocumentLoad(
            content: String,
            language: CodeLanguage,
            palette: EditorThemePalette,
            title: String,
            baseURL: URL?
        ) {
            guard let wv = webView else { return }
            isMarkdownShellLoaded = false
            loadedMarkdownHasMath = (language == .markdown)
                && (content.contains("$$") || content.contains("\\(") || content.contains("\\["))

            let html = MarkdownHTMLRenderer.buildLivePreviewHTML(
                content: content,
                language: language,
                palette: palette,
                title: title
            )

            wv.evaluateJavaScript("window.scrollY || 0") { [weak self] val, _ in
                Task { @MainActor in
                    if let num = val as? Double {
                        self?.savedScrollY = num
                    }
                    wv.loadHTMLString(html, baseURL: baseURL)
                }
            }
        }

        func syncScroll(to fraction: Double) {
            guard abs(fraction - lastSyncedFraction) > 0.006, let wv = webView else { return }
            lastSyncedFraction = fraction
            let js = """
            (function(){
                const max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
                window.scrollTo({ top: max * \(fraction), behavior: 'auto' });
            })();
            """
            wv.evaluateJavaScript(js, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if lastRenderedLanguage == .markdown {
                isMarkdownShellLoaded = true
            }
            if savedScrollY > 0 {
                webView.evaluateJavaScript("window.scrollTo(0, \(savedScrollY));", completionHandler: nil)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" || scheme == "mailto" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
