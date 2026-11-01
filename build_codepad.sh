#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_WORKSPACE_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="CodePad"
BUNDLE_ID="com.hunglx.CodePad"
VERSION="${CODEPAD_VERSION:-1.0.2}"
BUILD_NUMBER="${CODEPAD_BUILD_NUMBER:-3}"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
ROOT_APP_BUNDLE="$ROOT_WORKSPACE_DIR/$APP_NAME.app"
DIST_DIR="$PROJECT_DIR/dist"

echo "==> [1/6] Đang biên dịch $APP_NAME (Universal Binary arm64 + x86_64 Release)..."
if swift build -c release --product "$APP_NAME" --arch arm64 --arch x86_64 2>/dev/null; then
    BIN_PATH="$(swift build -c release --product "$APP_NAME" --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"
else
    swift build -c release --product "$APP_NAME"
    BIN_PATH="$(swift build -c release --product "$APP_NAME" --show-bin-path)/$APP_NAME"
fi

echo "==> [2/6] Đang tạo biểu tượng ứng dụng (AppIcon.icns) phong cách Sublime macOS..."
ICONSET_DIR="$PROJECT_DIR/.build/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

swift - "$ICONSET_DIR" << 'SWIFT_ICON'
import AppKit

let outDir = CommandLine.arguments[1]
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (px, name) in sizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(px)
    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let inset = s * 0.08
    let bgRect = rect.insetBy(dx: inset, dy: inset)
    let radius = bgRect.width * 0.228

    // Deep Sublime Charcoal-Slate macOS Squircle
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)
    let bgGrad = NSGradient(colors: [
        NSColor(calibratedRed: 0.19, green: 0.20, blue: 0.18, alpha: 1.0),
        NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 1.0),
        NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.13, alpha: 1.0)
    ])!
    bgGrad.draw(in: bgPath, angle: -60)

    // Subtle glass border highlight
    NSColor.white.withAlphaComponent(0.14).setStroke()
    bgPath.lineWidth = max(1.0, s * 0.012)
    bgPath.stroke()

    // Subtle Monokai syntax color bars at top-left
    let barH = max(1.5, s * 0.028)
    let barY = s * 0.72
    let bars: [(CGFloat, CGFloat, NSColor)] = [
        (0.22, 0.14, NSColor(calibratedRed: 0.98, green: 0.15, blue: 0.45, alpha: 0.92)),
        (0.39, 0.18, NSColor(calibratedRed: 0.65, green: 0.89, blue: 0.18, alpha: 0.92)),
        (0.60, 0.15, NSColor(calibratedRed: 0.40, green: 0.85, blue: 0.94, alpha: 0.92))
    ]
    for (xPct, wPct, col) in bars {
        let r = NSRect(x: s * xPct, y: barY, width: s * wPct, height: barH)
        col.setFill()
        NSBezierPath(roundedRect: r, xRadius: barH * 0.5, yRadius: barH * 0.5).fill()
    }

    // Iconic Warm Sublime Amber-Orange </> Symbol
    if let sym = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: nil) {
        let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.34, weight: .bold)
            .applying(.init(paletteColors: [NSColor(calibratedRed: 1.0, green: 0.60, blue: 0.12, alpha: 1.0)]))
        if let rendered = sym.withSymbolConfiguration(cfg) {
            let sz = rendered.size
            let drawRect = NSRect(
                x: rect.midX - sz.width / 2.0,
                y: rect.midY - sz.height / 2.0 - s * 0.05,
                width: sz.width,
                height: sz.height
            )
            rendered.draw(in: drawRect)
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    }
}
SWIFT_ICON

echo "==> [3/6] Đang đóng gói $APP_NAME.app..."
STAGE_ROOT="$(mktemp -d /tmp/CodePadBuildStage.XXXXXX)"
trap 'rm -rf "$STAGE_ROOT"' EXIT
STAGE_APP="$STAGE_ROOT/$APP_NAME.app"
STAGE_CONTENTS="$STAGE_APP/Contents"
STAGE_MACOS="$STAGE_CONTENTS/MacOS"
STAGE_RESOURCES="$STAGE_CONTENTS/Resources"
mkdir -p "$STAGE_MACOS" "$STAGE_RESOURCES"

cp -X "$BIN_PATH" "$STAGE_MACOS/$APP_NAME"
chmod +x "$STAGE_MACOS/$APP_NAME"

iconutil -c icns "$ICONSET_DIR" -o "$STAGE_RESOURCES/AppIcon.icns" || true

cat > "$STAGE_CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>vi</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>CodePad</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Source Code &amp; Markup Document</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.text</string>
                <string>public.source-code</string>
                <string>public.html</string>
                <string>public.json</string>
                <string>public.xml</string>
                <string>net.daringfireball.markdown</string>
            </array>
        </dict>
    </array>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

echo "==> [4/6] Đang ký số (Ad-hoc Codesign)..."
xattr -cr "$STAGE_APP" 2>/dev/null || true
codesign --force --deep --sign - "$STAGE_APP"
codesign --verify --deep --strict "$STAGE_APP"

rm -rf "$APP_BUNDLE"
ditto --noextattr "$STAGE_APP" "$APP_BUNDLE"
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> [5/6] Đang tạo bộ cài đặt .DMG và .ZIP tại thư mục dist/..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

DMG_STAGING="$STAGE_ROOT/dmg_staging"
mkdir -p "$DMG_STAGING"

ditto --noextattr "$STAGE_APP" "$DMG_STAGING/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"

cat > "$DMG_STAGING/Cai_Dat_CodePad.command" << 'INSTALLER_EOF'
#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SRC="$DIR/CodePad.app"
APP_DST="/Applications/CodePad.app"

echo "===================================================="
echo "  Đang cài đặt CodePad vào /Applications..."
echo "===================================================="

pkill -f "/Applications/CodePad.app" 2>/dev/null || true
rm -rf "$APP_DST"
ditto --noextattr "$APP_SRC" "$APP_DST"
xattr -cr "$APP_DST" 2>/dev/null || true

echo "✓ Đã cài đặt thành công tại: $APP_DST"
echo "✓ Đang khởi chạy CodePad..."
open "$APP_DST"
sleep 1
INSTALLER_EOF
chmod +x "$DMG_STAGING/Cai_Dat_CodePad.command"
xattr -cr "$DMG_STAGING" 2>/dev/null || true

DMG_PATH="$DIST_DIR/${APP_NAME}-Installer-v${VERSION}.dmg"
hdiutil create -volname "${APP_NAME} Installer" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

ZIP_PATH="$DIST_DIR/${APP_NAME}-v${VERSION}-macOS.zip"
ditto -c -k --norsrc --noextattr --keepParent "$STAGE_APP" "$ZIP_PATH"

echo "==> [6/6] Đồng bộ $ROOT_APP_BUNDLE..."
if [ "$ROOT_WORKSPACE_DIR" != "$PROJECT_DIR" ]; then
    rm -rf "$ROOT_APP_BUNDLE"
    ditto --noextattr "$STAGE_APP" "$ROOT_APP_BUNDLE"
    xattr -cr "$ROOT_APP_BUNDLE" 2>/dev/null || true
    codesign --force --deep --sign - "$ROOT_APP_BUNDLE"
fi

echo "==> Hoàn tất!"
echo "    - Ứng dụng: $APP_BUNDLE"
echo "    - Bộ cài DMG: $DMG_PATH"
echo "    - Bản nén ZIP: $ZIP_PATH"
