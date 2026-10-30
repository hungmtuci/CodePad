import AppKit
import SwiftUI

enum EditorThemeID: String, CaseIterable, Codable, Identifiable, Sendable {
    case monokaiPro = "monokai_pro"
    case mariana = "mariana"
    case dracula = "dracula"
    case githubLight = "github_light"
    case solarizedLight = "solarized_light"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monokaiPro: return "Monokai Pro (Sublime Classic)"
        case .mariana: return "Mariana (Sublime Dark)"
        case .dracula: return "Dracula Night"
        case .githubLight: return "GitHub Light (Sáng tinh gọn)"
        case .solarizedLight: return "Solarized Paper (Giấy ấm)"
        }
    }

    var isDark: Bool {
        switch self {
        case .monokaiPro, .mariana, .dracula:
            return true
        case .githubLight, .solarizedLight:
            return false
        }
    }

    var palette: EditorThemePalette {
        switch self {
        case .monokaiPro:
            return EditorThemePalette(
                id: .monokaiPro,
                isDark: true,
                editorBackgroundHex: "#272822",
                chromeBackgroundHex: "#1E1F1C",
                gutterBackgroundHex: "#272822",
                gutterTextHex: "#75715E",
                activeLineHex: "#3E3D32",
                selectionHex: "#49483E",
                plainTextHex: "#F8F8F2",
                caretHex: "#F8F8F0",
                commentHex: "#7E7A66",
                keywordHex: "#F92672",
                stringHex: "#E6DB74",
                numberHex: "#AE81FF",
                typeHex: "#66D9EF",
                functionHex: "#A6E22E",
                propertyHex: "#FD971F",
                tagHex: "#F92672",
                attributeHex: "#A6E22E",
                operatorHex: "#F92672",
                decoratorHex: "#FD971F",
                headingHex: "#FFD866",
                accentHex: "#FF9800"
            )
        case .mariana:
            return EditorThemePalette(
                id: .mariana,
                isDark: true,
                editorBackgroundHex: "#303841",
                chromeBackgroundHex: "#262D35",
                gutterBackgroundHex: "#303841",
                gutterTextHex: "#65737E",
                activeLineHex: "#3B444F",
                selectionHex: "#4E5A65",
                plainTextHex: "#D8DEE9",
                caretHex: "#F9AE58",
                commentHex: "#7A8894",
                keywordHex: "#C594C5",
                stringHex: "#99C794",
                numberHex: "#F99157",
                typeHex: "#5FB3B3",
                functionHex: "#6699CC",
                propertyHex: "#FAC863",
                tagHex: "#EC5F67",
                attributeHex: "#C594C5",
                operatorHex: "#5FB3B3",
                decoratorHex: "#F99157",
                headingHex: "#FAC863",
                accentHex: "#5FB3B3"
            )
        case .dracula:
            return EditorThemePalette(
                id: .dracula,
                isDark: true,
                editorBackgroundHex: "#282A36",
                chromeBackgroundHex: "#1E1F29",
                gutterBackgroundHex: "#282A36",
                gutterTextHex: "#6272A4",
                activeLineHex: "#343746",
                selectionHex: "#44475A",
                plainTextHex: "#F8F8F2",
                caretHex: "#FF79C6",
                commentHex: "#6272A4",
                keywordHex: "#FF79C6",
                stringHex: "#F1FA8C",
                numberHex: "#BD93F9",
                typeHex: "#8BE9FD",
                functionHex: "#50FA7B",
                propertyHex: "#FFB86C",
                tagHex: "#FF79C6",
                attributeHex: "#50FA7B",
                operatorHex: "#FF79C6",
                decoratorHex: "#FFB86C",
                headingHex: "#BD93F9",
                accentHex: "#BD93F9"
            )
        case .githubLight:
            return EditorThemePalette(
                id: .githubLight,
                isDark: false,
                editorBackgroundHex: "#FFFFFF",
                chromeBackgroundHex: "#F4F6F8",
                gutterBackgroundHex: "#FFFFFF",
                gutterTextHex: "#8C959F",
                activeLineHex: "#F3F6FA",
                selectionHex: "#DDF4FF",
                plainTextHex: "#24292F",
                caretHex: "#0969DA",
                commentHex: "#6E7781",
                keywordHex: "#CF222E",
                stringHex: "#0A3069",
                numberHex: "#0550AE",
                typeHex: "#953800",
                functionHex: "#8250DF",
                propertyHex: "#116329",
                tagHex: "#116329",
                attributeHex: "#0550AE",
                operatorHex: "#CF222E",
                decoratorHex: "#8250DF",
                headingHex: "#0969DA",
                accentHex: "#0969DA"
            )
        case .solarizedLight:
            return EditorThemePalette(
                id: .solarizedLight,
                isDark: false,
                editorBackgroundHex: "#FDF6E3",
                chromeBackgroundHex: "#EEE8D5",
                gutterBackgroundHex: "#FDF6E3",
                gutterTextHex: "#93A1A1",
                activeLineHex: "#F5EFDC",
                selectionHex: "#E6DFCB",
                plainTextHex: "#586E75",
                caretHex: "#268BD2",
                commentHex: "#93A1A1",
                keywordHex: "#859900",
                stringHex: "#2AA198",
                numberHex: "#D33682",
                typeHex: "#B58900",
                functionHex: "#268BD2",
                propertyHex: "#CB4B16",
                tagHex: "#268BD2",
                attributeHex: "#859900",
                operatorHex: "#859900",
                decoratorHex: "#CB4B16",
                headingHex: "#CB4B16",
                accentHex: "#268BD2"
            )
        }
    }
}

struct EditorThemePalette: Equatable, Sendable {
    let id: EditorThemeID
    let isDark: Bool
    let editorBackgroundHex: String
    let chromeBackgroundHex: String
    let gutterBackgroundHex: String
    let gutterTextHex: String
    let activeLineHex: String
    let selectionHex: String
    let plainTextHex: String
    let caretHex: String
    let commentHex: String
    let keywordHex: String
    let stringHex: String
    let numberHex: String
    let typeHex: String
    let functionHex: String
    let propertyHex: String
    let tagHex: String
    let attributeHex: String
    let operatorHex: String
    let decoratorHex: String
    let headingHex: String
    let accentHex: String

    var editorBackgroundNS: NSColor { NSColor.fromHex(editorBackgroundHex) }
    var chromeBackgroundNS: NSColor { NSColor.fromHex(chromeBackgroundHex) }
    var gutterBackgroundNS: NSColor { NSColor.fromHex(gutterBackgroundHex) }
    var gutterTextNS: NSColor { NSColor.fromHex(gutterTextHex) }
    var activeLineNS: NSColor { NSColor.fromHex(activeLineHex) }
    var selectionNS: NSColor { NSColor.fromHex(selectionHex) }
    var plainTextNS: NSColor { NSColor.fromHex(plainTextHex) }
    var caretNS: NSColor { NSColor.fromHex(caretHex) }
    var commentNS: NSColor { NSColor.fromHex(commentHex) }
    var keywordNS: NSColor { NSColor.fromHex(keywordHex) }
    var stringNS: NSColor { NSColor.fromHex(stringHex) }
    var numberNS: NSColor { NSColor.fromHex(numberHex) }
    var typeNS: NSColor { NSColor.fromHex(typeHex) }
    var functionNS: NSColor { NSColor.fromHex(functionHex) }
    var propertyNS: NSColor { NSColor.fromHex(propertyHex) }
    var tagNS: NSColor { NSColor.fromHex(tagHex) }
    var attributeNS: NSColor { NSColor.fromHex(attributeHex) }
    var operatorNS: NSColor { NSColor.fromHex(operatorHex) }
    var decoratorNS: NSColor { NSColor.fromHex(decoratorHex) }
    var headingNS: NSColor { NSColor.fromHex(headingHex) }

    var editorBackgroundColor: Color { Color(nsColor: editorBackgroundNS) }
    var chromeBackgroundColor: Color { Color(nsColor: chromeBackgroundNS) }
    var plainTextColor: Color { Color(nsColor: plainTextNS) }
    var accentColor: Color { Color(nsColor: NSColor.fromHex(accentHex)) }
}

extension NSColor {
    static func fromHex(_ hex: String, alpha: CGFloat = 1.0) -> NSColor {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }
        guard clean.count == 6, let rgb = UInt64(clean, radix: 16) else {
            return .labelColor
        }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}
