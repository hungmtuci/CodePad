import AppKit
import SwiftUI

@main
enum CodePadMain {
    static func main() {
        // Built-in headless self-test hook for automated verification (`--verify-export <dir>`)
        let args = CommandLine.arguments
        if let flagIdx = args.firstIndex(of: "--verify-export"), flagIdx + 1 < args.count {
            let outDir = URL(fileURLWithPath: args[flagIdx + 1], isDirectory: true)
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            MainActor.assumeIsolated {
                SelfVerificationRunner.run(outputDir: outDir)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(15))
            return
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = CodePadAppDelegate.shared
        app.delegate = delegate
        MainActor.assumeIsolated {
            delegate.installMainMenu()
        }
        app.run()
    }
}

@MainActor
final class CodePadAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let shared = CodePadAppDelegate()

    private var mainWindow: NSWindow?
    private var keyMonitor: Any?
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier {
            let ownPID = ProcessInfo.processInfo.processIdentifier
            if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { $0.processIdentifier != ownPID }) {
                existing.activate()
                NSApp.terminate(nil)
                return
            }
        }

        WorkspaceStore.shared.refreshSystemAppearance()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            Task { @MainActor in
                WorkspaceStore.shared.refreshSystemAppearance()
            }
        }

        installKeyboardMonitor()
        openOrFocusMainWindow()
        UpdateCheckerService.shared.checkSilentlyOnLaunchIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openOrFocusMainWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        WorkspaceStore.shared.saveImmediately()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openOrFocusMainWindow()
        for url in urls {
            WorkspaceStore.shared.openFileURL(url)
        }
    }

    func openOrFocusMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: MainEditorWorkspaceView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1220, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "CodePad"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 720, height: 480)
        window.contentViewController = hosting
        window.center()
        window.setFrameAutosaveName("CodePadMainWindow_v1")
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Local Keyboard Shortcut Monitor

    private func installKeyboardMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else {
                return event
            }
            let store = WorkspaceStore.shared

            // Ctrl + G -> Sublime Goto Line
            if flags == [.control] && chars == "g" {
                store.isGotoLinePresented.toggle()
                return nil
            }

            // Ctrl + Cmd + Z -> Zen Mode
            if flags == [.control, .command] && chars == "z" {
                withAnimation(.easeInOut(duration: 0.18)) {
                    store.isZenMode.toggle()
                }
                return nil
            }

            guard flags.contains(.command) && !flags.contains(.control) else {
                return event
            }

            // Cmd + Shift + P -> Sublime Command Palette
            if chars == "p" && flags == [.command, .shift] {
                store.isCommandPalettePresented.toggle()
                return nil
            }

            // Cmd + Option + P -> Toggle Split Preview
            if chars == "p" && flags == [.command, .option] {
                store.toggleSplitPreview()
                return nil
            }

            // Cmd + Shift + O -> Popout Floating Preview Window
            if chars == "o" && flags == [.command, .shift] {
                store.openOrFocusFloatingPreviewWindow()
                return nil
            }

            // Cmd + Option + M -> Toggle Sublime Minimap
            if chars == "m" && flags == [.command, .option] {
                store.preferences.showMinimap.toggle()
                return nil
            }

            // Cmd + \ -> Toggle Left Sidebar
            if chars == "\\" && flags == [.command] {
                withAnimation(.easeInOut(duration: 0.16)) {
                    store.preferences.showSidebar.toggle()
                }
                return nil
            }

            // Cmd + / -> Toggle Line/Block Comment
            if chars == "/" && flags == [.command] {
                store.sendEditorCommand(.toggleComment)
                return nil
            }

            // Cmd + Shift + D -> Duplicate Line
            if chars == "d" && flags == [.command, .shift] {
                store.sendEditorCommand(.duplicateLine)
                return nil
            }

            // Cmd + Shift + I -> Format / Beautify JSON & Code
            if chars == "i" && flags == [.command, .shift] {
                store.formatActiveDocument()
                return nil
            }

            // Cmd + L -> Goto Line
            if chars == "l" && flags == [.command] {
                store.isGotoLinePresented.toggle()
                return nil
            }

            // Cmd + F / Cmd + Option + F -> Find & Replace
            if chars == "f" && flags == [.command] {
                store.isFindBarVisible = true
                store.isReplaceModeInFindBar = false
                return nil
            }
            if chars == "f" && flags == [.command, .option] {
                store.isFindBarVisible = true
                store.isReplaceModeInFindBar = true
                return nil
            }

            // Cmd + E -> Open Export Center (PDF/DOCX/HTML/PNG...)
            if chars == "e" && flags == [.command] {
                store.isExportSheetPresented = true
                return nil
            }

            // Cmd + Shift + V -> Paste Clipboard into New Auto-Highlighted Tab
            if chars == "v" && flags == [.command, .shift] {
                store.pasteClipboardIntoNewTab()
                return nil
            }

            // Cmd + 1 ... Cmd + 9 -> Switch Tabs
            if flags == [.command], let num = Int(chars), (1...9).contains(num) {
                store.selectTabByIndex(num - 1)
                return nil
            }

            // Cmd + (+ / = / - / 0) -> Editor Font Zoom
            if (chars == "=" || chars == "+") && (flags == [.command] || flags == [.command, .shift]) {
                store.preferences.fontSize = min(28, store.preferences.fontSize + 1)
                return nil
            }
            if chars == "-" && flags == [.command] {
                store.preferences.fontSize = max(10, store.preferences.fontSize - 1)
                return nil
            }
            if chars == "0" && flags == [.command] {
                store.preferences.fontSize = 13.5
                return nil
            }

            return event
        }
    }

    // MARK: - Native macOS Menu Bar

    func installMainMenu() {
        let mainMenu = NSMenu()

        // 1. App Menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Giới thiệu về CodePad", action: #selector(showAboutAction), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        let updateItem = appMenu.addItem(withTitle: "Kiểm tra cập nhật từ GitHub…", action: #selector(checkUpdatesAction), keyEquivalent: "u")
        updateItem.target = self
        let prefsItem = appMenu.addItem(withTitle: "Cài đặt…", action: #selector(openPreferencesAction), keyEquivalent: ",")
        prefsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ẩn CodePad", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Ẩn các ứng dụng khác", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Thoát CodePad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // 2. File Menu
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "Tệp")
        fileMenu.addItem(makeItem("Tab mới", #selector(newTabAction), "n"))
        fileMenu.addItem(makeItem("Tab mới (Phím tắt phụ)", #selector(newTabAction), "t"))
        fileMenu.addItem(makeItem("Dán Clipboard thành Tab mới", #selector(pasteNewTabAction), "v", [.command, .shift]))
        fileMenu.addItem(.separator())
        fileMenu.addItem(makeItem("Mở tệp…", #selector(openFileAction), "o"))
        fileMenu.addItem(makeItem("Lưu tệp", #selector(saveFileAction), "s"))
        fileMenu.addItem(makeItem("Lưu thành…", #selector(saveFileAsAction), "s", [.command, .shift]))
        fileMenu.addItem(.separator())
        fileMenu.addItem(makeItem("Xuất ra PDF / DOCX / HTML / PNG…", #selector(openExportSheetAction), "e"))
        fileMenu.addItem(makeItem("Xuất nhanh ra PDF (.pdf)…", #selector(quickExportPDFAction), "p", [.command]))
        fileMenu.addItem(makeItem("Xuất nhanh ra Word (.docx)…", #selector(quickExportDOCXAction), "d", [.command, .option]))
        fileMenu.addItem(.separator())
        fileMenu.addItem(makeItem("Đóng Tab hiện tại", #selector(closeTabAction), "w"))
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        // 3. Edit Menu (Standard Responder Chain for Undo/Redo/Cut/Copy/Paste/SelectAll!)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Chỉnh sửa")
        editMenu.addItem(withTitle: "Hoàn tác", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Làm lại", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cắt", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Sao chép", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(makeItem("Sao chép Rich Text giữ màu Code", #selector(copyRichTextAction), "c", [.command, .option]))
        editMenu.addItem(withTitle: "Dán (Tự nhận diện Code)", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Chọn tất cả", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(makeItem("Bật / Tắt Ghi chú dòng (Comment)", #selector(toggleCommentAction), "/"))
        editMenu.addItem(makeItem("Làm đẹp Code / Pretty-Print JSON", #selector(formatCodeAction), "i", [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(makeItem("Tìm kiếm…", #selector(findAction), "f"))
        editMenu.addItem(makeItem("Tìm & Thay thế…", #selector(findReplaceAction), "f", [.command, .option]))
        editMenu.addItem(makeItem("Đi tới dòng…", #selector(gotoLineAction), "l"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        // 4. View Menu
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "Hiển thị")
        viewMenu.addItem(makeItem("Command Palette (Sublime)…", #selector(commandPaletteAction), "p", [.command, .shift]))
        viewMenu.addItem(.separator())
        viewMenu.addItem(makeItem("Bật / Tắt Khung Xem trước trực tiếp", #selector(togglePreviewAction), "p", [.command, .option]))
        viewMenu.addItem(makeItem("Mở Cửa sổ Xem trước riêng biệt", #selector(floatingPreviewAction), "o", [.command, .shift]))
        viewMenu.addItem(.separator())
        viewMenu.addItem(makeItem("Bật / Tắt Thanh Minimap", #selector(toggleMinimapAction), "m", [.command, .option]))
        viewMenu.addItem(makeItem("Ẩn / Hiện Thanh bên trái", #selector(toggleSidebarAction), "\\"))
        viewMenu.addItem(makeItem("Chế độ tập trung Zen Mode", #selector(toggleZenAction), "z", [.control, .command]))
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        // 5. Window & Help Menu
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Cửa sổ")
        windowMenu.addItem(withTitle: "Thu nhỏ", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Thu phóng", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        let helpItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Trợ giúp")
        let repoItem = helpMenu.addItem(withTitle: "Trang chủ GitHub (hungmtuci/CodePad)", action: #selector(openGitHubAction), keyEquivalent: "")
        repoItem.target = self
        helpItem.submenu = helpMenu
        mainMenu.addItem(helpItem)

        NSApp.mainMenu = mainMenu
    }

    private func makeItem(
        _ title: String,
        _ action: Selector,
        _ key: String,
        _ mask: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mask
        item.target = self
        return item
    }

    // MARK: - Menu Actions

    @objc private func showAboutAction() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "CodePad",
            .applicationVersion: UpdateCheckerService.shared.currentVersion,
            .credits: NSAttributedString(string: "Trình soạn thảo & dán Code tối giản lấy cảm hứng từ Sublime Text cho macOS — Hỗ trợ tự động Highlight 25+ ngôn ngữ, Live Preview Markdown/HTML/SVG và xuất PDF/DOCX.")
        ])
    }

    @objc private func checkUpdatesAction() { UpdateCheckerService.shared.checkForUpdatesManually() }
    @objc private func openPreferencesAction() { WorkspaceStore.shared.isPreferencesPresented = true }
    @objc private func newTabAction() { WorkspaceStore.shared.createNewTab() }
    @objc private func pasteNewTabAction() { WorkspaceStore.shared.pasteClipboardIntoNewTab() }
    @objc private func openFileAction() { WorkspaceStore.shared.openFileDialog() }
    @objc private func saveFileAction() { WorkspaceStore.shared.saveActiveTab() }
    @objc private func saveFileAsAction() { WorkspaceStore.shared.saveActiveTabAs() }
    @objc private func closeTabAction() { WorkspaceStore.shared.closeActiveTab() }
    @objc private func openExportSheetAction() { WorkspaceStore.shared.isExportSheetPresented = true }

    @objc private func quickExportPDFAction() {
        if let tab = WorkspaceStore.shared.activeTab {
            ExportService.shared.promptAndExport(tab: tab, format: .pdf, preferences: WorkspaceStore.shared.preferences)
        }
    }

    @objc private func quickExportDOCXAction() {
        if let tab = WorkspaceStore.shared.activeTab {
            ExportService.shared.promptAndExport(tab: tab, format: .docx, preferences: WorkspaceStore.shared.preferences)
        }
    }

    @objc private func copyRichTextAction() {
        if let tab = WorkspaceStore.shared.activeTab {
            ExportService.shared.copyHighlightedRichTextToClipboard(tab: tab, preferences: WorkspaceStore.shared.preferences)
        }
    }

    @objc private func toggleCommentAction() { WorkspaceStore.shared.sendEditorCommand(.toggleComment) }
    @objc private func formatCodeAction() { WorkspaceStore.shared.formatActiveDocument() }
    @objc private func findAction() {
        WorkspaceStore.shared.isFindBarVisible = true
        WorkspaceStore.shared.isReplaceModeInFindBar = false
    }
    @objc private func findReplaceAction() {
        WorkspaceStore.shared.isFindBarVisible = true
        WorkspaceStore.shared.isReplaceModeInFindBar = true
    }
    @objc private func gotoLineAction() { WorkspaceStore.shared.isGotoLinePresented = true }
    @objc private func commandPaletteAction() { WorkspaceStore.shared.isCommandPalettePresented.toggle() }
    @objc private func togglePreviewAction() { WorkspaceStore.shared.toggleSplitPreview() }
    @objc private func floatingPreviewAction() { WorkspaceStore.shared.openOrFocusFloatingPreviewWindow() }
    @objc private func toggleMinimapAction() { WorkspaceStore.shared.preferences.showMinimap.toggle() }
    @objc private func toggleSidebarAction() { WorkspaceStore.shared.preferences.showSidebar.toggle() }
    @objc private func toggleZenAction() { WorkspaceStore.shared.isZenMode.toggle() }
    @objc private func openGitHubAction() { UpdateCheckerService.shared.openGitHubRepoPage() }
}

// MARK: - Automated Headless Verification Suite (`CodePad --verify-export /tmp/...`)

@MainActor
private enum SelfVerificationRunner {
    static func run(outputDir: URL) {
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

                // 1. Verify LanguageDetector across languages
                assert(LanguageDetector.detect(from: "import SwiftUI\n@MainActor struct Demo: View {}") == .swift)
                assert(LanguageDetector.detect(from: "def fib(n):\n    if n <= 1:\n        return n\n    return fib(n-1)") == .python)
                assert(LanguageDetector.detect(from: "<!DOCTYPE html><html><body><h1>Hi</h1></body></html>") == .html)
                assert(LanguageDetector.detect(from: "# Tiêu đề\n\n- [x] Mục 1\n\n```js\nconsole.log(1)\n```") == .markdown)
                assert(LanguageDetector.detect(from: "{\"name\": \"CodePad\", \"ok\": true}") == .json)
                assert(LanguageDetector.detect(from: "SELECT id, email FROM users WHERE active = 1 ORDER BY id DESC;") == .sql)

                // 2. Verify PDF, DOCX, RTF, HTML & PNG exports on both Markdown & Code
                let mdTab = DocumentTab(
                    customTitle: "TaiLieuThuNghiem.md",
                    content: "# Kiểm thử CodePad Tiếng Việt\n\nĐoạn văn **in đậm** và bảng dữ liệu:\n\n| Ngôn ngữ | Tự động Highlight |\n| :--- | :---: |\n| Swift | Có |\n| Python | Có |\n\n```python\ndef chao(ten: str):\n    print(f\"Xin chào {ten}\")\n```",
                    language: .markdown,
                    isLanguageAutoDetected: true
                )
                let prefs = EditorPreferences()

                let pdfURL = outputDir.appendingPathComponent("test_markdown.pdf")
                let docxURL = outputDir.appendingPathComponent("test_markdown.docx")
                let htmlURL = outputDir.appendingPathComponent("test_markdown.html")
                let pngURL = outputDir.appendingPathComponent("test_code.png")

                try await ExportService.shared.exportDocument(tab: mdTab, format: .pdf, to: pdfURL, preferences: prefs)
                try await ExportService.shared.exportDocument(tab: mdTab, format: .docx, to: docxURL, preferences: prefs)
                try await ExportService.shared.exportDocument(tab: mdTab, format: .html, to: htmlURL, preferences: prefs)

                let codeTab = DocumentTab(
                    customTitle: "Hello.swift",
                    content: "import Foundation\n\nfunc xinChao() {\n    print(\"CodePad macOS\")\n}\n",
                    language: .swift,
                    isLanguageAutoDetected: false
                )
                try await ExportService.shared.exportDocument(tab: codeTab, format: .pngCard, to: pngURL, preferences: prefs)

                print("VERIFY_OK: All language detections & PDF/DOCX/HTML/PNG exports succeeded!")
                exit(0)
            } catch {
                fputs("VERIFY_FAILED: \(error)\n", stderr)
                exit(1)
            }
        }
    }
}
