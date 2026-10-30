import AppKit
import SwiftUI

struct MainEditorWorkspaceView: View {
    @ObservedObject var store = WorkspaceStore.shared
    @ObservedObject var updater = UpdateCheckerService.shared

    var body: some View {
        let palette = store.effectivePalette

        ZStack {
            // Paint seamless Sublime background color all the way under the macOS Titlebar / Traffic Lights,
            // while keeping interactive controls strictly inside safeArea so NSTitlebarContainerView never blocks clicks!
            palette.chromeBackgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if !store.isZenMode {
                    topSublimeHeaderBar(palette: palette)
                }

                GeometryReader { geo in
                    let sidebarW: CGFloat = (store.preferences.showSidebar && !store.isZenMode) ? 215 : 0
                    let contentTotalW = max(320, geo.size.width - sidebarW - (sidebarW > 0 ? 1 : 0))

                    HStack(spacing: 0) {
                        if sidebarW > 0 {
                            leftScratchpadSidebar(palette: palette)
                                .frame(width: sidebarW)
                            Divider().overlay(Color.primary.opacity(0.14))
                        }

                        if store.isSplitPreviewVisible {
                            let minPane: CGFloat = min(280, contentTotalW * 0.35)
                            let previewW = max(minPane, min(contentTotalW - minPane - 8, contentTotalW * store.previewWidthRatio))
                            let editorW = max(minPane, contentTotalW - previewW - 8)

                            editorColumn(palette: palette)
                                .frame(width: editorW, height: geo.size.height)

                            resizableSplitDivider(sidebarOffset: sidebarW, totalWidth: contentTotalW, palette: palette)
                                .frame(height: geo.size.height)

                            LivePreviewPaneView(isStandaloneWindow: false)
                                .frame(width: previewW, height: geo.size.height)
                        } else {
                            editorColumn(palette: palette)
                                .frame(width: contentTotalW, height: geo.size.height)
                        }
                    }
                    .coordinateSpace(name: "SplitWorkspace")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.editorBackgroundColor)

                if store.preferences.showStatusBar && !store.isZenMode {
                    bottomSublimeStatusBar(palette: palette)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if store.isCommandPalettePresented {
                CommandPaletteOverlayView()
                    .zIndex(20)
            }

            if store.isGotoLinePresented {
                GotoLineOverlayView()
                    .zIndex(22)
            }

            if updater.showUpdatePromptDialog {
                GitHubUpdateOverlayCard()
                    .zIndex(25)
            }

            if let toast = store.activeToast {
                VStack {
                    Spacer()
                    toastBanner(toast: toast)
                        .padding(.bottom, store.preferences.showStatusBar ? 38 : 16)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(30)
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .sheet(isPresented: $store.isExportSheetPresented) {
            ExportCenterSheetView()
        }
        .sheet(isPresented: $store.isPreferencesPresented) {
            PreferencesSheetView()
        }
    }

    // MARK: - Top Sublime Tab Bar + Action Controls (100% Clickable Below Titlebar)

    @ViewBuilder
    private func topSublimeHeaderBar(palette: EditorThemePalette) -> some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    store.preferences.showSidebar.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.plainTextColor.opacity(0.8))
            .help("Ẩn / Hiện Thanh bên danh sách tệp (⌘\\)")

            // Scrollable Sublime-inspired Tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(store.tabs) { tab in
                        let isActive = (tab.id == store.activeTabID)
                        sublimeTabPill(tab: tab, isActive: isActive, palette: palette)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                store.createNewTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.plainTextColor.opacity(0.9))
            .help("Tạo Tab mới (⌘N)")

            Button {
                store.pasteClipboardIntoNewTab()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("Dán mới")
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.plainTextColor.opacity(0.9))
            .help("Dán Clipboard thành Tab mới & tự động nhận diện ngôn ngữ (⌘⇧V)")

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 2)

            // Live Preview Split + Popout Window Controls
            HStack(spacing: 4) {
                Button {
                    store.toggleSplitPreview()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: store.isSplitPreviewVisible ? "eye.fill" : "eye")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("Preview")
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(store.isSplitPreviewVisible ? Color.accentColor : Color.primary.opacity(0.08))
                    )
                    .foregroundStyle(store.isSplitPreviewVisible ? .white : palette.plainTextColor.opacity(0.9))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Bật / Tắt khung Xem trước trực tiếp cạnh bên cho Markdown, HTML, SVG, JSON, CSV (⌘⌥P)")

                Button {
                    store.openOrFocusFloatingPreviewWindow()
                } label: {
                    Image(systemName: "pip.exit")
                        .font(.system(size: 11.5, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.plainTextColor.opacity(0.84))
                .help("Mở Cửa sổ Xem trước riêng biệt (⌘⇧O)")
            }

            // Export Dropdown Menu (PDF / DOCX / HTML / RTF / ODT / PNG)
            Menu {
                if let tab = store.activeTab {
                    Section("Xuất tài liệu chuẩn đẹp") {
                        Button {
                            ExportService.shared.promptAndExport(tab: tab, format: .pdf, preferences: store.preferences)
                        } label: {
                            Label("Xuất PDF chuẩn A4 (.pdf)…", systemImage: "doc.richtext.fill")
                        }

                        Button {
                            ExportService.shared.promptAndExport(tab: tab, format: .docx, preferences: store.preferences)
                        } label: {
                            Label("Xuất Microsoft Word (.docx)…", systemImage: "doc.text.fill")
                        }

                        Button {
                            ExportService.shared.promptAndExport(tab: tab, format: .html, preferences: store.preferences)
                        } label: {
                            Label("Xuất Trang Web độc lập (.html)…", systemImage: "safari.fill")
                        }

                        Button {
                            ExportService.shared.promptAndExport(tab: tab, format: .rtf, preferences: store.preferences)
                        } label: {
                            Label("Xuất Rich Text (.rtf)…", systemImage: "text.alignleft")
                        }

                        Button {
                            ExportService.shared.promptAndExport(tab: tab, format: .odt, preferences: store.preferences)
                        } label: {
                            Label("Xuất OpenDocument (.odt)…", systemImage: "doc.fill")
                        }

                        Button {
                            ExportService.shared.promptAndExport(tab: tab, format: .pngCard, preferences: store.preferences)
                        } label: {
                            Label("Xuất Ảnh chụp Code @2x (.png)…", systemImage: "photo.artframe")
                        }
                    }

                    Divider()

                    Section("Sao chép nhanh giữ định dạng") {
                        Button {
                            ExportService.shared.copyHighlightedRichTextToClipboard(tab: tab, preferences: store.preferences)
                        } label: {
                            Label("Chép Rich Text giữ màu (dán vào Word/Pages)", systemImage: "paintbrush.pointed")
                        }

                        Button {
                            ExportService.shared.copyCodeCardImageToClipboard(tab: tab, preferences: store.preferences)
                        } label: {
                            Label("Chép Ảnh chụp Code vào Clipboard", systemImage: "photo.on.rectangle")
                        }
                    }

                    Divider()

                    Button {
                        store.isExportSheetPresented = true
                    } label: {
                        Label("Mở Trung tâm Xuất tệp & Tuỳ chọn (⌘E)…", systemImage: "slider.horizontal.3")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("Xuất PDF/DOCX")
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.09)))
                .foregroundStyle(palette.plainTextColor.opacity(0.94))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Xuất ra PDF, Word (.docx), HTML, RTF, ODT hoặc Ảnh Code PNG (⌘E)")

            Button {
                store.isCommandPalettePresented.toggle()
            } label: {
                Image(systemName: "command")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.plainTextColor.opacity(0.82))
            .help("Mở Bảng lệnh Sublime Command Palette (⌘⇧P)")

            Button {
                store.isPreferencesPresented = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.plainTextColor.opacity(0.82))
            .help("Cài đặt CodePad (⌘,)")
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(palette.chromeBackgroundColor)
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.primary.opacity(0.16))
        }
    }

    @ViewBuilder
    private func sublimeTabPill(tab: DocumentTab, isActive: Bool, palette: EditorThemePalette) -> some View {
        HStack(spacing: 6) {
            Text(tab.language.shortBadge)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(tab.language.accentColor)
                .padding(.horizontal, 4.5)
                .padding(.vertical, 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(tab.language.accentColor.opacity(0.16))
                )

            Text(tab.displayTitle)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(palette.plainTextColor.opacity(isActive ? 0.96 : 0.65))
                .lineLimit(1)

            if tab.isDirty && tab.fileURL != nil {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }

            Button {
                store.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.plainTextColor.opacity(0.55))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isActive ? palette.editorBackgroundColor : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isActive ? palette.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectTab(tab.id)
        }
    }

    // MARK: - Editor Column

    @ViewBuilder
    private func editorColumn(palette: EditorThemePalette) -> some View {
        VStack(spacing: 0) {
            if store.isFindBarVisible {
                InlineFindReplaceBar()
            }

            if let tab = store.activeTab {
                NativeCodeEditorView(
                    tabID: tab.id,
                    text: tab.content,
                    language: tab.language,
                    palette: palette,
                    preferences: store.preferences,
                    pendingCommand: store.pendingEditorCommand,
                    onTextChange: { updatedText, wasPaste in
                        store.updateActiveTabContent(updatedText, immediateDetect: wasPaste)
                    },
                    onCursorChange: { ln, col, selLen in
                        if store.activeCursorLine != ln { store.activeCursorLine = ln }
                        if store.activeCursorColumn != col { store.activeCursorColumn = col }
                        if store.selectedCharCount != selLen { store.selectedCharCount = selLen }
                    },
                    onScrollFractionChange: { frac in
                        if abs(store.editorScrollFraction - frac) > 0.008 {
                            store.editorScrollFraction = frac
                        }
                    },
                    onOpenDroppedFile: { fileURL in
                        store.openFileURL(fileURL)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(palette.editorBackgroundColor)
        .clipped()
    }

    @ViewBuilder
    private func resizableSplitDivider(sidebarOffset: CGFloat, totalWidth: CGFloat, palette: EditorThemePalette) -> some View {
        ZStack {
            Rectangle()
                .fill(palette.chromeBackgroundColor)
            Rectangle()
                .fill(Color.primary.opacity(0.14))
                .frame(width: 1)
            Capsule()
                .fill(palette.plainTextColor.opacity(0.32))
                .frame(width: 3, height: 32)
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("SplitWorkspace"))
                .onChanged { value in
                    let localX = value.location.x - sidebarOffset
                    let proposedPreviewW = totalWidth - localX
                    let ratio = proposedPreviewW / max(320, totalWidth)
                    store.previewWidthRatio = min(0.70, max(0.26, ratio))
                }
        )
    }

    // MARK: - Optional Left Scratchpad & Recent Files Sidebar (Cmd+\)

    @ViewBuilder
    private func leftScratchpadSidebar(palette: EditorThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CÁC TAB ĐANG MỞ")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(palette.plainTextColor.opacity(0.5))
                Spacer()
                Button {
                    store.openFileDialog()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.plainTextColor.opacity(0.75))
                .help("Mở tệp từ máy Mac (⌘O)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(store.tabs) { tab in
                        let isSel = (tab.id == store.activeTabID)
                        Button {
                            store.selectTab(tab.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: tab.language.sfSymbol)
                                    .font(.system(size: 12))
                                    .foregroundStyle(tab.language.accentColor)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tab.displayTitle)
                                        .font(.system(size: 12, weight: isSel ? .semibold : .regular))
                                        .foregroundStyle(palette.plainTextColor.opacity(isSel ? 1.0 : 0.78))
                                        .lineLimit(1)
                                    Text("\(tab.language.displayName) • \(tab.lineCount) dòng")
                                        .font(.system(size: 10))
                                        .foregroundStyle(palette.plainTextColor.opacity(0.46))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(isSel ? Color.accentColor.opacity(0.20) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if !store.recentFilePaths.isEmpty {
                        Text("MỞ GẦN ĐÂY")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(palette.plainTextColor.opacity(0.5))
                            .padding(.top, 14)
                            .padding(.horizontal, 6)

                        ForEach(store.recentFilePaths, id: \.self) { path in
                            let url = URL(fileURLWithPath: path)
                            Button {
                                store.openFileURL(url)
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 11))
                                        .foregroundStyle(palette.plainTextColor.opacity(0.5))
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(palette.plainTextColor.opacity(0.75))
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 6)
            }

            Divider().overlay(Color.primary.opacity(0.14))

            VStack(spacing: 6) {
                Button {
                    if updater.availableUpdateInfo != nil {
                        updater.showUpdatePromptDialog = true
                    } else {
                        updater.checkForUpdatesManually()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: updater.availableUpdateInfo != nil ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath")
                            .foregroundStyle(updater.availableUpdateInfo != nil ? .green : Color.accentColor)
                        Text(updater.availableUpdateInfo.map { "Cập nhật v\($0.version)" } ?? "Kiểm tra Update (GitHub)")
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.plainTextColor.opacity(0.9))
            }
            .padding(10)
        }
        .background(palette.chromeBackgroundColor)
    }

    // MARK: - Sublime Bottom Status Bar

    @ViewBuilder
    private func bottomSublimeStatusBar(palette: EditorThemePalette) -> some View {
        HStack(spacing: 12) {
            Button {
                store.isGotoLinePresented = true
            } label: {
                Text("Dòng \(store.activeCursorLine), Cột \(store.activeCursorColumn)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .help("Bấm để nhảy nhanh tới dòng bất kỳ (⌃G)")

            if let tab = store.activeTab {
                if store.selectedCharCount > 0 {
                    Text("Đã chọn \(store.selectedCharCount) ký tự")
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .foregroundStyle(palette.accentColor)
                } else {
                    Text("\(tab.lineCount) dòng • \(tab.wordCount) từ • \(tab.characterCount) ký tự")
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .opacity(0.75)
                }
            }

            Spacer(minLength: 8)

            Button {
                store.preferences.showMinimap.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sidebar.trailing")
                    Text("Minimap")
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .fixedSize(horizontal: true, vertical: false)
                .opacity(store.preferences.showMinimap ? 0.95 : 0.5)
            }
            .buttonStyle(.plain)
            .help("Bật / Tắt thanh Minimap kiểu Sublime Text (⌘⌥M)")

            Menu {
                ForEach([2, 4, 8], id: \.self) { w in
                    Button("Độ rộng Tab: \(w) Spaces") {
                        store.preferences.tabWidth = w
                    }
                }
                Divider()
                Toggle("Tự xuống dòng (Word Wrap)", isOn: $store.preferences.wordWrap)
            } label: {
                Text("Spaces: \(store.preferences.tabWidth)")
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                Toggle("Tự động Sáng / Tối theo macOS", isOn: $store.preferences.followSystemAppearance)
                Divider()
                ForEach(EditorThemeID.allCases) { theme in
                    Button {
                        store.preferences.followSystemAppearance = false
                        store.preferences.themeID = theme
                    } label: {
                        HStack {
                            Text(theme.displayName)
                            if !store.preferences.followSystemAppearance && store.preferences.themeID == theme {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: palette.isDark ? "moon.stars" : "sun.max")
                    Text(store.preferences.followSystemAppearance ? "Auto macOS" : store.preferences.themeID.palette.id.displayName.components(separatedBy: " (").first ?? "Theme")
                        .lineLimit(1)
                }
                .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if let tab = store.activeTab {
                Menu {
                    Button {
                        store.setLanguageForActiveTab(.plainText, autoDetect: true)
                    } label: {
                        Label(
                            tab.isLanguageAutoDetected ? "✓ Tự động nhận diện (Đang bật)" : "Bật Tự động nhận diện ngôn ngữ",
                            systemImage: "wand.and.rays"
                        )
                    }
                    Divider()
                    ForEach(CodeLanguage.allCases) { lang in
                        Button {
                            store.setLanguageForActiveTab(lang, autoDetect: false)
                        } label: {
                            Label(lang.displayName, systemImage: lang.sfSymbol)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if tab.isLanguageAutoDetected {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                                .foregroundStyle(palette.accentColor)
                            Text("Tự động: \(tab.language.displayName)")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                        } else {
                            Image(systemName: tab.language.sfSymbol)
                                .font(.system(size: 10))
                            Text(tab.language.displayName)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Ngôn ngữ tô màu cú pháp — Bấm để chọn ngôn ngữ hoặc bật Tự động nhận diện")
            }

            Button {
                if updater.availableUpdateInfo != nil {
                    updater.showUpdatePromptDialog = true
                } else {
                    updater.checkForUpdatesManually()
                }
            } label: {
                HStack(spacing: 4) {
                    if updater.state == .checking {
                        ProgressView()
                            .controlSize(.mini)
                    } else if let info = updater.availableUpdateInfo {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.green)
                        Text("Cập nhật v\(info.version)")
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("GitHub v\(updater.currentVersion)")
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 2.5)
                .background(
                    Capsule()
                        .fill(updater.availableUpdateInfo != nil ? Color.green.opacity(0.18) : Color.primary.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            .help("Kiểm tra và cập nhật tự động phiên bản mới từ GitHub (hungmtuci/CodePad — ⌘U)")
        }
        .foregroundStyle(palette.plainTextColor.opacity(0.86))
        .padding(.horizontal, 12)
        .frame(height: 27)
        .background(palette.chromeBackgroundColor)
        .overlay(alignment: .top) {
            Divider().overlay(Color.primary.opacity(0.16))
        }
    }

    // MARK: - Interactive Toast Banner

    @ViewBuilder
    private func toastBanner(toast: WorkspaceToast) -> some View {
        HStack(spacing: 10) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? .orange : .green)

            Text(toast.message)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)

            if let url = toast.revealFileURL {
                Button {
                    store.revealInFinder(url)
                    store.dismissToast()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                        Text("Hiện trên Finder")
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            Button {
                store.dismissToast()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 12, y: 5)
    }
}
