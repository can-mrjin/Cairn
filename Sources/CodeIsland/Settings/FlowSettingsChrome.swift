import AppKit
import SwiftUI

// MARK: - Sidebar Backdrop (Native macOS Frosted Sidebar Material)

struct FlowSidebarBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Settings Palette (Light & Dark Adaptive)

enum FlowSettingsPalette {
    static func detailBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.115) : Color.white
    }

    static func cardFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.055) : Color(red: 0.962, green: 0.964, blue: 0.972)
    }

    static func cardBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.085) : Color.black.opacity(0.05)
    }

    static func rowDivider(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.075) : Color.black.opacity(0.06)
    }

    static func sidebarSelected(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    static func sidebarHovered(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    static func valuePillFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.white
    }

    static func valuePillBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12)
    }
}

// MARK: - Colorful Rounded Square Icon Badge (System Settings Style)

struct SettingsIconBadge: View {
    let systemName: String
    let topColor: Color
    let bottomColor: Color
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [topColor, bottomColor],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.32), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            Image(systemName: systemName)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Page Shell (Fixed Modern Header + Inset-Grouped Scroll Body)

struct FlowSettingsPageShell<Content: View>: View {
    let page: SettingsPage
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            // Header bar aligned with traffic lights
            HStack(spacing: 9) {
                SettingsIconBadge(
                    systemName: page.icon,
                    topColor: page.gradientTop,
                    bottomColor: page.gradientBottom,
                    size: 22
                )
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .frame(height: 52)
            .background(FlowSettingsPalette.detailBackground(scheme))

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    content()
                }
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FlowSettingsPalette.detailBackground(scheme))
    }
}

// MARK: - Inset Grouped Card Section

struct FlowSettingsSection<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.88))
                    .padding(.leading, 4)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(FlowSettingsPalette.cardFill(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(FlowSettingsPalette.cardBorder(scheme), lineWidth: 0.6)
            )

            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

// MARK: - Card Divider

struct FlowSettingsDivider: View {
    @Environment(\.colorScheme) private var scheme
    var leadingInset: CGFloat = 14

    var body: some View {
        Rectangle()
            .fill(FlowSettingsPalette.rowDivider(scheme))
            .frame(height: 0.5)
            .padding(.leading, leadingInset)
            .padding(.trailing, 14)
    }
}

// MARK: - Standard Card Rows

struct FlowSettingsRow<Content: View>: View {
    var verticalPadding: CGFloat = 11
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FlowSettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        FlowSettingsRow {
            HStack(alignment: subtitle == nil ? .center : .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.regular)
                    .padding(.top, subtitle == nil ? 0 : 1)
            }
        }
    }
}

struct FlowSettingsPickerRow<SelectionValue: Hashable, Options: View>: View {
    let title: String
    var subtitle: String? = nil
    @Binding var selection: SelectionValue
    var disabled: Bool = false
    @ViewBuilder let options: () -> Options

    var body: some View {
        FlowSettingsRow {
            HStack(alignment: subtitle == nil ? .center : .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(disabled ? .secondary : .primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                Picker("", selection: $selection) {
                    options()
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(disabled)
            }
        }
    }
}

struct FlowValuePill: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(FlowSettingsPalette.valuePillFill(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(FlowSettingsPalette.valuePillBorder(scheme), lineWidth: 0.7)
            )
    }
}

struct FlowSettingsSliderRow: View {
    let title: String
    var subtitle: String? = nil
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var tickCount: Int = 11
    var disabled: Bool = false

    var body: some View {
        FlowSettingsRow(verticalPadding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(disabled ? .secondary : .primary)
                    Spacer(minLength: 12)
                    FlowValuePill(text: valueText)
                }

                VStack(spacing: 4) {
                    Slider(value: $value, in: range, step: step)
                        .disabled(disabled)
                        .accessibilityLabel(Text(title))
                        .accessibilityValue(Text(valueText))

                    if tickCount > 1 {
                        HStack(spacing: 0) {
                            ForEach(0..<tickCount, id: \.self) { idx in
                                Circle()
                                    .fill(Color.primary.opacity(0.18))
                                    .frame(width: 2.5, height: 2.5)
                                if idx < tickCount - 1 {
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .padding(.horizontal, 7)
                    }
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - App Logo (Cairn Artwork)

struct AppLogoView: View {
    var size: CGFloat = 100
    var showBackground: Bool = true

    private static let cachedLogoImage: NSImage? = {
        guard let url = Bundle.appModule.url(
            forResource: "CairnLogo",
            withExtension: "png",
            subdirectory: "Resources"
        ) else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        if showBackground, let img = Self.cachedLogoImage {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.22), radius: size * 0.11, y: size * 0.05)
        } else {
            // Compact liquid-flow pill glyph (used on the expanded dark notch header or fallback)
            Canvas { ctx, sz in
                let inset = sz.width * (showBackground ? 0.1 : 0.06)
                let rect = CGRect(x: inset, y: inset, width: sz.width - inset * 2, height: sz.height - inset * 2)
                if showBackground {
                    let bgPath = Path(roundedRect: rect, cornerRadius: rect.width * 0.225, style: .continuous)
                    ctx.fill(
                        bgPath,
                        with: .radialGradient(
                            Gradient(colors: [Color(red: 0.11, green: 0.15, blue: 0.28), Color(red: 0.04, green: 0.05, blue: 0.10)]),
                            center: CGPoint(x: rect.midX, y: rect.midY * 0.85),
                            startRadius: 0,
                            endRadius: rect.width * 0.7
                        )
                    )
                }
                let pillW = rect.width * (showBackground ? 0.74 : 0.86)
                let pillH = pillW * 0.44
                let pillRect = CGRect(
                    x: rect.midX - pillW / 2,
                    y: rect.midY - pillH / 2,
                    width: pillW,
                    height: pillH
                )
                let pillPath = Path(roundedRect: pillRect, cornerRadius: pillH / 2, style: .continuous)
                ctx.fill(pillPath, with: .color(Color(white: showBackground ? 0.04 : 0.14)))
                ctx.stroke(
                    pillPath,
                    with: .linearGradient(
                        Gradient(colors: [.white.opacity(0.45), .white.opacity(0.08)]),
                        startPoint: CGPoint(x: pillRect.midX, y: pillRect.minY),
                        endPoint: CGPoint(x: pillRect.midX, y: pillRect.maxY)
                    ),
                    lineWidth: max(0.8, sz.width * 0.018)
                )

                // Luminous S-wave flow ribbon connecting two glowing orbs
                let leftPt = CGPoint(x: pillRect.minX + pillW * 0.24, y: pillRect.midY)
                let rightPt = CGPoint(x: pillRect.maxX - pillW * 0.24, y: pillRect.midY)
                var wave = Path()
                wave.move(to: leftPt)
                wave.addCurve(
                    to: CGPoint(x: pillRect.midX, y: pillRect.midY),
                    control1: CGPoint(x: leftPt.x + pillW * 0.10, y: pillRect.midY - pillH * 0.34),
                    control2: CGPoint(x: pillRect.midX - pillW * 0.08, y: pillRect.midY - pillH * 0.34)
                )
                wave.addCurve(
                    to: rightPt,
                    control1: CGPoint(x: pillRect.midX + pillW * 0.08, y: pillRect.midY + pillH * 0.34),
                    control2: CGPoint(x: rightPt.x - pillW * 0.10, y: pillRect.midY + pillH * 0.34)
                )
                ctx.stroke(
                    wave,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.22, green: 0.74, blue: 0.97),
                            Color(red: 0.51, green: 0.55, blue: 0.97),
                            Color(red: 0.98, green: 0.57, blue: 0.24),
                        ]),
                        startPoint: leftPt,
                        endPoint: rightPt
                    ),
                    style: StrokeStyle(lineWidth: max(1.6, pillH * 0.2), lineCap: .round)
                )

                let orbR = pillH * 0.17
                ctx.fill(
                    Path(ellipseIn: CGRect(x: leftPt.x - orbR, y: leftPt.y - orbR, width: orbR * 2, height: orbR * 2)),
                    with: .color(Color(red: 0.35, green: 0.82, blue: 1.0))
                )
                ctx.fill(
                    Path(ellipseIn: CGRect(x: rightPt.x - orbR, y: rightPt.y - orbR, width: orbR * 2, height: orbR * 2)),
                    with: .color(Color(red: 1.0, green: 0.65, blue: 0.32))
                )
            }
            .frame(width: size, height: size)
        }
    }
}
