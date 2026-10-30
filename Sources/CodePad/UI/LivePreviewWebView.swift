import AppKit
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
            // Sleek Preview Header Toolbar
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("XEM TRƯỚC TRỰC TIẾP")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(palette.plainTextColor.opacity(0.88))

                    if let tab = store.activeTab {
                        Text("• \(tab.language.displayName)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.plainTextColor.opacity(0.58))
                    }
                }

                Spacer()

                Button {
                    store.forceLightPaperPreview.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: store.forceLightPaperPreview ? "sun.max.fill" : "circle.lefthalf.filled")
                        Text(store.forceLightPaperPreview ? "Nền giấy sáng" : "Theo Theme")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
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
                        Label("PDF", systemImage: "doc.richtext")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .help("Xuất trực tiếp ra tệp PDF chuẩn A4")

                    Button {
                        ExportService.shared.promptAndExport(tab: tab, format: .docx, preferences: store.preferences)
                    } label: {
                        Label("DOCX", systemImage: "doc.text")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
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
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.plainTextColor.opacity(0.75))
                    .help("Tách Live Preview ra cửa sổ riêng (⌘⇧O)")

                    Button {
                        store.toggleSplitPreview()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.plainTextColor.opacity(0.7))
                    .help("Ẩn khung Xem trước cạnh bên (⌘⌥P)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(palette.chromeBackgroundColor)

            Divider()
                .overlay(Color.primary.opacity(0.12))

            if let tab = store.activeTab {
                LivePreviewWebRepresentable(
                    content: tab.content,
                    language: tab.language,
                    title: tab.displayTitle,
                    baseURL: tab.fileURL?.deletingLastPathComponent(),
                    palette: previewPalette,
                    scrollFraction: store.preferences.syncPreviewScroll ? store.editorScrollFraction : nil
                )
            } else {
                Spacer()
            }
        }
    }
}

struct FloatingPreviewWindowRootView: View {
    @ObservedObject var store = WorkspaceStore.shared

    var body: some View {
        LivePreviewPaneView(isStandaloneWindow: true)
            .padding(.top, 28)
            .background(store.effectivePalette.chromeBackgroundColor)
            .ignoresSafeArea(.container, edges: .top)
    }
}

// MARK: - Debounced Scroll-Preserving WKWebView Wrapper

private struct LivePreviewWebRepresentable: NSViewRepresentable {
    let content: String
    let language: CodeLanguage
    let title: String
    let baseURL: URL?
    let palette: EditorThemePalette
    let scrollFraction: Double?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = wv
        return wv
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = MarkdownHTMLRenderer.buildLivePreviewHTML(
            content: content,
            language: language,
            palette: palette,
            title: title
        )
        context.coordinator.scheduleLoadIfNeeded(html: html, baseURL: baseURL)
        if let frac = scrollFraction {
            context.coordinator.syncScroll(to: frac)
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var lastLoadedHTML: String = ""
        private var pendingHTML: String?
        private var pendingBaseURL: URL?
        private var debounceItem: DispatchWorkItem?
        private var savedScrollY: Double = 0
        private var lastSyncedFraction: Double = -1

        func scheduleLoadIfNeeded(html: String, baseURL: URL?) {
            guard html != lastLoadedHTML else { return }
            pendingHTML = html
            pendingBaseURL = baseURL

            debounceItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.commitPendingHTML()
                }
            }
            debounceItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.11, execute: item)
        }

        private func commitPendingHTML() {
            guard let wv = webView, let html = pendingHTML else { return }
            lastLoadedHTML = html
            let base = pendingBaseURL

            wv.evaluateJavaScript("window.scrollY || 0") { [weak self] val, _ in
                Task { @MainActor in
                    if let num = val as? Double {
                        self?.savedScrollY = num
                    }
                    wv.loadHTMLString(html, baseURL: base)
                }
            }
        }

        func syncScroll(to fraction: Double) {
            guard abs(fraction - lastSyncedFraction) > 0.008, let wv = webView else { return }
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
