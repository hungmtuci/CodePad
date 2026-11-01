import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum EditorActionCommand: Equatable {
    case toggleComment
    case indentSelection
    case outdentSelection
    case duplicateLine
    case jumpToLine(Int)
    case findNext(query: String, caseSensitive: Bool)
    case findPrevious(query: String, caseSensitive: Bool)
    case replaceCurrent(query: String, replacement: String, caseSensitive: Bool)
    case replaceAll(query: String, replacement: String, caseSensitive: Bool)
}

@MainActor
final class EditorTelemetryStore: ObservableObject {
    static let shared = EditorTelemetryStore()

    @Published var cursorLine: Int = 1
    @Published var cursorColumn: Int = 1
    @Published var selectedCharCount: Int = 0
    @Published var scrollFraction: Double = 0.0

    private init() {}

    func updateCursor(line: Int, column: Int, selectedCount: Int) {
        if cursorLine != line { cursorLine = line }
        if cursorColumn != column { cursorColumn = column }
        if selectedCharCount != selectedCount { selectedCharCount = selectedCount }
    }

    func updateScroll(fraction: Double) {
        if abs(scrollFraction - fraction) > 0.004 {
            scrollFraction = fraction
        }
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore()

    @Published var tabs: [DocumentTab] = []
    @Published var activeTabID: UUID?
    @Published var preferences: EditorPreferences = EditorPreferences() {
        didSet {
            if preferences != oldValue {
                scheduleAutosave()
            }
        }
    }

    // Live UI & Sublime Features State
    @Published var isSplitPreviewVisible: Bool = false
    @Published var isFloatingPreviewWindowOpen: Bool = false
    @Published var isCommandPalettePresented: Bool = false
    @Published var isGotoLinePresented: Bool = false
    @Published var isFindBarVisible: Bool = false
    @Published var isReplaceModeInFindBar: Bool = false
    @Published var isPreferencesPresented: Bool = false
    @Published var isExportSheetPresented: Bool = false
    @Published var isZenMode: Bool = false
    @Published var systemIsDark: Bool = true

    // Find & Replace Queries & Transient UI State
    @Published var findQuery: String = ""
    @Published var replaceQuery: String = ""
    @Published var findCaseSensitive: Bool = false
    @Published var previewWidthRatio: CGFloat = 0.47
    @Published var forceLightPaperPreview: Bool = false
    @Published var commandPaletteQuery: String = ""
    @Published var commandPaletteSelectedIndex: Int = 0
    @Published var gotoLineInput: String = ""
    @Published var selectedExportFormat: ExportFormat = .pdf

    // Dispatched action command to active NSTextView
    @Published var pendingEditorCommand: (id: UUID, cmd: EditorActionCommand)?

    // Floating Toast Notification
    @Published var activeToast: WorkspaceToast?

    // Recent files list
    @Published var recentFilePaths: [String] = []

    private var saveWorkItem: DispatchWorkItem?
    private var detectWorkItem: DispatchWorkItem?
    private var toastWorkItem: DispatchWorkItem?
    private var floatingPreviewWindow: NSWindow?
    private let persistenceQueue = DispatchQueue(label: "com.hunglx.CodePad.persistence", qos: .utility)

    private let storageFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("CodePad", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("workspace_v1.json")
    }()

    private struct PersistedSnapshot: Codable, Sendable {
        var tabs: [DocumentTab]
        var activeTabID: UUID?
        var preferences: EditorPreferences
        var isSplitPreviewVisible: Bool
        var recentFilePaths: [String]
    }

    var activeTabIndex: Int? {
        guard let id = activeTabID else { return tabs.isEmpty ? nil : 0 }
        return tabs.firstIndex(where: { $0.id == id })
    }

    var activeTab: DocumentTab? {
        guard let idx = activeTabIndex, tabs.indices.contains(idx) else { return nil }
        return tabs[idx]
    }

    var effectivePalette: EditorThemePalette {
        if preferences.followSystemAppearance {
            return systemIsDark ? EditorThemeID.monokaiPro.palette : EditorThemeID.githubLight.palette
        }
        return preferences.themeID.palette
    }

    private init() {
        refreshSystemAppearance()
        loadPersistedWorkspace()
    }

    func refreshSystemAppearance() {
        let best = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        systemIsDark = (best != .aqua)
    }

    // MARK: - Persistence (Sublime Hot-Exit Session Restore)

    private func loadPersistedWorkspace() {
        if let data = try? Data(contentsOf: storageFileURL),
           let decoded = try? JSONDecoder().decode(PersistedSnapshot.self, from: data),
           !decoded.tabs.isEmpty {
            self.tabs = decoded.tabs
            self.activeTabID = decoded.activeTabID ?? decoded.tabs.first?.id
            self.preferences = decoded.preferences
            self.isSplitPreviewVisible = decoded.isSplitPreviewVisible
            self.recentFilePaths = decoded.recentFilePaths
            return
        }

        // First-launch starter tab showcasing auto-highlight, live preview & PDF/DOCX export
        let welcomeMD = """
        # Chào mừng đến với CodePad

        **CodePad** là trình soạn thảo & dán code tối giản lấy cảm hứng từ **Sublime Text**, thiết kế riêng cho **macOS**.

        > [!TIP]
        > Bấm **`⌘N`** để tạo tab trống mới và **`⌘V`** để dán bất kỳ đoạn code nào — CodePad sẽ **tự động nhận diện ngôn ngữ & tô màu cú pháp** ngay lập tức!

        ## Tính năng nổi bật

        - [x] **Tự động nhận diện 25+ ngôn ngữ** khi dán hoặc gõ (`Python`, `Swift`, `JS/TS`, `HTML`, `Markdown`, `SQL`, `JSON`, `Bash`, `C++`, `Rust`, `Go`...)
        - [x] **Live Preview trực tiếp** (Chia đôi cạnh bên `⌘⌥P` hoặc **Tách cửa sổ Preview riêng** `⌘⇧O`) cho `Markdown`, `HTML`, `SVG`, `Mermaid`, `CSV`, `JSON`, `LaTeX`
        - [x] **Xuất tài liệu 1 chạm (`⌘E`)**: Xuất ra **PDF chuẩn A4**, **Microsoft Word (`.docx`)**, **HTML**, **RTF**, **ODT**, và **Ảnh chụp Code sắc nét (`.png`)**
        - [x] **Sublime DNA**: Thanh **Minimap** (`⌘⌥M`), **Command Palette** (`⌘⇧P`), **Goto Line** (`⌃G`), tự lưu nháp không bao giờ mất dữ liệu

        ## Ví dụ khối Code được Highlight tự động

        ```swift
        import Foundation

        struct Greeting {
            let appName = "CodePad for macOS"

            func welcome(user: String) -> String {
                return "Xin chào \\(user)! Chào mừng tới \\(appName)."
            }
        }
        ```

        | Phím tắt | Chức năng nhanh |
        | :--- | :--- |
        | `⌘N` / `⌘⇧V` | Tạo Tab mới / Dán Clipboard thành Tab mới |
        | `⌘⇧P` | Mở **Command Palette** kiểu Sublime Text |
        | `⌘⌥P` / `⌘⇧O` | Bật/Tắt Preview cạnh bên / Mở cửa sổ Preview riêng |
        | `⌘E` | Xuất nhanh sang **PDF / DOCX / HTML / PNG** |
        | `⌘U` | Kiểm tra & Cập nhật tự động qua **GitHub Releases** |
        """

        let starter = DocumentTab(
            content: welcomeMD,
            language: .markdown,
            isLanguageAutoDetected: true,
            isDirty: false
        )
        self.tabs = [starter]
        self.activeTabID = starter.id
        self.isSplitPreviewVisible = true
    }

    func scheduleAutosave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.saveInBackground()
            }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: item)
    }

    private func makeSnapshot() -> PersistedSnapshot {
        PersistedSnapshot(
            tabs: tabs,
            activeTabID: activeTabID,
            preferences: preferences,
            isSplitPreviewVisible: isSplitPreviewVisible,
            recentFilePaths: Array(recentFilePaths.prefix(15))
        )
    }

    private func saveInBackground() {
        let snapshot = makeSnapshot()
        let targetURL = storageFileURL
        persistenceQueue.async {
            if let encoded = try? JSONEncoder().encode(snapshot) {
                try? encoded.write(to: targetURL, options: .atomic)
            }
        }
    }

    func saveImmediately() {
        saveWorkItem?.cancel()
        let snapshot = makeSnapshot()
        let targetURL = storageFileURL
        persistenceQueue.sync {
            if let encoded = try? JSONEncoder().encode(snapshot) {
                try? encoded.write(to: targetURL, options: .atomic)
            }
        }
    }

    // MARK: - Tab Lifecycle & Content Updates

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        if let tab = activeTab,
           preferences.autoOpenPreviewForMarkup,
           tab.language.autoOpenPreviewOnDetect,
           !isFloatingPreviewWindowOpen {
            isSplitPreviewVisible = true
        }
        scheduleAutosave()
    }

    func selectTabByIndex(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectTab(tabs[index].id)
    }

    func createNewTab(
        initialContent: String = "",
        language: CodeLanguage = .plainText,
        autoDetect: Bool = true
    ) {
        var resolvedLang = language
        if autoDetect && !initialContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedLang = LanguageDetector.detect(from: initialContent)
        }
        let tab = DocumentTab(
            content: initialContent,
            language: resolvedLang,
            isLanguageAutoDetected: autoDetect,
            isDirty: !initialContent.isEmpty
        )
        tabs.append(tab)
        activeTabID = tab.id

        if preferences.autoOpenPreviewForMarkup && resolvedLang.autoOpenPreviewOnDetect && !isFloatingPreviewWindowOpen {
            isSplitPreviewVisible = true
        } else if initialContent.isEmpty && !isFloatingPreviewWindowOpen {
            // Keep clean minimalist single-pane editor on blank scratchpad until markup is pasted/typed
            isSplitPreviewVisible = false
        }
        scheduleAutosave()
    }

    func pasteClipboardIntoNewTab() {
        let pasted = NSPasteboard.general.string(forType: .string) ?? ""
        guard !pasted.isEmpty else {
            showToast("Clipboard hiện đang trống — đã tạo Tab trống mới")
            createNewTab()
            return
        }
        let detected = LanguageDetector.detect(from: pasted)
        createNewTab(initialContent: pasted, language: detected, autoDetect: true)
        showToast("Đã dán & tự nhận diện ngôn ngữ: \(detected.displayName)")
    }

    func closeTab(_ id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let removingActive = (activeTabID == id)
        tabs.remove(at: idx)

        if tabs.isEmpty {
            createNewTab()
            return
        }

        if removingActive {
            let nextIdx = min(idx, tabs.count - 1)
            activeTabID = tabs[nextIdx].id
        }
        scheduleAutosave()
    }

    func closeActiveTab() {
        if let id = activeTabID {
            closeTab(id)
        }
    }

    func updateActiveTabContent(_ newText: String, immediateDetect: Bool = false) {
        guard let idx = activeTabIndex else { return }
        guard tabs[idx].content != newText else { return }

        tabs[idx].content = newText
        tabs[idx].isDirty = true
        tabs[idx].updatedAt = Date()

        let tabID = tabs[idx].id
        if tabs[idx].isLanguageAutoDetected {
            if immediateDetect {
                detectWorkItem?.cancel()
                runLanguageAutoDetect(for: tabID)
            } else {
                detectWorkItem?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    Task { @MainActor in
                        self?.runLanguageAutoDetect(for: tabID)
                    }
                }
                detectWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
            }
        }

        scheduleAutosave()
    }

    func runLanguageAutoDetect(for tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[idx].isLanguageAutoDetected else { return }

        let text = tabs[idx].content
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if tabs[idx].language != .plainText {
                tabs[idx].language = .plainText
            }
            return
        }

        let detected = LanguageDetector.detect(from: text)
        let previous = tabs[idx].language
        if detected != previous {
            tabs[idx].language = detected
            if preferences.autoOpenPreviewForMarkup
                && detected.autoOpenPreviewOnDetect
                && !isSplitPreviewVisible
                && !isFloatingPreviewWindowOpen {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSplitPreviewVisible = true
                }
            }
        }
    }

    func setLanguageForActiveTab(_ language: CodeLanguage, autoDetect: Bool = false) {
        guard let idx = activeTabIndex else { return }
        tabs[idx].isLanguageAutoDetected = autoDetect
        if autoDetect {
            runLanguageAutoDetect(for: tabs[idx].id)
            showToast("Đã bật Tự động nhận diện ngôn ngữ (\(tabs[idx].language.displayName))")
        } else {
            tabs[idx].language = language
            if preferences.autoOpenPreviewForMarkup && language.autoOpenPreviewOnDetect && !isFloatingPreviewWindowOpen {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSplitPreviewVisible = true
                }
            }
            showToast("Đã chọn ngôn ngữ: \(language.displayName)")
        }
        scheduleAutosave()
    }

    // MARK: - Open & Save Files on Disk

    func openFileDialog() {
        let panel = NSOpenPanel()
        panel.title = "Mở tệp mã nguồn hoặc tài liệu"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            openFileURL(url)
        }
    }

    func openFileURL(_ url: URL) {
        if let existingIdx = tabs.firstIndex(where: { $0.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
            activeTabID = tabs[existingIdx].id
            return
        }

        let content: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            content = utf8
        } else if let latin = try? String(contentsOf: url, encoding: .isoLatin1) {
            content = latin
        } else {
            showToast("Không thể đọc tệp \(url.lastPathComponent)", isError: true)
            return
        }

        let extLang = CodeLanguage.fromFileURL(url)
        let resolvedLang = extLang ?? LanguageDetector.detect(from: content)
        let newTab = DocumentTab(
            customTitle: url.lastPathComponent,
            content: content,
            language: resolvedLang,
            isLanguageAutoDetected: (extLang == nil),
            fileURL: url,
            isDirty: false
        )

        // Reuse single empty untouched scratchpad tab if present
        if tabs.count == 1, tabs[0].content.isEmpty, tabs[0].fileURL == nil {
            tabs = [newTab]
        } else {
            tabs.append(newTab)
        }
        activeTabID = newTab.id
        recordRecentFile(url)

        if preferences.autoOpenPreviewForMarkup && resolvedLang.autoOpenPreviewOnDetect && !isFloatingPreviewWindowOpen {
            isSplitPreviewVisible = true
        }
        scheduleAutosave()
    }

    func saveActiveTab() {
        guard let idx = activeTabIndex else { return }
        if let existingURL = tabs[idx].fileURL {
            do {
                try tabs[idx].content.write(to: existingURL, atomically: true, encoding: .utf8)
                tabs[idx].isDirty = false
                tabs[idx].updatedAt = Date()
                recordRecentFile(existingURL)
                saveImmediately()
                showToast("Đã lưu \(existingURL.lastPathComponent)", revealURL: existingURL)
            } catch {
                showToast("Lưu tệp thất bại: \(error.localizedDescription)", isError: true)
            }
        } else {
            saveActiveTabAs()
        }
    }

    func saveActiveTabAs() {
        guard let idx = activeTabIndex else { return }
        let tab = tabs[idx]
        let ext = tab.language.defaultExtension
        let panel = NSSavePanel()
        panel.title = "Lưu tệp mã nguồn"
        panel.nameFieldStringValue = "\(tab.suggestedBaseFilename).\(ext)"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let dest = panel.url else { return }

        do {
            try tab.content.write(to: dest, atomically: true, encoding: .utf8)
            tabs[idx].fileURL = dest
            tabs[idx].customTitle = dest.lastPathComponent
            tabs[idx].isDirty = false
            if let fileLang = CodeLanguage.fromFileURL(dest) {
                tabs[idx].language = fileLang
                tabs[idx].isLanguageAutoDetected = false
            }
            recordRecentFile(dest)
            saveImmediately()
            showToast("Đã lưu thành công: \(dest.lastPathComponent)", revealURL: dest)
        } catch {
            showToast("Lưu tệp thất bại: \(error.localizedDescription)", isError: true)
        }
    }

    private func recordRecentFile(_ url: URL) {
        let p = url.standardizedFileURL.path
        recentFilePaths.removeAll { $0 == p }
        recentFilePaths.insert(p, at: 0)
        if recentFilePaths.count > 15 {
            recentFilePaths = Array(recentFilePaths.prefix(15))
        }
    }

    // MARK: - Code Formatting / Beautify

    func formatActiveDocument() {
        guard let idx = activeTabIndex else { return }
        let raw = tabs[idx].content
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if tabs[idx].language == .json, let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
           let prettyStr = String(data: prettyData, encoding: .utf8) {
            tabs[idx].content = prettyStr
            tabs[idx].isDirty = true
            scheduleAutosave()
            showToast("Đã chuẩn hoá & làm đẹp JSON (Pretty-Print)")
            return
        }

        // Clean trailing spaces and normalize tabs/newlines for any language
        let indentUnit = String(repeating: " ", count: preferences.tabWidth)
        let cleaned = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { line -> String in
                var l = line
                if preferences.useSpacesForTabs {
                    l = l.replacingOccurrences(of: "\t", with: indentUnit)
                }
                while l.last == " " || l.last == "\t" {
                    l.removeLast()
                }
                return l
            }
            .joined(separator: "\n")

        tabs[idx].content = cleaned
        tabs[idx].isDirty = true
        scheduleAutosave()
        showToast("Đã chuẩn hoá khoảng trắng & lề dòng")
    }

    func sendEditorCommand(_ cmd: EditorActionCommand) {
        pendingEditorCommand = (UUID(), cmd)
    }

    // MARK: - Live Preview Split & Dedicated Floating Window

    func toggleSplitPreview() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isSplitPreviewVisible.toggle()
        }
        scheduleAutosave()
    }

    func openOrFocusFloatingPreviewWindow() {
        if let existing = floatingPreviewWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            isFloatingPreviewWindowOpen = true
            return
        }

        let host = NSHostingController(rootView: FloatingPreviewWindowRootView())
        host.sizingOptions = []
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "CodePad — Xem trước trực tiếp (Live Preview)"
        win.titlebarAppearsTransparent = true
        win.minSize = NSSize(width: 460, height: 340)
        win.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        win.contentViewController = host
        win.setContentSize(NSSize(width: 840, height: 740))
        win.setFrameAutosaveName("CodePadFloatingPreviewWin_v2")
        win.center()
        win.isReleasedWhenClosed = false

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isFloatingPreviewWindowOpen = false
            }
        }

        self.floatingPreviewWindow = win
        self.isFloatingPreviewWindowOpen = true
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Toast Notifications & Finder Reveal

    func showToast(_ message: String, revealURL: URL? = nil, isError: Bool = false) {
        toastWorkItem?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            activeToast = WorkspaceToast(message: message, revealFileURL: revealURL, isError: isError)
        }
        let duration: Double = revealURL != nil ? 6.0 : 3.4
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.22)) {
                    self?.activeToast = nil
                }
            }
        }
        toastWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    func dismissToast() {
        toastWorkItem?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            activeToast = nil
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
