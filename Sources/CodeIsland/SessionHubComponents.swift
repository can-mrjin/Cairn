import SwiftUI
import CodeIslandCore

// MARK: - Localization Helpers

private func hubLocalized(_ l10n: L10n, _ key: String, fallback: String) -> String {
    let value = l10n[key]
    return value == key ? fallback : value
}

private func hubFormatSingleArg(_ template: String, arg: String) -> String {
    if template.contains("%@") {
        return String(format: template, arg)
    }
    return "\(template) · \(arg)"
}

private func hubFormatCount(_ template: String, count: Int) -> String {
    if template.contains("%d") || template.contains("%lld") || template.contains("%ld") {
        return String(format: template, count)
    }
    return "\(template) (\(count))"
}

// MARK: - Palette Constants (Dark Notch Aesthetic)

private enum SessionHubPalette {
    static let unreadAccent = Color(red: 0.28, green: 0.80, blue: 1.0)
    static let unreadGlow = Color(red: 0.22, green: 0.74, blue: 1.0)
    static let activeGreen = Color(red: 0.36, green: 0.94, blue: 0.56)
    static let pinAmber = Color(red: 1.0, green: 0.76, blue: 0.28)
    static let bypassOrange = Color(red: 1.0, green: 0.62, blue: 0.24)
    static let compactionPurple = Color(red: 0.74, green: 0.54, blue: 1.0)
    static let allowGreen = Color(red: 0.34, green: 0.88, blue: 0.52)
    static let denyRed = Color(red: 0.98, green: 0.42, blue: 0.42)
}

// MARK: - 1. Collapsed Unread Badge

/// Compact glowing unread counter pill sized to sit cleanly inside the
/// collapsed notch right wing (~18-28pt wide, 16pt tall).
struct CollapsedUnreadBadgeView: View {
    let count: Int

    init(count: Int) {
        self.count = count
    }

    private var formattedCount: String {
        count > 99 ? "99+" : "\(count)"
    }

    var body: some View {
        if count > 0 {
            HStack(spacing: 3) {
                Circle()
                    .fill(SessionHubPalette.unreadAccent)
                    .frame(width: 5, height: 5)
                    .shadow(color: SessionHubPalette.unreadGlow.opacity(0.85), radius: 2.5)

                Text(formattedCount)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(1)
            }
            .padding(.horizontal, 4.5)
            .frame(minWidth: 18, maxHeight: 16)
            .frame(height: 16)
            .background(
                Capsule(style: .continuous)
                    .fill(SessionHubPalette.unreadGlow.opacity(0.20))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(SessionHubPalette.unreadAccent.opacity(0.50), lineWidth: 0.6)
            )
            .fixedSize()
            .transition(.scale(scale: 0.85).combined(with: .opacity))
            .accessibilityLabel(Text("\(count) unread"))
        }
    }
}

// MARK: - 2. Session Hub Toolbar

/// Compact single-row filter, unread clear, archive toggle, and inline search
/// toolbar for navigating today's sessions inside the expanded notch panel.
struct SessionHubToolbarView: View {
    @Binding var filter: SessionHubFilter
    @Binding var searchQuery: String
    let totalCount: Int
    let unreadCount: Int
    let activeCount: Int
    let pinnedCount: Int
    let archivedCount: Int
    @Binding var showArchived: Bool
    let onMarkAllRead: () -> Void
    let l10n: L10n

    @State private var searchExpanded = false
    @FocusState private var searchFocused: Bool

    init(
        filter: Binding<SessionHubFilter>,
        searchQuery: Binding<String>,
        totalCount: Int,
        unreadCount: Int,
        activeCount: Int,
        pinnedCount: Int,
        archivedCount: Int,
        showArchived: Binding<Bool>,
        onMarkAllRead: @escaping () -> Void,
        l10n: L10n
    ) {
        self._filter = filter
        self._searchQuery = searchQuery
        self.totalCount = totalCount
        self.unreadCount = unreadCount
        self.activeCount = activeCount
        self.pinnedCount = pinnedCount
        self.archivedCount = archivedCount
        self._showArchived = showArchived
        self.onMarkAllRead = onMarkAllRead
        self.l10n = l10n
    }

    private var isSearchVisible: Bool {
        searchExpanded || !searchQuery.isEmpty
    }

    var body: some View {
        HStack(spacing: 5) {
            // Left: filter pills
            HStack(spacing: 4) {
                ForEach(SessionHubFilter.allCases) { item in
                    HubFilterPillButton(
                        title: filterTitle(for: item),
                        count: filterCount(for: item),
                        dotColor: filterDotColor(for: item),
                        iconName: item == .pinned ? "pin.fill" : nil,
                        isSelected: filter == item
                    ) {
                        withAnimation(.easeOut(duration: 0.14)) {
                            filter = item
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            // Right: utility actions + inline search
            HStack(spacing: 4) {
                if unreadCount > 0 {
                    HubActionPillButton(
                        iconName: "checkmark.circle",
                        title: isSearchVisible ? nil : hubLocalized(l10n, "hub_mark_all_read", fallback: "Mark All Read"),
                        tint: SessionHubPalette.unreadAccent,
                        isActive: false
                    ) {
                        onMarkAllRead()
                    }
                    .help(hubLocalized(l10n, "hub_mark_all_read", fallback: "Mark All Read"))
                }

                if archivedCount > 0 {
                    HubActionPillButton(
                        iconName: "archivebox",
                        title: "\(archivedCount)",
                        tint: .white.opacity(0.85),
                        isActive: showArchived
                    ) {
                        withAnimation(.easeOut(duration: 0.14)) {
                            showArchived.toggle()
                        }
                    }
                    .help(hubLocalized(l10n, "hub_show_archived", fallback: "Show Archived"))
                }

                searchControl
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var searchControl: some View {
        if isSearchVisible {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))

                TextField(
                    hubLocalized(l10n, "hub_search_placeholder", fallback: "Filter sessions..."),
                    text: $searchQuery
                )
                .textFieldStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.92))
                .focused($searchFocused)
                .frame(width: 96)

                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        if searchQuery.isEmpty {
                            searchExpanded = false
                            searchFocused = false
                        } else {
                            searchQuery = ""
                        }
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 7)
            .frame(height: 21)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.09))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(searchFocused ? 0.30 : 0.14), lineWidth: 0.6)
            )
            .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .trailing)))
        } else {
            HubActionPillButton(
                iconName: "magnifyingglass",
                title: nil,
                tint: .white.opacity(0.75),
                isActive: false
            ) {
                withAnimation(.easeOut(duration: 0.15)) {
                    searchExpanded = true
                }
                DispatchQueue.main.async {
                    searchFocused = true
                }
            }
            .help(hubLocalized(l10n, "hub_search_placeholder", fallback: "Filter sessions..."))
        }
    }

    private func filterTitle(for item: SessionHubFilter) -> String {
        switch item {
        case .all:
            return hubLocalized(l10n, "hub_filter_all", fallback: "All")
        case .unread:
            return hubLocalized(l10n, "hub_filter_unread", fallback: "Unread")
        case .active:
            return hubLocalized(l10n, "hub_filter_active", fallback: "Active")
        case .pinned:
            return hubLocalized(l10n, "hub_filter_pinned", fallback: "Pinned")
        }
    }

    private func filterCount(for item: SessionHubFilter) -> Int {
        switch item {
        case .all: return totalCount
        case .unread: return unreadCount
        case .active: return activeCount
        case .pinned: return pinnedCount
        }
    }

    private func filterDotColor(for item: SessionHubFilter) -> Color? {
        switch item {
        case .unread:
            return unreadCount > 0 ? SessionHubPalette.unreadAccent : nil
        case .active:
            return activeCount > 0 ? SessionHubPalette.activeGreen : nil
        case .all, .pinned:
            return nil
        }
    }
}

private struct HubFilterPillButton: View {
    let title: String
    let count: Int
    let dotColor: Color?
    let iconName: String?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3.5) {
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 5, height: 5)
                        .shadow(color: dotColor.opacity(0.65), radius: 2)
                } else if let iconName, count > 0 || isSelected {
                    Image(systemName: iconName)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(isSelected ? SessionHubPalette.pinAmber : SessionHubPalette.pinAmber.opacity(0.75))
                }

                Text(title)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white.opacity(0.96) : .white.opacity(isHovered ? 0.84 : 0.62))
                    .lineLimit(1)

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? .white.opacity(0.92) : .white.opacity(0.55))
                        .padding(.horizontal, 3.5)
                        .padding(.vertical, 0.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(isSelected ? 0.16 : 0.08))
                        )
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 21)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.16 : (isHovered ? 0.09 : 0.045)))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(isSelected ? 0.24 : (isHovered ? 0.12 : 0.06)),
                        lineWidth: 0.6
                    )
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

private struct HubActionPillButton: View {
    let iconName: String
    let title: String?
    let tint: Color
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: iconName)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(isActive ? .white : tint.opacity(isHovered ? 1.0 : 0.85))
                if let title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(isActive ? .white : tint.opacity(isHovered ? 1.0 : 0.85))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, title == nil ? 6 : 7)
            .frame(height: 21)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isActive
                            ? Color.white.opacity(0.18)
                            : Color.white.opacity(isHovered ? 0.10 : 0.05)
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isActive
                            ? Color.white.opacity(0.28)
                            : Color.white.opacity(isHovered ? 0.14 : 0.07),
                        lineWidth: 0.6
                    )
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - 3. Session Card Hub Badges

/// Compact inline status badges rendered inside a session card header:
/// unread indicator, pin mark, bypass badge, context compaction capsule,
/// and ⌘1..⌘9 keyboard shortcut hint.
struct SessionCardHubBadgesView: View {
    let isUnread: Bool
    let isPinned: Bool
    let bypassMode: SessionBypassMode
    let compactionText: String?
    let shortcutIndex: Int?
    let l10n: L10n

    init(
        isUnread: Bool,
        isPinned: Bool,
        bypassMode: SessionBypassMode,
        compactionText: String?,
        shortcutIndex: Int?,
        l10n: L10n = .shared
    ) {
        self.isUnread = isUnread
        self.isPinned = isPinned
        self.bypassMode = bypassMode
        self.compactionText = compactionText
        self.shortcutIndex = shortcutIndex
        self.l10n = l10n
    }

    private var hasAnyBadge: Bool {
        isUnread
            || isPinned
            || bypassMode != .off
            || (compactionText != nil && !(compactionText?.isEmpty ?? true))
            || validShortcutIndex != nil
    }

    private var validShortcutIndex: Int? {
        guard let idx = shortcutIndex, (1...9).contains(idx) else { return nil }
        return idx
    }

    var body: some View {
        if hasAnyBadge {
            HStack(spacing: 4) {
                if isUnread {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(SessionHubPalette.unreadAccent)
                            .frame(width: 5, height: 5)
                            .shadow(color: SessionHubPalette.unreadGlow.opacity(0.85), radius: 2.5)
                        Text(hubLocalized(l10n, "hub_badge_unread", fallback: "NEW"))
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundStyle(SessionHubPalette.unreadAccent)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(
                        Capsule(style: .continuous)
                            .fill(SessionHubPalette.unreadGlow.opacity(0.15))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(SessionHubPalette.unreadAccent.opacity(0.38), lineWidth: 0.5)
                    )
                }

                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(SessionHubPalette.pinAmber)
                        .rotationEffect(.degrees(-25))
                        .frame(width: 15, height: 15)
                        .background(
                            Circle()
                                .fill(SessionHubPalette.pinAmber.opacity(0.14))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(SessionHubPalette.pinAmber.opacity(0.32), lineWidth: 0.5)
                        )
                }

                if bypassMode != .off {
                    HStack(spacing: 2.5) {
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text(hubLocalized(l10n, "hub_badge_bypass", fallback: "BYPASS"))
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                    }
                    .foregroundStyle(SessionHubPalette.bypassOrange)
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(
                        Capsule(style: .continuous)
                            .fill(SessionHubPalette.bypassOrange.opacity(bypassMode == .session ? 0.22 : 0.15))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                SessionHubPalette.bypassOrange.opacity(bypassMode == .session ? 0.55 : 0.36),
                                lineWidth: 0.5
                            )
                    )
                }

                if let compactionText, !compactionText.isEmpty {
                    let template = hubLocalized(l10n, "hub_compacting_elapsed", fallback: "Compacting · %@")
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.2.circlepath")
                            .font(.system(size: 8, weight: .semibold))
                        Text(hubFormatSingleArg(template, arg: compactionText))
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .foregroundStyle(SessionHubPalette.compactionPurple)
                    .padding(.horizontal, 5.5)
                    .frame(height: 15)
                    .background(
                        Capsule(style: .continuous)
                            .fill(SessionHubPalette.compactionPurple.opacity(0.16))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(SessionHubPalette.compactionPurple.opacity(0.38), lineWidth: 0.5)
                    )
                }

                if let idx = validShortcutIndex {
                    Text("⌘\(idx)")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.48))
                        .padding(.horizontal, 4)
                        .frame(height: 15)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                }
            }
            .fixedSize()
        }
    }
}

// MARK: - 4. Batch Approval & Turn Bypass Banner

/// Horizontal action strip shown above or beside approvals for one-click
/// batch Allow All / Deny All (when `pendingCount >= 2`) and turn/session
/// Bypass toggling.
struct BatchApprovalBannerView: View {
    let pendingCount: Int
    let currentSessionBypassMode: SessionBypassMode
    let onAllowAll: () -> Void
    let onDenyAll: () -> Void
    let onToggleTurnBypass: () -> Void
    let l10n: L10n

    init(
        pendingCount: Int,
        currentSessionBypassMode: SessionBypassMode,
        onAllowAll: @escaping () -> Void,
        onDenyAll: @escaping () -> Void,
        onToggleTurnBypass: @escaping () -> Void,
        l10n: L10n
    ) {
        self.pendingCount = pendingCount
        self.currentSessionBypassMode = currentSessionBypassMode
        self.onAllowAll = onAllowAll
        self.onDenyAll = onDenyAll
        self.onToggleTurnBypass = onToggleTurnBypass
        self.l10n = l10n
    }

    private var bypassActive: Bool {
        currentSessionBypassMode != .off
    }

    var body: some View {
        HStack(spacing: 6) {
            if pendingCount >= 2 {
                BatchBannerButton(
                    iconName: "checkmark.circle.fill",
                    title: hubFormatCount(
                        hubLocalized(l10n, "hub_allow_all", fallback: "Allow All"),
                        count: pendingCount
                    ),
                    tint: SessionHubPalette.allowGreen,
                    filled: true,
                    action: onAllowAll
                )

                BatchBannerButton(
                    iconName: "xmark.circle.fill",
                    title: hubLocalized(l10n, "hub_deny_all", fallback: "Deny All"),
                    tint: SessionHubPalette.denyRed,
                    filled: false,
                    action: onDenyAll
                )
            }

            Spacer(minLength: 4)

            BatchBannerButton(
                iconName: bypassActive ? "bolt.shield.fill" : "bolt.shield",
                title: bypassActive
                    ? "\(hubLocalized(l10n, "hub_badge_bypass", fallback: "BYPASS")) ON"
                    : hubLocalized(l10n, "hub_bypass_turn", fallback: "Auto-approve turn"),
                tint: bypassActive ? SessionHubPalette.bypassOrange : .white.opacity(0.82),
                filled: bypassActive,
                action: onToggleTurnBypass
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    bypassActive ? SessionHubPalette.bypassOrange.opacity(0.32) : Color.white.opacity(0.09),
                    lineWidth: 0.6
                )
        )
    }
}

private struct BatchBannerButton: View {
    let iconName: String
    let title: String
    let tint: Color
    let filled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .foregroundStyle(tint.opacity(isHovered ? 1.0 : 0.92))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(filled ? (isHovered ? 0.28 : 0.20) : (isHovered ? 0.16 : 0.10)))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(isHovered ? 0.55 : 0.34), lineWidth: 0.6)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - 5. Session Card Hub Context Menu

/// Native macOS context menu items for a session card, intended to be placed
/// inside `.contextMenu { SessionCardHubContextMenu(...) }`.
struct SessionCardHubContextMenu: View {
    let isUnread: Bool
    let isPinned: Bool
    let isArchived: Bool
    let bypassMode: SessionBypassMode
    let hasCwd: Bool
    let hasPrompt: Bool
    let onToggleRead: () -> Void
    let onTogglePin: () -> Void
    let onToggleArchive: () -> Void
    let onToggleBypass: () -> Void
    let onSilenceDirectory: () -> Void
    let onSilencePromptPrefix: () -> Void
    let l10n: L10n

    init(
        isUnread: Bool,
        isPinned: Bool,
        isArchived: Bool,
        bypassMode: SessionBypassMode,
        hasCwd: Bool,
        hasPrompt: Bool,
        onToggleRead: @escaping () -> Void,
        onTogglePin: @escaping () -> Void,
        onToggleArchive: @escaping () -> Void,
        onToggleBypass: @escaping () -> Void,
        onSilenceDirectory: @escaping () -> Void,
        onSilencePromptPrefix: @escaping () -> Void,
        l10n: L10n
    ) {
        self.isUnread = isUnread
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.bypassMode = bypassMode
        self.hasCwd = hasCwd
        self.hasPrompt = hasPrompt
        self.onToggleRead = onToggleRead
        self.onTogglePin = onTogglePin
        self.onToggleArchive = onToggleArchive
        self.onToggleBypass = onToggleBypass
        self.onSilenceDirectory = onSilenceDirectory
        self.onSilencePromptPrefix = onSilencePromptPrefix
        self.l10n = l10n
    }

    var body: some View {
        Button(action: onToggleRead) {
            Label(
                isUnread
                    ? hubLocalized(l10n, "hub_menu_mark_read", fallback: "Mark as Read")
                    : hubLocalized(l10n, "hub_menu_mark_unread", fallback: "Mark as Unread"),
                systemImage: isUnread ? "envelope.open" : "envelope.badge"
            )
        }

        Button(action: onTogglePin) {
            Label(
                isPinned
                    ? hubLocalized(l10n, "hub_menu_unpin", fallback: "Unpin Session")
                    : hubLocalized(l10n, "hub_menu_pin", fallback: "Pin Session"),
                systemImage: isPinned ? "pin.slash" : "pin"
            )
        }

        Button(action: onToggleArchive) {
            Label(
                isArchived
                    ? hubLocalized(l10n, "hub_menu_unarchive", fallback: "Unarchive Session")
                    : hubLocalized(l10n, "hub_menu_archive", fallback: "Archive Session"),
                systemImage: isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }

        Divider()

        Button(action: onToggleBypass) {
            Label(
                bypassMode == .off
                    ? hubLocalized(l10n, "hub_menu_bypass_on", fallback: "Auto-approve Session (Bypass)")
                    : hubLocalized(l10n, "hub_menu_bypass_off", fallback: "Disable Session Bypass"),
                systemImage: bypassMode == .off ? "bolt.shield" : "bolt.shield.fill"
            )
        }

        if hasCwd || hasPrompt {
            Divider()

            if hasCwd {
                Button(action: onSilenceDirectory) {
                    Label(
                        hubLocalized(l10n, "hub_menu_silence_dir", fallback: "Silence This Directory"),
                        systemImage: "folder.badge.minus"
                    )
                }
            }

            if hasPrompt {
                Button(action: onSilencePromptPrefix) {
                    Label(
                        hubLocalized(l10n, "hub_menu_silence_prompt", fallback: "Silence This Prompt Prefix"),
                        systemImage: "text.badge.minus"
                    )
                }
            }
        }
    }
}
