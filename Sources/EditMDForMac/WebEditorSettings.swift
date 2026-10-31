import Foundation

/// Display settings of the embedded md-editor-plus web editor.
/// Persisted in UserDefaults (prefix `mdplus.`) and sent to the webview in the
/// `init` message, mirroring the `mdEditorPlus.*` VS Code settings.
struct WebEditorSettings: Equatable {
    var theme = "light"            // light | claude | dark | os (legacy "sepia"/"sync-os"/"sync-ide" are migrated webview-side)
    var font = "sans"              // sans | serif | mono
    var textSize = "m"             // s | m | l | xl  (14/16/18/20 px)
    var pageWidth = 800
    var fullWidth = true
    var alwaysDarkCode = false
    var alwaysDarkDiagram = false
    var alwaysDarkSource = false
    var sourceFullWidth = true
    var shortenCodeSnippets = false
    var smartTypography = true
    var outlineVisible = false
    var structureMapVisible = false
    var sourceWordWrap = false

    private static let prefix = "mdplus."
    private static let keys = [
        "theme", "font", "textSize", "pageWidth", "fullWidth",
        "alwaysDarkCode", "alwaysDarkDiagram", "alwaysDarkSource", "sourceFullWidth",
        "shortenCodeSnippets", "smartTypography", "outlineVisible", "structureMapVisible", "sourceWordWrap",
    ]

    /// Shape expected by the webview's `init`/`saveDefaults` messages.
    var defaultsDictionary: [String: Any] {
        [
            "theme": theme,
            "font": font,
            "textSize": textSize,
            "pageWidth": pageWidth,
            "fullWidth": fullWidth,
            "alwaysDarkCode": alwaysDarkCode,
            "alwaysDarkDiagram": alwaysDarkDiagram,
            "alwaysDarkSource": alwaysDarkSource,
            "sourceFullWidth": sourceFullWidth,
            "shortenCodeSnippets": shortenCodeSnippets,
            "smartTypography": smartTypography,
            "outlineVisible": outlineVisible,
            "structureMapVisible": structureMapVisible,
            "sourceWordWrap": sourceWordWrap,
        ]
    }

    static func load(from defaults: UserDefaults = .standard) -> WebEditorSettings {
        var settings = WebEditorSettings()
        let d = defaults.dictionaryRepresentation()
        if let v = d[prefix + "theme"] as? String { settings.theme = v }
        if let v = d[prefix + "font"] as? String { settings.font = v }
        if let v = d[prefix + "textSize"] as? String { settings.textSize = v }
        if let v = d[prefix + "pageWidth"] as? Int { settings.pageWidth = v }
        if let v = d[prefix + "fullWidth"] as? Bool { settings.fullWidth = v }
        if let v = d[prefix + "alwaysDarkCode"] as? Bool { settings.alwaysDarkCode = v }
        if let v = d[prefix + "alwaysDarkDiagram"] as? Bool { settings.alwaysDarkDiagram = v }
        if let v = d[prefix + "alwaysDarkSource"] as? Bool { settings.alwaysDarkSource = v }
        if let v = d[prefix + "sourceFullWidth"] as? Bool { settings.sourceFullWidth = v }
        if let v = d[prefix + "shortenCodeSnippets"] as? Bool { settings.shortenCodeSnippets = v }
        if let v = d[prefix + "smartTypography"] as? Bool { settings.smartTypography = v }
        if let v = d[prefix + "outlineVisible"] as? Bool { settings.outlineVisible = v }
        if let v = d[prefix + "structureMapVisible"] as? Bool { settings.structureMapVisible = v }
        if let v = d[prefix + "sourceWordWrap"] as? Bool { settings.sourceWordWrap = v }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        for (key, value) in defaultsDictionary {
            defaults.set(value, forKey: Self.prefix + key)
        }
    }

    static func reset(from defaults: UserDefaults = .standard) {
        for key in keys {
            defaults.removeObject(forKey: prefix + key)
        }
    }

    /// Merge a `defaults` payload sent by the webview (`saveDefaults`).
    mutating func apply(dictionary d: [String: Any]) {
        if let v = d["theme"] as? String { theme = v }
        if let v = d["font"] as? String { font = v }
        if let v = d["textSize"] as? String { textSize = v }
        if let v = d["pageWidth"] as? Int { pageWidth = v }
        if let v = d["fullWidth"] as? Bool { fullWidth = v }
        if let v = d["alwaysDarkCode"] as? Bool { alwaysDarkCode = v }
        if let v = d["alwaysDarkDiagram"] as? Bool { alwaysDarkDiagram = v }
        if let v = d["alwaysDarkSource"] as? Bool { alwaysDarkSource = v }
        if let v = d["sourceFullWidth"] as? Bool { sourceFullWidth = v }
        if let v = d["shortenCodeSnippets"] as? Bool { shortenCodeSnippets = v }
        if let v = d["smartTypography"] as? Bool { smartTypography = v }
    }
}

