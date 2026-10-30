import AppKit
import SwiftUI

// MARK: - Export Center Sheet (PDF, DOCX, HTML, RTF, ODT, PNG, Source)

struct ExportCenterSheetView: View {
    @ObservedObject var store = WorkspaceStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Xuất Tài Liệu & Mã Nguồn")
                        .font(.title3.weight(.bold))
                    if let tab = store.activeTab {
                        Text("\(tab.displayTitle) • \(tab.language.displayName) • \(tab.lineCount) dòng")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(ExportFormat.allCases) { fmt in
                    let isSelected = (store.selectedExportFormat == fmt)
                    Button {
                        store.selectedExportFormat = fmt
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: fmt.sfSymbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : Color.accentColor)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(fmt.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isSelected ? .white : .primary)
                                Text(".\(fmt.fileExtension(for: store.activeTab?.language ?? .plainText))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                            }
                            Spacer()
                        }
                        .padding(11)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            GroupBox("Tuỳ chọn định dạng khi xuất") {
                VStack(alignment: .leading, spacing: 9) {
                    Toggle("Sử dụng nền giấy sáng chuẩn in ấn (khuyên dùng cho PDF / Word)", isOn: $store.preferences.exportUseLightTheme)
                    Toggle("Hiển thị số thứ tự dòng bên trái khối Code", isOn: $store.preferences.exportIncludeLineNumbers)
                    Toggle("Đính kèm tiêu đề tệp, ngôn ngữ & thời gian xuất ở đầu trang", isOn: $store.preferences.exportIncludeHeaderMetadata)
                }
                .font(.system(size: 12.5))
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                if let tab = store.activeTab {
                    Button {
                        ExportService.shared.copyHighlightedRichTextToClipboard(tab: tab, preferences: store.preferences)
                        dismiss()
                    } label: {
                        Label("Chép Rich Text cho Word", systemImage: "doc.on.clipboard")
                    }

                    Button {
                        ExportService.shared.copyCodeCardImageToClipboard(tab: tab, preferences: store.preferences)
                        dismiss()
                    } label: {
                        Label("Chép Ảnh Code", systemImage: "photo.on.rectangle")
                    }
                }

                Spacer()

                Button("Huỷ") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    let tabToExport = store.activeTab
                    let fmt = store.selectedExportFormat
                    let prefs = store.preferences
                    dismiss()
                    if let tabToExport {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            ExportService.shared.promptAndExport(tab: tabToExport, format: fmt, preferences: prefs)
                        }
                    }
                } label: {
                    Label("Chọn nơi lưu & Xuất…", systemImage: "square.and.arrow.down.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}

// MARK: - Native macOS Settings / Preferences Sheet (Cmd+,)

struct PreferencesSheetView: View {
    @ObservedObject var store = WorkspaceStore.shared
    @ObservedObject var updater = UpdateCheckerService.shared
    @Environment(\.dismiss) private var dismiss

    private let fontChoices = ["SF Mono", "Menlo", "Monaco", "Courier New"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Cài Đặt CodePad", systemImage: "slider.horizontal.3")
                    .font(.title3.weight(.bold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Form {
                Section("Giao diện & Bảng màu (Sublime Color Schemes)") {
                    Toggle("Tự động đổi Sáng / Tối theo giao diện macOS", isOn: $store.preferences.followSystemAppearance)

                    Picker("Bảng màu chủ đạo:", selection: $store.preferences.themeID) {
                        ForEach(EditorThemeID.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .disabled(store.preferences.followSystemAppearance)

                    Picker("Phông chữ Code:", selection: $store.preferences.fontFamily) {
                        ForEach(fontChoices, id: \.self) { fam in
                            Text(fam).tag(fam)
                        }
                    }

                    HStack {
                        Text("Cỡ chữ: \(String(format: "%.1f pt", store.preferences.fontSize))")
                        Slider(value: $store.preferences.fontSize, in: 11...24, step: 0.5)
                    }
                }

                Section("Trình soạn thảo & Xem trước trực tiếp") {
                    Picker("Độ rộng phím Tab:", selection: $store.preferences.tabWidth) {
                        Text("2 Spaces").tag(2)
                        Text("4 Spaces").tag(4)
                        Text("8 Spaces").tag(8)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Tự xuống dòng khi tràn khung (Word Wrap)", isOn: $store.preferences.wordWrap)
                    Toggle("Hiện cột số thứ tự dòng (Line Numbers)", isOn: $store.preferences.showLineNumbers)
                    Toggle("Hiện thanh Minimap bên phải kiểu Sublime Text", isOn: $store.preferences.showMinimap)
                    Toggle("Tự động bật Live Preview khi nhận diện Markdown / HTML / SVG", isOn: $store.preferences.autoOpenPreviewForMarkup)
                    Toggle("Đồng bộ thanh cuộn giữa Khung Code và Khung Preview", isOn: $store.preferences.syncPreviewScroll)
                }

                Section("Cập nhật qua GitHub Releases (hungmtuci/CodePad)") {
                    Toggle("Tự động kiểm tra bản mới khi khởi động ứng dụng", isOn: $updater.autoCheckOnLaunch)

                    HStack(spacing: 10) {
                        Text("Phiên bản đang chạy: v\(updater.currentVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            updater.openGitHubRepoPage()
                        } label: {
                            Label("Mở GitHub Repo", systemImage: "safari")
                        }
                        Button {
                            dismiss()
                            updater.checkForUpdatesManually()
                        } label: {
                            Label("Kiểm tra cập nhật ngay", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 430)

            HStack {
                Spacer()
                Button("Đóng") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540)
    }
}

// MARK: - GitHub Self-Update Progress & Release Notes Dialog

struct GitHubUpdateOverlayCard: View {
    @ObservedObject var updater = UpdateCheckerService.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .onTapGesture {
                    if !updater.isBusy {
                        updater.showUpdatePromptDialog = false
                    }
                }

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cập nhật CodePad từ GitHub")
                            .font(.headline)
                        Text("Phiên bản hiện tại: v\(updater.currentVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                switch updater.state {
                case let .available(info):
                    Text("Đã phát hiện phiên bản mới **CodePad v\(info.version)** trên GitHub Releases (`hungmtuci/CodePad`).")
                        .font(.callout)

                    if let notes = info.releaseNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ScrollView {
                            Text(notes)
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .frame(maxHeight: 150)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                    }

                    HStack {
                        Button("Xem trên GitHub") {
                            updater.openReleasesPage()
                        }
                        Spacer()
                        Button("Để sau") {
                            updater.showUpdatePromptDialog = false
                        }
                        Button("Tải & Cập nhật tự động") {
                            updater.installAvailableUpdate()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                case let .downloading(ver, pct):
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Đang tải gói cập nhật CodePad v\(ver)… (\(Int(pct * 100))%)")
                            .font(.callout.weight(.medium))
                        ProgressView(value: pct, total: 1.0)
                            .progressViewStyle(.linear)
                    }

                case let .installing(ver):
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Đang cài đặt CodePad v\(ver), gỡ Gatekeeper và khởi động lại…")
                            .font(.callout)
                    }

                case let .failed(msg):
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(.red)
                    HStack {
                        Spacer()
                        Button("Mở trang GitHub Releases") {
                            updater.openReleasesPage()
                            updater.showUpdatePromptDialog = false
                        }
                        Button("Đóng") {
                            updater.showUpdatePromptDialog = false
                        }
                    }

                default:
                    HStack {
                        Spacer()
                        Button("Đóng") {
                            updater.showUpdatePromptDialog = false
                        }
                    }
                }
            }
            .padding(22)
            .frame(width: 460)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.32), radius: 24, y: 10)
        }
    }
}
