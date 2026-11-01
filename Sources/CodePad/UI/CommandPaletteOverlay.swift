import AppKit
import SwiftUI

struct CommandPaletteItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let shortcutHint: String?
    let searchHaystack: String
    let action: @MainActor () -> Void

    init(
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        shortcutHint: String?,
        action: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.shortcutHint = shortcutHint
        self.searchHaystack = "\(title.lowercased()) \(subtitle.lowercased())"
        self.action = action
    }
}

struct CommandPaletteOverlayView: View {
    @ObservedObject var store = WorkspaceStore.shared
    @FocusState private var isSearchFocused: Bool

    @MainActor
    private static let catalog: [CommandPaletteItem] = {
        var list: [CommandPaletteItem] = [
            CommandPaletteItem(
                id: "paste-new-tab",
                title: "Dán Clipboard thành Tab mới & Tự động Highlight",
                subtitle: "Tự nhận diện ngôn ngữ và mở Preview nếu là Markdown/HTML",
                icon: "doc.on.clipboard.fill",
                shortcutHint: "⌘⇧V"
            ) {
                WorkspaceStore.shared.pasteClipboardIntoNewTab()
            },
            CommandPaletteItem(
                id: "new-tab",
                title: "Tạo Tab soạn thảo mới",
                subtitle: "Tab nháp tự động lưu kiểu Sublime Text",
                icon: "plus.square.on.square",
                shortcutHint: "⌘N"
            ) {
                WorkspaceStore.shared.createNewTab()
            },
            CommandPaletteItem(
                id: "toggle-preview",
                title: "Bật / Tắt Khung Xem trước trực tiếp (Split Preview)",
                subtitle: "Xem kết quả Markdown, HTML, SVG, JSON, CSV ngay cạnh code",
                icon: "rectangle.split.2x1",
                shortcutHint: "⌘⌥P"
            ) {
                WorkspaceStore.shared.toggleSplitPreview()
            },
            CommandPaletteItem(
                id: "floating-preview",
                title: "Mở Cửa sổ Xem trước riêng (Floating Preview Window)",
                subtitle: "Tách cửa sổ kết quả sang màn hình phụ, đồng bộ theo thời gian thực",
                icon: "macwindow.on.rectangle",
                shortcutHint: "⌘⇧O"
            ) {
                WorkspaceStore.shared.openOrFocusFloatingPreviewWindow()
            },
            CommandPaletteItem(
                id: "export-pdf",
                title: "Xuất tài liệu ra PDF chuẩn A4 (.pdf)",
                subtitle: "Vector sắc nét, giữ nguyên bảng biểu & màu cú pháp",
                icon: "doc.richtext.fill",
                shortcutHint: "⌘E"
            ) {
                let ws = WorkspaceStore.shared
                if let tab = ws.activeTab {
                    ExportService.shared.promptAndExport(tab: tab, format: .pdf, preferences: ws.preferences)
                }
            },
            CommandPaletteItem(
                id: "export-docx",
                title: "Xuất tài liệu ra Microsoft Word (.docx)",
                subtitle: "Mở trực tiếp bằng Word, Apple Pages hoặc Google Docs",
                icon: "doc.text.fill",
                shortcutHint: nil
            ) {
                let ws = WorkspaceStore.shared
                if let tab = ws.activeTab {
                    ExportService.shared.promptAndExport(tab: tab, format: .docx, preferences: ws.preferences)
                }
            },
            CommandPaletteItem(
                id: "export-html",
                title: "Xuất ra Trang Web độc lập (.html)",
                subtitle: "Tệp HTML tự chứa đầy đủ CSS & màu Highlight",
                icon: "safari.fill",
                shortcutHint: nil
            ) {
                let ws = WorkspaceStore.shared
                if let tab = ws.activeTab {
                    ExportService.shared.promptAndExport(tab: tab, format: .html, preferences: ws.preferences)
                }
            },
            CommandPaletteItem(
                id: "export-png",
                title: "Xuất Ảnh chụp Code sắc nét (.png @2x)",
                subtitle: "Khung cửa sổ macOS sang trọng để chia sẻ nhanh",
                icon: "photo.artframe",
                shortcutHint: nil
            ) {
                let ws = WorkspaceStore.shared
                if let tab = ws.activeTab {
                    ExportService.shared.promptAndExport(tab: tab, format: .pngCard, preferences: ws.preferences)
                }
            },
            CommandPaletteItem(
                id: "copy-rtf",
                title: "Sao chép Rich Text giữ nguyên màu Highlight",
                subtitle: "Dán trực tiếp vào Word, Mail, Pages không mất màu code",
                icon: "paintbrush.pointed.fill",
                shortcutHint: "⌘⌥C"
            ) {
                let ws = WorkspaceStore.shared
                if let tab = ws.activeTab {
                    ExportService.shared.copyHighlightedRichTextToClipboard(tab: tab, preferences: ws.preferences)
                }
            },
            CommandPaletteItem(
                id: "format-code",
                title: "Làm đẹp Code / Pretty-Print JSON & Chuẩn hoá lề",
                subtitle: "Định dạng JSON tự động và xoá khoảng trắng thừa cuối dòng",
                icon: "wand.and.stars",
                shortcutHint: "⌘⇧I"
            ) {
                WorkspaceStore.shared.formatActiveDocument()
            },
            CommandPaletteItem(
                id: "toggle-minimap",
                title: "Bật / Tắt Thanh Minimap kiểu Sublime Text",
                subtitle: "Bản đồ thu nhỏ mã nguồn bên cạnh phải",
                icon: "sidebar.trailing",
                shortcutHint: "⌘⌥M"
            ) {
                WorkspaceStore.shared.preferences.showMinimap.toggle()
            },
            CommandPaletteItem(
                id: "toggle-zen",
                title: "Bật / Tắt Chế độ tập trung tối đa (Zen Mode)",
                subtitle: "Ẩn toàn bộ thanh công cụ phụ để tập trung viết code",
                icon: "sparkles.rectangle.stack",
                shortcutHint: "⌃⌘Z"
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    WorkspaceStore.shared.isZenMode.toggle()
                }
            },
            CommandPaletteItem(
                id: "github-update",
                title: "Kiểm tra & Cập nhật ứng dụng từ GitHub Releases",
                subtitle: "hungmtuci/CodePad",
                icon: "arrow.triangle.2.circlepath.circle.fill",
                shortcutHint: "⌘U"
            ) {
                UpdateCheckerService.shared.checkForUpdatesManually()
            },
            CommandPaletteItem(
                id: "syntax-auto",
                title: "Set Syntax: Tự động nhận diện ngôn ngữ (Auto-Detect)",
                subtitle: "Tự phân tích cú pháp mỗi khi dán hoặc gõ",
                icon: "wand.and.rays",
                shortcutHint: nil
            ) {
                WorkspaceStore.shared.setLanguageForActiveTab(.plainText, autoDetect: true)
            }
        ]

        for theme in EditorThemeID.allCases {
            list.append(CommandPaletteItem(
                id: "theme-\(theme.rawValue)",
                title: "Theme: \(theme.displayName)",
                subtitle: "Đổi bảng màu trình soạn thảo",
                icon: theme.isDark ? "moon.stars.fill" : "sun.max.fill",
                shortcutHint: nil
            ) {
                WorkspaceStore.shared.preferences.followSystemAppearance = false
                WorkspaceStore.shared.preferences.themeID = theme
            })
        }

        for lang in CodeLanguage.allCases {
            list.append(CommandPaletteItem(
                id: "syntax-\(lang.rawValue)",
                title: "Set Syntax: \(lang.displayName)",
                subtitle: "Chuyển chế độ tô màu cú pháp sang .\(lang.defaultExtension)",
                icon: lang.sfSymbol,
                shortcutHint: nil
            ) {
                WorkspaceStore.shared.setLanguageForActiveTab(lang, autoDetect: false)
            })
        }

        return list
    }()

    private var filteredItems: [CommandPaletteItem] {
        let q = store.commandPaletteQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return Array(Self.catalog.prefix(18)) }
        let terms = q.split(separator: " ")
        return Self.catalog.filter { item in
            terms.allSatisfy { item.searchHaystack.contains($0) }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture {
                    store.isCommandPalettePresented = false
                }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "command")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField("Gõ lệnh, ngôn ngữ (vd: Set Syntax Python), Theme, hoặc Xuất PDF...", text: $store.commandPaletteQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14.5))
                        .focused($isSearchFocused)
                        .onChange(of: store.commandPaletteQuery) { _, _ in
                            store.commandPaletteSelectedIndex = 0
                        }
                        .onSubmit {
                            triggerSelected()
                        }

                    Button {
                        store.isCommandPalettePresented = false
                    } label: {
                        Text("ESC")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { idx, item in
                                let isSel = (idx == store.commandPaletteSelectedIndex)
                                Button {
                                    store.commandPaletteSelectedIndex = idx
                                    triggerSelected()
                                } label: {
                                    HStack(spacing: 11) {
                                        Image(systemName: item.icon)
                                            .font(.system(size: 13.5, weight: .medium))
                                            .frame(width: 22)
                                            .foregroundStyle(isSel ? .white : Color.accentColor)

                                        VStack(alignment: .leading, spacing: 1.5) {
                                            Text(item.title)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(isSel ? .white : .primary)
                                            Text(item.subtitle)
                                                .font(.system(size: 11))
                                                .foregroundStyle(isSel ? .white.opacity(0.82) : .secondary)
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        if let hint = item.shortcutHint {
                                            Text(hint)
                                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                .foregroundStyle(isSel ? .white.opacity(0.9) : .secondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .fill(isSel ? Color.white.opacity(0.18) : Color.primary.opacity(0.07))
                                                )
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(isSel ? Color.accentColor : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(idx)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: store.commandPaletteSelectedIndex) { _, newIdx in
                        proxy.scrollTo(newIdx, anchor: .center)
                    }
                }
            }
            .frame(width: 580)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.32), radius: 24, y: 12)
            .padding(.top, 58)
            .onKeyPress(.downArrow) {
                if !filteredItems.isEmpty {
                    store.commandPaletteSelectedIndex = min(filteredItems.count - 1, store.commandPaletteSelectedIndex + 1)
                }
                return .handled
            }
            .onKeyPress(.upArrow) {
                if !filteredItems.isEmpty {
                    store.commandPaletteSelectedIndex = max(0, store.commandPaletteSelectedIndex - 1)
                }
                return .handled
            }
            .onKeyPress(.escape) {
                store.isCommandPalettePresented = false
                return .handled
            }
        }
        .onAppear {
            store.commandPaletteQuery = ""
            store.commandPaletteSelectedIndex = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                isSearchFocused = true
            }
        }
    }

    private func triggerSelected() {
        let idx = store.commandPaletteSelectedIndex
        guard filteredItems.indices.contains(idx) else { return }
        let chosen = filteredItems[idx]
        store.isCommandPalettePresented = false
        chosen.action()
    }
}

// MARK: - Sublime Goto Line HUD (Ctrl+G / Cmd+L)

struct GotoLineOverlayView: View {
    @ObservedObject var store = WorkspaceStore.shared
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .onTapGesture {
                    store.isGotoLinePresented = false
                }

            HStack(spacing: 10) {
                Image(systemName: "arrow.down.right.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Đi tới dòng:")
                    .font(.system(size: 13, weight: .semibold))

                TextField("Nhập số dòng (1…\(store.activeTab?.lineCount ?? 1))", text: $store.gotoLineInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5, design: .monospaced))
                    .focused($isFocused)
                    .onSubmit {
                        if let num = Int(store.gotoLineInput.trimmingCharacters(in: .whitespaces)), num > 0 {
                            store.sendEditorCommand(.jumpToLine(num))
                        }
                        store.isGotoLinePresented = false
                    }

                Button("Nhảy") {
                    if let num = Int(store.gotoLineInput.trimmingCharacters(in: .whitespaces)), num > 0 {
                        store.sendEditorCommand(.jumpToLine(num))
                    }
                    store.isGotoLinePresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 400)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.16), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
            .padding(.top, 64)
            .onKeyPress(.escape) {
                store.isGotoLinePresented = false
                return .handled
            }
        }
        .onAppear {
            store.gotoLineInput = "\(EditorTelemetryStore.shared.cursorLine)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                isFocused = true
            }
        }
    }
}

// MARK: - Compact Inline Find & Replace Bar (Cmd+F / Cmd+Option+F)

struct InlineFindReplaceBar: View {
    @ObservedObject var store = WorkspaceStore.shared
    @FocusState private var findFocused: Bool

    var body: some View {
        let palette = store.effectivePalette
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        store.isReplaceModeInFindBar.toggle()
                    }
                } label: {
                    Image(systemName: store.isReplaceModeInFindBar ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.plainTextColor.opacity(0.75))

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.plainTextColor.opacity(0.6))

                TextField("Tìm kiếm trong tài liệu...", text: $store.findQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(palette.plainTextColor)
                    .focused($findFocused)
                    .onSubmit {
                        store.sendEditorCommand(.findNext(query: store.findQuery, caseSensitive: store.findCaseSensitive))
                    }

                Toggle("Aa", isOn: $store.findCaseSensitive)
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help("Phân biệt chữ HOA / thường")

                Button {
                    store.sendEditorCommand(.findPrevious(query: store.findQuery, caseSensitive: store.findCaseSensitive))
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    store.sendEditorCommand(.findNext(query: store.findQuery, caseSensitive: store.findCaseSensitive))
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    store.isFindBarVisible = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.plainTextColor.opacity(0.7))
            }

            if store.isReplaceModeInFindBar {
                HStack(spacing: 8) {
                    Spacer().frame(width: 26)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.plainTextColor.opacity(0.6))

                    TextField("Thay thế bằng...", text: $store.replaceQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(palette.plainTextColor)
                        .onSubmit {
                            store.sendEditorCommand(.replaceCurrent(
                                query: store.findQuery,
                                replacement: store.replaceQuery,
                                caseSensitive: store.findCaseSensitive
                            ))
                        }

                    Button("Thay thế") {
                        store.sendEditorCommand(.replaceCurrent(
                            query: store.findQuery,
                            replacement: store.replaceQuery,
                            caseSensitive: store.findCaseSensitive
                        ))
                    }
                    .controlSize(.small)

                    Button("Thay tất cả") {
                        store.sendEditorCommand(.replaceAll(
                            query: store.findQuery,
                            replacement: store.replaceQuery,
                            caseSensitive: store.findCaseSensitive
                        ))
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(palette.chromeBackgroundColor)
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.primary.opacity(0.14))
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                findFocused = true
            }
        }
    }
}
