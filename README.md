# CodePad cho macOS — Trình Soạn Thảo & Dán Code Tối Giản (Cảm Hứng Sublime Text)

[![Release](https://img.shields.io/github/v/release/hungmtuci/CodePad?label=Release&color=orange)](https://github.com/hungmtuci/CodePad/releases/latest)
[![Platform](https://img.shields.io/badge/macOS-14.0%2B-0A84FF)](https://github.com/hungmtuci/CodePad)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**CodePad** là ứng dụng Native macOS (`Swift + AppKit/NSTextView + SwiftUI + WKWebView`, yêu cầu `macOS 14.0+`) siêu nhẹ, khởi động tức thì, lấy cảm hứng từ triết lý **"Text Editing, Done Right" của Sublime Text** — sinh ra để bạn **dán hoặc viết nhanh bất kỳ đoạn code / ghi chú nào** mà không cần tạo project phức tạp.

---

## 📥 Tải về & Tự động cập nhật (GitHub Releases)

- Tải bộ cài mới nhất (`.dmg` hoặc `.zip` Universal Binary `arm64 + x86_64`) tại: **[GitHub Releases — hungmtuci/CodePad](https://github.com/hungmtuci/CodePad/releases/latest)**
- **Cập nhật 1 chạm ngay trong ứng dụng**:
  - Bấm nút **`Cập nhật GitHub`** ngay ở góc phải dưới thanh trạng thái (Status Bar), hoặc ở cuối thanh bên trái, hoặc dùng phím tắt **`⌘U`** (`CodePad > Kiểm tra cập nhật từ GitHub…`).
  - Khi có phiên bản mới trên GitHub Releases, CodePad tự động tải gói cập nhật kèm thanh tiến trình trực tiếp, gỡ cờ Gatekeeper (`xattr -cr`), thay thế nguyên tử `CodePad.app` và khởi động lại ngay.

---

## ✨ Tính năng nổi bật

### 1. Dán là Tự Động Nhận Diện & Tô Màu Cú Pháp (25+ Ngôn Ngữ)
- Bộ phân tích thông minh `LanguageDetector` tự động nhận diện ngôn ngữ ngay khoảnh khắc bạn bấm **`⌘V`** hoặc **`⌘⇧V`** (`Dán mới`):
  - `Python`, `Swift`, `JavaScript`, `TypeScript`, `HTML`, `CSS`, `Markdown`, `SQL`, `JSON`, `Shell / Bash`, `YAML`, `XML`, `SVG`, `Mermaid`, `CSV / TSV`, `Go`, `Rust`, `C / C++`, `Java / Kotlin`, `C#`, `PHP`, `Ruby`, `Dockerfile`, `LaTeX`.
- Hoạt động mượt mà với **bộ gõ Tiếng Việt (Telex / VNI / OpenKey)** mà không bị nuốt dấu khi gõ tốc độ cao.

### 2. Mang Linh Hồn Sublime Text Lên Giao Diện Thuần macOS
- **Sublime Minimap (`⌘⌥M`)**: Thanh bản đồ thu nhỏ mã nguồn tương tác bên cạnh phải, bấm hoặc kéo để lướt xuyên suốt file dài.
- **Command Palette (`⌘⇧P`)**: Hộp thoại tìm lệnh mờ (fuzzy) kiểu Sublime Text (`Set Syntax`, đổi `Theme`, `Xuất PDF/DOCX`, `Pretty-Print JSON`...).
- **Hot-Exit Scratchpad Tabs**: Tự động lưu nháp toàn bộ các Tab đang mở vào ổ cứng — đóng máy hay thoát ứng dụng đột ngột cũng không bao giờ mất đoạn code vừa dán.
- **5 Bảng Màu Kinh Điển + Tự Động Sáng/Tối**: `Monokai Pro (Sublime Classic)`, `Mariana (Sublime Dark)`, `Dracula Night`, `GitHub Light`, `Solarized Paper` và chế độ **Auto macOS**.

### 3. Cửa Sổ Live Preview Trực Tiếp (Markdown, HTML, SVG, Mermaid, CSV, JSON, LaTeX)
- Khi dán hoặc viết **Markdown, HTML, SVG, Mermaid**, CodePad tự động bật **khung Xem trước trực tiếp (Split Preview `⌘⌥P`)** ngay cạnh bên kèm đồng bộ thanh cuộn.
- Hỗ trợ **Tách ra Cửa sổ Xem trước riêng biệt (`⌘⇧O`)** để kéo sang màn hình thứ hai.
- Tích hợp nút chuyển nhanh **Nền giấy sáng** ngay trên thanh Preview để kiểm tra bố cục trước khi in ấn / xuất file.

### 4. Xuất Tài Liệu Đa Định Dạng 1 Chạm (`⌘E`)
- **PDF chuẩn A4 (`.pdf`)**: Vector sắc nét nhiều trang, giữ trọn màu highlight, bảng biểu, hộp ghi chú và khối code.
- **Microsoft Word (`.docx`)**: Mở chỉnh sửa trực tiếp trong Word, Apple Pages, Google Docs với định dạng phông chữ `Menlo` và màu cú pháp chuẩn.
- **Rich Text (`.rtf`)** & **OpenDocument (`.odt`)**: Tương thích TextEdit, Pages, LibreOffice.
- **Trang Web độc lập (`.html`)**: 1 file HTML duy nhất nhúng sẵn toàn bộ CSS & màu highlight.
- **Ảnh chụp Code sắc nét `@2x` (`.png`)**: Khung cửa sổ macOS sang trọng (kèm nút đèn giao thông & đổ bóng) để gửi nhanh qua Zalo, Messenger, Slack, thuyết trình.
- **Sao chép Rich Text giữ màu (`⌘⌥C`)**: Dán thẳng đoạn code có màu vào Word / Email / Pages.

---

## ⌨️ Bảng phím tắt chuẩn macOS & Sublime Text

| Phím tắt | Tác dụng |
| :--- | :--- |
| `⌘N` / `⌘T` | Tạo Tab nháp mới |
| `⌘⇧V` | Dán nội dung Clipboard thành Tab mới & tự nhận diện ngôn ngữ |
| `⌘O` / `⌘S` / `⌘⇧S` | Mở tệp / Lưu tệp / Lưu thành… |
| `⌘⇧P` | Mở **Command Palette** kiểu Sublime Text |
| `⌘⌥P` | Ẩn / Hiện khung **Live Preview** chia đôi cạnh bên |
| `⌘⇧O` | Mở **Cửa sổ Live Preview riêng biệt** |
| `⌘E` | Mở Trung tâm Xuất tệp (`PDF`, `DOCX`, `HTML`, `RTF`, `ODT`, `PNG`) |
| `⌘P` / `⌘⌥D` | Xuất nhanh ra **PDF** / Xuất nhanh ra **Word (`.docx`)** |
| `⌘⌥C` | Sao chép Rich Text giữ nguyên màu Highlight |
| `⌘/` | Bật / Tắt ghi chú dòng (`//`, `#`, `--`, `<!-- -->`) theo ngôn ngữ |
| `⌘⇧I` | Làm đẹp Code & Pretty-Print JSON |
| `⌘F` / `⌘⌥F` / `⌃G` | Tìm kiếm / Tìm & Thay thế / Đi tới dòng (Goto Line) |
| `⌘⌥M` / `⌘\` / `⌃⌘Z` | Ẩn/Hiện Minimap / Ẩn/Hiện Sidebar / Chế độ Zen Mode |
| `⌘+` / `⌘-` / `⌘0` | Phóng to / Thu nhỏ / Đặt lại cỡ chữ |
| `⌘U` / `⌘,` | Kiểm tra cập nhật GitHub / Mở Cài đặt |

---

## 🛠 Biên dịch từ mã nguồn

```bash
chmod +x build_codepad.sh
./build_codepad.sh
```

Sau khi chạy xong:
- Ứng dụng hoàn chỉnh: `CodePad.app`
- Bộ cài đặt DMG: `dist/CodePad-Installer-v1.0.2.dmg`
- Bản nén ZIP: `dist/CodePad-v1.0.2-macOS.zip`
