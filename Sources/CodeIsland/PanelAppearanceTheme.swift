import AppKit
import SwiftUI

/// Panel background surface style selectable in Settings -> Appearance.
enum PanelMaterialMode: String, CaseIterable {
    /// Deep OLED pure black (#000000) for maximum contrast and seamless notch blending.
    case pureBlack
    /// Native macOS dark translucent vibrancy (`NSVisualEffectView`, `.hudWindow`).
    case vibrancy

    init(storedValue: String?) {
        self = storedValue.flatMap(PanelMaterialMode.init(rawValue:)) ?? .pureBlack
    }

    var titleKey: String {
        switch self {
        case .pureBlack: return "panel_material_pure_black"
        case .vibrancy: return "panel_material_vibrancy"
        }
    }
}

/// User-customizable accent theme used across unread indicators, active pills,
/// and live preview highlights inside the dark notch panel.
enum PanelAccentTheme: String, CaseIterable, Identifiable {
    case emerald
    case sky
    case violet
    case amber
    case rose
    case mono

    var id: String { rawValue }

    init(storedValue: String?) {
        self = storedValue.flatMap(PanelAccentTheme.init(rawValue:)) ?? .emerald
    }

    var titleKey: String {
        switch self {
        case .emerald: return "accent_theme_emerald"
        case .sky: return "accent_theme_sky"
        case .violet: return "accent_theme_violet"
        case .amber: return "accent_theme_amber"
        case .rose: return "accent_theme_rose"
        case .mono: return "accent_theme_mono"
        }
    }

    var color: Color {
        switch self {
        case .emerald: return Color(red: 0.30, green: 0.90, blue: 0.52)
        case .sky: return Color(red: 0.28, green: 0.80, blue: 1.0)
        case .violet: return Color(red: 0.68, green: 0.56, blue: 1.0)
        case .amber: return Color(red: 1.0, green: 0.72, blue: 0.28)
        case .rose: return Color(red: 1.0, green: 0.45, blue: 0.58)
        case .mono: return Color.white.opacity(0.90)
        }
    }
}

/// Pure AppKit wrapper around `NSVisualEffectView` for native dark macOS vibrancy.
struct NotchVisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.material != material { nsView.material = material }
        if nsView.blendingMode != blendingMode { nsView.blendingMode = blendingMode }
        if nsView.state != .active { nsView.state = .active }
    }
}
