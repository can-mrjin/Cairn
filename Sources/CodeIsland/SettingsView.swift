import SwiftUI
import AppKit
import CodeIslandCore

// MARK: - Navigation Model

enum SettingsPage: String, Identifiable, Hashable {
    case general
    case hooks
    case behavior
    case appearance
    case sound
    case mascots
    case shortcuts
    case remote
    case buddy
    case about

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .hooks: return "puzzlepiece.extension.fill"
        case .behavior: return "bell.badge.fill"
        case .appearance: return "textformat.size"
        case .sound: return "speaker.wave.2.fill"
        case .mascots: return "sparkles"
        case .shortcuts: return "keyboard.fill"
        case .remote: return "globe"
        case .buddy: return "dot.radiowaves.left.and.right"
        case .about: return "info.circle.fill"
        }
    }

    var gradientTop: Color {
        switch self {
        case .general: return Color(red: 0.59, green: 0.60, blue: 0.63)
        case .hooks: return Color(red: 0.08, green: 0.74, blue: 0.88)
        case .behavior: return Color(red: 1.00, green: 0.32, blue: 0.28)
        case .appearance: return Color(red: 0.44, green: 0.45, blue: 0.96)
        case .sound: return Color(red: 0.24, green: 0.82, blue: 0.39)
        case .mascots: return Color(red: 0.98, green: 0.24, blue: 0.42)
        case .shortcuts: return Color(red: 0.72, green: 0.35, blue: 0.94)
        case .remote: return Color(red: 0.10, green: 0.70, blue: 0.85)
        case .buddy: return Color(red: 1.00, green: 0.62, blue: 0.14)
        case .about: return Color(red: 0.10, green: 0.54, blue: 0.98)
        }
    }

    var gradientBottom: Color {
        switch self {
        case .general: return Color(red: 0.46, green: 0.47, blue: 0.50)
        case .hooks: return Color(red: 0.00, green: 0.58, blue: 0.76)
        case .behavior: return Color(red: 0.88, green: 0.20, blue: 0.24)
        case .appearance: return Color(red: 0.33, green: 0.34, blue: 0.84)
        case .sound: return Color(red: 0.16, green: 0.70, blue: 0.31)
        case .mascots: return Color(red: 0.84, green: 0.14, blue: 0.32)
        case .shortcuts: return Color(red: 0.58, green: 0.20, blue: 0.84)
        case .remote: return Color(red: 0.04, green: 0.54, blue: 0.74)
        case .buddy: return Color(red: 0.92, green: 0.44, blue: 0.04)
        case .about: return Color(red: 0.00, green: 0.40, blue: 0.88)
        }
    }
}

private struct SidebarGroup: Hashable {
    let titleKey: String?
    let literalTitle: String?
    let pages: [SettingsPage]

    init(titleKey: String? = nil, literalTitle: String? = nil, pages: [SettingsPage]) {
        self.titleKey = titleKey
        self.literalTitle = literalTitle
        self.pages = pages
    }

    func resolvedTitle(_ l10n: L10n) -> String? {
        if let literalTitle { return literalTitle }
        if let titleKey { return l10n[titleKey] }
        return nil
    }
}

private let sidebarGroups: [SidebarGroup] = [
    SidebarGroup(pages: [.general, .hooks, .behavior, .appearance, .sound, .mascots]),
    SidebarGroup(titleKey: "settings_group_advanced", pages: [.shortcuts, .remote, .buddy]),
    SidebarGroup(literalTitle: "FlowIsland", pages: [.about]),
]

// MARK: - Main Settings View

struct SettingsView: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var selectedPage: SettingsPage
    @Environment(\.colorScheme) private var scheme
    var appState: AppState?

    /// `initialPage` opens the window on that page (the offscreen UI gallery
    /// renders every page through it).
    init(appState: AppState? = nil, initialPage: SettingsPage = .general) {
        self.appState = appState
        _selectedPage = State(initialValue: initialPage)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left frosted sidebar (matches modern macOS System Settings)
            VStack(spacing: 0) {
                // Space reserved for native macOS traffic lights
                Spacer().frame(height: 44)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(sidebarGroups.enumerated()), id: \.offset) { idx, group in
                            if let header = group.resolvedTitle(l10n) {
                                Text(header)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary.opacity(0.8))
                                    .padding(.leading, 18)
                                    .padding(.top, idx == 0 ? 4 : 14)
                                    .padding(.bottom, 5)
                            }
                            ForEach(group.pages) { page in
                                SidebarNavRow(
                                    page: page,
                                    title: l10n[page.rawValue],
                                    isSelected: selectedPage == page
                                ) {
                                    selectedPage = page
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 16)
                }
            }
            .frame(width: 198)
            .frame(maxHeight: .infinity)
            .background(FlowSidebarBackdrop())

            // Subtle vertical hairline separator
            Rectangle()
                .fill(FlowSettingsPalette.rowDivider(scheme))
                .frame(width: 0.5)
                .ignoresSafeArea()

            // Right detail surface
            Group {
                switch selectedPage {
                case .general: GeneralPage()
                case .hooks: HooksPage(appState: appState)
                case .behavior: BehaviorPage(appState: appState)
                case .appearance: AppearancePage()
                case .sound: SoundPage()
                case .mascots: MascotsPage()
                case .shortcuts: ShortcutsPage()
                case .remote: RemoteHostsPage()
                case .buddy: BuddyPage()
                case .about: AboutPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct SidebarNavRow: View {
    let page: SettingsPage
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                SettingsIconBadge(
                    systemName: page.icon,
                    topColor: page.gradientTop,
                    bottomColor: page.gradientBottom,
                    size: 22
                )
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return FlowSettingsPalette.sidebarSelected(scheme)
        }
        if isHovered {
            return FlowSettingsPalette.sidebarHovered(scheme)
        }
        return .clear
    }
}
