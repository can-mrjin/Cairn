import SwiftUI
import AppKit
import CodeIslandCore

// MARK: - Appearance Page

/// Card text sizes offered in Settings. The panel keeps a fixed width
/// (≤ 620pt) and each card header stays on one row, so the range stops at
/// 16pt rather than growing without bound.
enum ContentFontSize {
    static let choices = Array(10...16)
}

struct AppearancePage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.maxVisibleSessions) private var maxVisibleSessions = SettingsDefaults.maxVisibleSessions
    @AppStorage(SettingsKey.sessionListDensity) private var sessionListDensityRaw = SettingsDefaults.sessionListDensity
    @AppStorage(SettingsKey.contentFontSize) private var contentFontSize = SettingsDefaults.contentFontSize
    @AppStorage(SettingsKey.aiMessageLines) private var aiMessageLines = SettingsDefaults.aiMessageLines
    @AppStorage(SettingsKey.showAgentDetails) private var showAgentDetails = SettingsDefaults.showAgentDetails
    @AppStorage(SettingsKey.showToolStatus) private var showToolStatus = SettingsDefaults.showToolStatus
    @AppStorage(SettingsKey.showGitBranch) private var showGitBranch = SettingsDefaults.showGitBranch
    @AppStorage(SettingsKey.showTaskProgress) private var showTaskProgress = SettingsDefaults.showTaskProgress
    @AppStorage(SettingsKey.taskProgressStyle) private var taskProgressStyleRaw = SettingsDefaults.taskProgressStyle
    @AppStorage(SettingsKey.showSessionRecap) private var showSessionRecap = SettingsDefaults.showSessionRecap
    @AppStorage(SettingsKey.showModelLabel) private var showModelLabel = SettingsDefaults.showModelLabel
    @AppStorage(SettingsKey.showProjectName) private var showProjectName = SettingsDefaults.showProjectName
    @AppStorage(SettingsKey.showUsageStats) private var showUsageStats = SettingsDefaults.showUsageStats
    @AppStorage(SettingsKey.showClaudeQuota) private var showClaudeQuota = SettingsDefaults.showClaudeQuota
    @AppStorage(SettingsKey.claudeQuotaChip) private var claudeQuotaChip = SettingsDefaults.claudeQuotaChip
    @AppStorage(SettingsKey.collapsedWidthScale) private var collapsedWidthScale = SettingsDefaults.collapsedWidthScale
    @AppStorage(SettingsKey.expandedPanelWidth) private var expandedPanelWidth = SettingsDefaults.expandedPanelWidth
    @AppStorage(SettingsKey.notchHeightMode) private var notchHeightModeRaw = SettingsDefaults.notchHeightMode
    @AppStorage(SettingsKey.customNotchHeight) private var customNotchHeight = SettingsDefaults.customNotchHeight
    @AppStorage(SettingsKey.notchAnimationSpeed) private var notchAnimationSpeed = SettingsDefaults.notchAnimationSpeed
    @AppStorage(SettingsKey.panelMaterialMode) private var panelMaterialModeRaw = SettingsDefaults.panelMaterialMode
    @AppStorage(SettingsKey.panelAccentTheme) private var panelAccentThemeRaw = SettingsDefaults.panelAccentTheme
    @AppStorage(SettingsKey.displayChoice) private var displayChoice = SettingsDefaults.displayChoice
    @State private var activeHasNotch: Bool = false

    private func refreshActiveDisplayNotch() {
        activeHasNotch = ScreenDetector.screenHasNotch(
            ScreenDetector.screen(forDisplayChoice: displayChoice)
        )
    }

    private var notchHeightMode: Binding<NotchHeightMode> {
        Binding(
            get: { NotchHeightMode(rawValue: notchHeightModeRaw) ?? .matchNotch },
            set: { notchHeightModeRaw = $0.rawValue }
        )
    }

    private var sessionListDensityBinding: Binding<SessionListDensity> {
        Binding(
            get: { SessionListDensity(storedValue: sessionListDensityRaw) },
            set: { sessionListDensityRaw = $0.rawValue }
        )
    }

    private var panelMaterialModeBinding: Binding<PanelMaterialMode> {
        Binding(
            get: { PanelMaterialMode(storedValue: panelMaterialModeRaw) },
            set: { panelMaterialModeRaw = $0.rawValue }
        )
    }

    private var panelAccentTheme: PanelAccentTheme {
        PanelAccentTheme(storedValue: panelAccentThemeRaw)
    }

    private var taskProgressStyleBinding: Binding<TaskProgressStyle> {
        Binding(
            get: { TaskProgressStyle(storedValue: taskProgressStyleRaw) },
            set: { taskProgressStyleRaw = $0.rawValue }
        )
    }

    private var notchAnimationSpeedBinding: Binding<Double> {
        Binding(
            get: { NotchAnimationSpeed.clamped(notchAnimationSpeed) },
            set: { notchAnimationSpeed = NotchAnimationSpeed.clamped($0) }
        )
    }

    var body: some View {
        FlowSettingsPageShell(page: .appearance, title: l10n["appearance"]) {
            FlowSettingsSection(title: l10n["preview"]) {
                FlowSettingsRow(verticalPadding: 12) {
                    AppearancePreview(
                        fontSize: contentFontSize,
                        lineLimit: aiMessageLines,
                        showAgentDetails: showAgentDetails,
                        showTaskProgress: showTaskProgress,
                        taskProgressStyle: taskProgressStyleBinding.wrappedValue,
                        showToolStatus: showToolStatus,
                        showModelLabel: showModelLabel,
                        showGitBranch: showGitBranch,
                        showProjectName: showProjectName,
                        density: sessionListDensityBinding.wrappedValue,
                        materialMode: panelMaterialModeBinding.wrappedValue,
                        accentTheme: panelAccentTheme
                    )
                }
            }

            FlowSettingsSection(title: l10n["panel"]) {
                FlowSettingsPickerRow(
                    title: l10n["panel_material_mode"],
                    subtitle: l10n["panel_material_mode_desc"],
                    selection: panelMaterialModeBinding
                ) {
                    ForEach(PanelMaterialMode.allCases, id: \.self) { mode in
                        Text(l10n[mode.titleKey]).tag(mode)
                    }
                }

                FlowSettingsDivider()
                FlowSettingsRow(verticalPadding: 11) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l10n["panel_accent_theme"])
                                .font(.system(size: 13.5, weight: .regular))
                            Text(l10n["panel_accent_theme_desc"])
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        HStack(spacing: 8) {
                            ForEach(PanelAccentTheme.allCases) { theme in
                                let selected = panelAccentTheme == theme
                                Button {
                                    panelAccentThemeRaw = theme.rawValue
                                } label: {
                                    Circle()
                                        .fill(theme.color)
                                        .frame(width: 18, height: 18)
                                        .overlay {
                                            if selected {
                                                Circle()
                                                    .strokeBorder(Color.primary, lineWidth: 2)
                                                    .padding(-3)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .help(l10n[theme.titleKey])
                                .accessibilityLabel(l10n[theme.titleKey])
                            }
                        }
                    }
                }

                FlowSettingsDivider()
                FlowSettingsSliderRow(
                    title: l10n["notch_animation_speed"],
                    subtitle: l10n["notch_animation_speed_desc"],
                    valueText: String(format: "%.1f×", notchAnimationSpeedBinding.wrappedValue),
                    value: notchAnimationSpeedBinding,
                    range: NotchAnimationSpeed.minimum...NotchAnimationSpeed.maximum,
                    step: NotchAnimationSpeed.step,
                    tickCount: 9
                )

                FlowSettingsDivider()
                FlowSettingsPickerRow(
                    title: l10n["max_visible_sessions"],
                    subtitle: l10n[sessionListDensityBinding.wrappedValue == .compact
                        ? "max_visible_sessions_desc_compact" : "max_visible_sessions_desc"],
                    selection: $maxVisibleSessions
                ) {
                    Text("3").tag(3)
                    Text("5").tag(5)
                    Text("8").tag(8)
                    Text("10").tag(10)
                    Text(l10n["unlimited"]).tag(99)
                }

                FlowSettingsDivider()
                FlowSettingsPickerRow(
                    title: l10n["session_list_density"],
                    subtitle: l10n["session_list_density_desc"],
                    selection: sessionListDensityBinding
                ) {
                    ForEach(SessionListDensity.allCases, id: \.self) { density in
                        Text(l10n[density.titleKey]).tag(density)
                    }
                }

                FlowSettingsDivider()
                FlowSettingsSliderRow(
                    title: l10n["expanded_panel_width"],
                    subtitle: l10n["expanded_panel_width_desc"],
                    valueText: "\(min(780, max(480, expandedPanelWidth)))pt",
                    value: Binding(
                        get: { Double(min(780, max(480, expandedPanelWidth))) },
                        set: { expandedPanelWidth = Int(($0 / 20).rounded() * 20) }
                    ),
                    range: 480...780,
                    step: 20,
                    tickCount: 8
                )

                FlowSettingsDivider()
                let collapsedMin = NotchWidthScale.sliderMin(hasNotch: activeHasNotch)
                let effectiveCollapsedScale = max(collapsedMin, min(NotchWidthScale.max, collapsedWidthScale))
                FlowSettingsSliderRow(
                    title: l10n["collapsed_width_scale"],
                    subtitle: l10n["collapsed_width_scale_desc"],
                    valueText: "\(effectiveCollapsedScale)%",
                    value: Binding(
                        get: { Double(effectiveCollapsedScale) },
                        set: { collapsedWidthScale = max(collapsedMin, min(NotchWidthScale.max, Int($0.rounded()))) }
                    ),
                    range: Double(collapsedMin)...Double(NotchWidthScale.max),
                    step: Double(NotchWidthScale.step),
                    tickCount: activeHasNotch ? 6 : 9
                )

                FlowSettingsDivider()
                FlowSettingsPickerRow(
                    title: l10n["notch_height_mode"],
                    subtitle: l10n["notch_height_mode_desc"],
                    selection: notchHeightMode
                ) {
                    Text(l10n["notch_height_match_notch"]).tag(NotchHeightMode.matchNotch)
                    Text(l10n["notch_height_match_menubar"]).tag(NotchHeightMode.matchMenuBar)
                    Text(l10n["notch_height_custom"]).tag(NotchHeightMode.custom)
                }

                if notchHeightMode.wrappedValue == .custom {
                    FlowSettingsDivider()
                    FlowSettingsSliderRow(
                        title: l10n["custom_notch_height"],
                        valueText: "\(Int(customNotchHeight.rounded()))pt",
                        value: $customNotchHeight,
                        range: 15...60,
                        step: 1,
                        tickCount: 10
                    )
                }
            }

            FlowSettingsSection(title: l10n["content"]) {
                FlowSettingsPickerRow(title: l10n["content_font_size"], selection: $contentFontSize) {
                    ForEach(ContentFontSize.choices, id: \.self) { size in
                        Text(size == SettingsDefaults.contentFontSize ? l10n["11pt_default"] : "\(size)pt")
                            .tag(size)
                    }
                }

                FlowSettingsDivider()
                FlowSettingsPickerRow(
                    title: l10n["ai_reply_lines"],
                    subtitle: l10n["ai_reply_lines_desc"],
                    selection: $aiMessageLines
                ) {
                    Text(l10n["1_line_default"]).tag(1)
                    Text(l10n["2_lines"]).tag(2)
                    Text(l10n["3_lines"]).tag(3)
                    Text(l10n["5_lines"]).tag(5)
                    Text(l10n["unlimited"]).tag(0)
                }

                FlowSettingsDivider()
                FlowSettingsToggleRow(title: l10n["show_agent_details"], isOn: $showAgentDetails)
                FlowSettingsDivider()
                FlowSettingsToggleRow(title: l10n["show_tool_status"], isOn: $showToolStatus)
                FlowSettingsDivider()
                FlowSettingsToggleRow(
                    title: l10n["show_project_name"],
                    subtitle: l10n["show_project_name_desc"],
                    isOn: $showProjectName
                )
                FlowSettingsDivider()
                FlowSettingsToggleRow(
                    title: l10n["show_git_branch"],
                    subtitle: l10n["show_git_branch_desc"],
                    isOn: $showGitBranch
                )
                FlowSettingsDivider()
                FlowSettingsToggleRow(
                    title: l10n["show_task_progress"],
                    subtitle: l10n["show_task_progress_desc"],
                    isOn: $showTaskProgress
                )
                FlowSettingsDivider()
                FlowSettingsPickerRow(
                    title: l10n["task_progress_style"],
                    selection: taskProgressStyleBinding,
                    disabled: !showTaskProgress
                ) {
                    ForEach(TaskProgressStyle.allCases, id: \.self) { style in
                        Text(l10n[style.titleKey]).tag(style)
                    }
                }
                FlowSettingsDivider()
                FlowSettingsToggleRow(
                    title: l10n["show_session_recap"],
                    subtitle: l10n["show_session_recap_desc"],
                    isOn: $showSessionRecap
                )
                FlowSettingsDivider()
                FlowSettingsToggleRow(
                    title: l10n["show_model_label"],
                    subtitle: l10n["show_model_label_desc"],
                    isOn: $showModelLabel
                )
                FlowSettingsDivider()
                FlowSettingsToggleRow(
                    title: l10n["show_usage_stats"],
                    subtitle: l10n["show_usage_stats_desc"],
                    isOn: $showUsageStats
                )
                FlowSettingsDivider()
                FlowSettingsToggleRow(
                    title: l10n["show_claude_quota"],
                    subtitle: l10n["show_claude_quota_desc"],
                    isOn: $showClaudeQuota
                )
                FlowSettingsDivider()
                FlowSettingsPickerRow(
                    title: l10n["claude_quota_chip"],
                    selection: $claudeQuotaChip,
                    disabled: !showClaudeQuota
                ) {
                    Text(l10n["quota_chip_off"]).tag(ClaudeQuotaChipMode.off.rawValue)
                    Text(l10n["quota_chip_auto"]).tag(ClaudeQuotaChipMode.auto.rawValue)
                    Text(l10n["quota_chip_session"]).tag(ClaudeQuotaChipMode.session.rawValue)
                    Text(l10n["quota_chip_weekly"]).tag(ClaudeQuotaChipMode.weeklyAll.rawValue)
                    Text(l10n["quota_chip_weekly_model"]).tag(ClaudeQuotaChipMode.weeklyScoped.rawValue)
                }
            }
        }
        .onAppear {
            refreshActiveDisplayNotch()
        }
        .onChange(of: displayChoice) { _, _ in
            refreshActiveDisplayNotch()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            refreshActiveDisplayNotch()
        }
    }
}

/// Real-time Vibe Island-style preview synchronized with all Appearance settings.
private struct AppearancePreview: View {
    let fontSize: Int
    let lineLimit: Int
    let showAgentDetails: Bool
    let showTaskProgress: Bool
    var taskProgressStyle: TaskProgressStyle = .compact
    let showToolStatus: Bool
    let showModelLabel: Bool
    let showGitBranch: Bool
    let showProjectName: Bool
    var density: SessionListDensity = .comfortable
    var materialMode: PanelMaterialMode = .pureBlack
    var accentTheme: PanelAccentTheme = .emerald

    private var fs: CGFloat { CGFloat(fontSize) }
    private var isChinese: Bool { L10n.shared.effectiveLanguage.hasPrefix("zh") }
    private var accent: Color { accentTheme.color }

    private static let sampleReply = """
        Found the issue in `auth.ts`:
        - token refresh was **skipping the expiry check**
        - stale sessions were never invalidated
        """

    var body: some View {
        Group {
            switch density {
            case .comfortable: comfortableCard
            case .compact: compactRow
            case .minimal: minimalRow
            }
        }
        .background(
            ZStack {
                if materialMode == .vibrancy {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black.opacity(0.68))
                        )
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(materialMode == .vibrancy ? 0.14 : 0.08), lineWidth: 0.75)
            )
        )
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.18), value: fontSize)
        .animation(.easeInOut(duration: 0.18), value: lineLimit)
        .animation(.easeInOut(duration: 0.18), value: showAgentDetails)
        .animation(.easeInOut(duration: 0.18), value: showTaskProgress)
        .animation(.easeInOut(duration: 0.18), value: taskProgressStyle)
        .animation(.easeInOut(duration: 0.18), value: showToolStatus)
        .animation(.easeInOut(duration: 0.18), value: showModelLabel)
        .animation(.easeInOut(duration: 0.18), value: showGitBranch)
        .animation(.easeInOut(duration: 0.18), value: showProjectName)
        .animation(.easeInOut(duration: 0.18), value: density)
        .animation(.easeInOut(duration: 0.18), value: materialMode)
        .animation(.easeInOut(duration: 0.18), value: accentTheme)
    }

    private var comfortableCard: some View {
        HStack(alignment: .top, spacing: 11) {
            MascotView(source: "claude", status: .running, size: 30, animate: false)
                .frame(width: 34)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                // Header: crisp status dot + SF Pro title + calm metadata pills
                HStack(alignment: .center, spacing: 6) {
                    Circle()
                        .fill(accent)
                        .frame(width: 7, height: 7)
                        .shadow(color: accent.opacity(0.6), radius: 2.5)

                    HStack(spacing: 4) {
                        if showProjectName {
                            Text("Cairn")
                                .font(.system(size: fs + 2.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                        }
                        if showGitBranch {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: max(8.5, fs - 1), weight: .medium))
                                Text("main")
                                    .font(.system(size: fs, weight: .regular))
                            }
                            .foregroundStyle(.white.opacity(0.55))
                        }
                        Text(showProjectName ? "· Refactor auth flow" : "Refactor auth flow")
                            .font(.system(size: fs + 2, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 4) {
                        if !showAgentDetails {
                            previewPill("+2", color: .white.opacity(0.60))
                        }
                        if showModelLabel {
                            previewPill("Opus 5", color: .white.opacity(0.68))
                        }
                        previewPill("<1m", color: .white.opacity(0.45))
                    }
                }

                // Prompt & AI summary
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(isChinese ? "你：" : "You:")
                        .font(.system(size: fs + 1))
                        .foregroundStyle(.white.opacity(0.48))
                    Text("extract chatEndpoint into a transport-agnostic layer")
                        .font(.system(size: fs + 1))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(1)
                }

                if lineLimit != 1 {
                    AssistantReplyText(
                        text: Self.sampleReply,
                        fontSize: fs + 0.5,
                        lineLimit: lineLimit > 0 ? lineLimit : nil
                    )
                    .foregroundStyle(.white.opacity(0.54))
                }

                if showToolStatus {
                    Text("Editing chatEndpoint.ts · 12s")
                        .font(.system(size: fs + 0.5))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }

                // Task checklist preview (uses the real AgentTaskProgressView so it
                // matches live cards across Compact / Expanded / Card styles).
                if showTaskProgress {
                    AgentTaskProgressView(
                        tasks: AgentTaskList(items: [
                            AgentTaskItem(
                                id: "preview-1",
                                title: isChinese ? "梳理会话状态" : "Audit session state",
                                status: .completed
                            ),
                            AgentTaskItem(
                                id: "preview-2",
                                title: isChinese ? "审查身份验证流程" : "Review auth token flow",
                                status: .inProgress
                            ),
                            AgentTaskItem(
                                id: "preview-3",
                                title: isChinese ? "补充回归测试" : "Add regression tests",
                                status: .pending
                            ),
                        ]),
                        fontSize: fs,
                        agentIsIdle: false,
                        style: taskProgressStyle,
                        accentColor: accent
                    )
                }

                // Subagent tree preview
                if showAgentDetails {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9, weight: .medium))
                            Text(isChinese ? "子 Agent (2)" : "Subagents (2)")
                                .font(.system(size: max(9.5, fs - 0.5), weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.45))

                        HStack(spacing: 6) {
                            Circle().fill(accent).frame(width: 5.5, height: 5.5)
                            Text("Explore (Search API endpoints)")
                                .font(.system(size: fs, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(1)
                            Text(isChinese ? "处理中 · 8s" : "running · 8s")
                                .font(.system(size: max(9.5, fs - 0.5)))
                                .foregroundStyle(.white.opacity(0.46))
                            Spacer(minLength: 4)
                            if showModelLabel {
                                Text("Sonnet 4.6")
                                    .font(.system(size: max(9, fs - 1), weight: .medium))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                        }

                        HStack(spacing: 6) {
                            Circle().fill(Color(red: 0.30, green: 0.85, blue: 0.52).opacity(0.7)).frame(width: 5.5, height: 5.5)
                            Text("Explore (Read config files)")
                                .font(.system(size: fs, weight: .medium))
                                .foregroundStyle(.white.opacity(0.62))
                                .lineLimit(1)
                            Text(isChinese ? "完成 · 12s" : "done · 12s")
                                .font(.system(size: max(9.5, fs - 0.5)))
                                .foregroundStyle(.white.opacity(0.38))
                            Spacer(minLength: 4)
                            if showModelLabel {
                                Text("Sonnet 4.6")
                                    .font(.system(size: max(9, fs - 1), weight: .medium))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var compactRow: some View {
        HStack(spacing: 8) {
            Circle().fill(accent).frame(width: 6.5, height: 6.5)
            MascotView(source: "claude", status: .running, size: 18, animate: false)
                .frame(width: 22)
            Text(showProjectName ? "Cairn" : "Refactor auth flow")
                .font(.system(size: fs + 1, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
            if showToolStatus {
                Text("Edit · chatEndpoint.ts")
                    .font(.system(size: fs))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if showModelLabel {
                previewPill("Opus 5", color: .white.opacity(0.62))
            }
            previewPill("<1m", color: .white.opacity(0.45))
        }
        .frame(minHeight: CompactSessionRowMetrics.rowHeight)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var minimalRow: some View {
        HStack(spacing: 7) {
            Circle().fill(accent).frame(width: 6.5, height: 6.5)
            MascotView(source: "claude", status: .running, size: 16, animate: false)
                .frame(width: 18)
            Text(showProjectName ? "Cairn · Refactor auth flow" : "Refactor auth flow")
                .font(.system(size: fs + 1.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
            Spacer(minLength: 6)
            if showToolStatus {
                Text("Edit")
                    .font(.system(size: max(9.5, fs - 0.5), weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
            }
            Text("<1m")
                .font(.system(size: max(9.5, fs - 0.5), weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func previewPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: max(9, fs - 1), weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white.opacity(0.08))
            )
    }
}

// MARK: - Sound Page

struct SoundPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = SettingsDefaults.soundEnabled
    @AppStorage(SettingsKey.soundVolume) private var soundVolume = SettingsDefaults.soundVolume
    @AppStorage(SettingsKey.soundSessionStart) private var soundSessionStart = SettingsDefaults.soundSessionStart
    @AppStorage(SettingsKey.soundTaskComplete) private var soundTaskComplete = SettingsDefaults.soundTaskComplete
    @AppStorage(SettingsKey.soundTaskError) private var soundTaskError = SettingsDefaults.soundTaskError
    @AppStorage(SettingsKey.soundApprovalNeeded) private var soundApprovalNeeded = SettingsDefaults.soundApprovalNeeded
    @AppStorage(SettingsKey.soundPromptSubmit) private var soundPromptSubmit = SettingsDefaults.soundPromptSubmit
    @AppStorage(SettingsKey.soundBoot) private var soundBoot = SettingsDefaults.soundBoot
    @AppStorage(SettingsKey.quietHoursEnabled) private var quietHoursEnabled = SettingsDefaults.quietHoursEnabled
    @AppStorage(SettingsKey.quietHoursStart) private var quietHoursStart = SettingsDefaults.quietHoursStart
    @AppStorage(SettingsKey.quietHoursEnd) private var quietHoursEnd = SettingsDefaults.quietHoursEnd
    @AppStorage(SettingsKey.autoMuteWhenAway) private var autoMuteWhenAway = SettingsDefaults.autoMuteWhenAway
    @AppStorage(SettingsKey.childAgentNotificationTiming) private var childAgentNotifTiming: String = SettingsDefaults.childAgentNotificationTiming

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                Calendar.current.date(
                    bySettingHour: minutes.wrappedValue / 60,
                    minute: minutes.wrappedValue % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    var body: some View {
        FlowSettingsPageShell(page: .sound, title: l10n["sound"]) {
            FlowSettingsSection {
                FlowSettingsToggleRow(title: l10n["enable_sound"], isOn: $soundEnabled)
                if soundEnabled {
                    FlowSettingsDivider()
                    FlowSettingsRow(verticalPadding: 12) {
                        HStack(spacing: 10) {
                            Text(l10n["volume"])
                                .font(.system(size: 13.5))
                            Image(systemName: "speaker.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Slider(
                                value: Binding(
                                    get: { Double(soundVolume) },
                                    set: { soundVolume = Int($0) }
                                ),
                                in: 0...100,
                                step: 1
                            )
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            FlowValuePill(text: "\(soundVolume)%")
                        }
                    }
                }
            }

            if soundEnabled {
                FlowSettingsSection {
                    FlowSettingsPickerRow(
                        title: l10n["child_agent_notif_timing"],
                        subtitle: l10n["child_agent_notif_timing_desc"],
                        selection: $childAgentNotifTiming
                    ) {
                        Text(l10n["child_agent_notif_root_only"]).tag(ChildAgentNotificationTiming.rootOnly.rawValue)
                        Text(l10n["child_agent_notif_all_finished"]).tag(ChildAgentNotificationTiming.allFinished.rawValue)
                        Text(l10n["child_agent_notif_every"]).tag(ChildAgentNotificationTiming.everyCompletion.rawValue)
                    }
                }

                FlowSettingsSection(title: l10n["sessions"]) {
                    SoundEventRow(title: l10n["session_start"], subtitle: l10n["new_claude_session"], soundName: "8bit_start", isOn: $soundSessionStart)
                    FlowSettingsDivider()
                    SoundEventRow(title: l10n["task_complete"], subtitle: l10n["ai_completed_reply"], soundName: "8bit_complete", isOn: $soundTaskComplete)
                    FlowSettingsDivider()
                    SoundEventRow(title: l10n["task_error"], subtitle: l10n["tool_or_api_error"], soundName: "8bit_error", isOn: $soundTaskError)
                }

                FlowSettingsSection(title: l10n["interaction"]) {
                    SoundEventRow(title: l10n["approval_needed"], subtitle: l10n["waiting_approval_desc"], soundName: "8bit_approval", isOn: $soundApprovalNeeded)
                    FlowSettingsDivider()
                    SoundEventRow(title: l10n["task_confirmation"], subtitle: l10n["you_sent_message"], soundName: "8bit_submit", isOn: $soundPromptSubmit)
                }

                FlowSettingsSection(title: l10n["system_section"]) {
                    SoundEventRow(title: l10n["boot_sound"], subtitle: l10n["boot_sound_desc"], soundName: "8bit_boot", isOn: $soundBoot)
                }

                FlowSettingsSection {
                    FlowSettingsToggleRow(
                        title: l10n["quiet_hours"],
                        subtitle: l10n["quiet_hours_desc"],
                        isOn: $quietHoursEnabled
                    )
                    if quietHoursEnabled {
                        FlowSettingsDivider()
                        FlowSettingsRow {
                            HStack(spacing: 16) {
                                DatePicker(
                                    l10n["quiet_hours_start"],
                                    selection: timeBinding($quietHoursStart),
                                    displayedComponents: .hourAndMinute
                                )
                                DatePicker(
                                    l10n["quiet_hours_end"],
                                    selection: timeBinding($quietHoursEnd),
                                    displayedComponents: .hourAndMinute
                                )
                            }
                            .datePickerStyle(.field)
                        }
                    }
                    FlowSettingsDivider()
                    FlowSettingsToggleRow(
                        title: l10n["auto_mute_when_away"],
                        subtitle: l10n["auto_mute_when_away_desc"],
                        isOn: $autoMuteWhenAway
                    )
                }
            }
        }
    }
}

private struct SoundEventRow: View {
    @ObservedObject private var l10n = L10n.shared
    let title: String
    var subtitle: String? = nil
    let soundName: String
    @Binding var isOn: Bool
    @State private var customPath: String = ""

    var body: some View {
        FlowSettingsRow {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5))
                    if customPath.isEmpty {
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(l10n["custom_sound_set"].replacingOccurrences(of: "%@", with: URL(fileURLWithPath: customPath).lastPathComponent))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 12)
                Menu {
                    Button {
                        chooseCustomSound()
                    } label: {
                        Label(l10n["choose_sound_file"], systemImage: "folder")
                    }
                    if !customPath.isEmpty {
                        Button {
                            clearCustomSound()
                        } label: {
                            Label(l10n["reset_to_default"], systemImage: "arrow.counterclockwise")
                        }
                    }
                } label: {
                    Image(systemName: customPath.isEmpty ? "waveform" : "waveform.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(customPath.isEmpty ? .secondary : Color.orange)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)

                Button {
                    if !customPath.isEmpty {
                        SoundManager.shared.previewCustom(customPath)
                    } else {
                        SoundManager.shared.preview(soundName)
                    }
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .onAppear {
            customPath = UserDefaults.standard.string(forKey: SettingsKey.soundCustomPath(soundName)) ?? ""
        }
    }

    private func chooseCustomSound() {
        let panel = NSOpenPanel()
        panel.title = l10n["choose_sound_file"]
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            customPath = url.path
            UserDefaults.standard.set(url.path, forKey: SettingsKey.soundCustomPath(soundName))
        }
    }

    private func clearCustomSound() {
        customPath = ""
        UserDefaults.standard.removeObject(forKey: SettingsKey.soundCustomPath(soundName))
    }
}

// MARK: - Mascots Page

struct MascotsPage: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var previewStatus: AgentStatus = .processing
    @AppStorage(SettingsKey.mascotSpeed) private var mascotSpeed = SettingsDefaults.mascotSpeed
    @AppStorage(SettingsKey.defaultSource) private var defaultSource = SettingsDefaults.defaultSource

    private let mascotList: [(name: String, source: String, desc: String, color: Color)] = [
        ("Clawd", "claude", "Claude Code", Color(red: 0.871, green: 0.533, blue: 0.427)),
        ("Dex", "codex", "Codex (OpenAI)", Color(red: 0.92, green: 0.92, blue: 0.93)),
        ("Grok", "grok", "Grok CLI", Color.white),
        ("Gemini", "gemini", "Gemini CLI", Color(red: 0.278, green: 0.588, blue: 0.894)),
        ("CursorBot", "cursor", "Cursor", Color(red: 0.96, green: 0.31, blue: 0.0)),
        ("TraeBot", "trae", "Trae", Color(red: 0.96, green: 0.31, blue: 0.0)),
        ("TraeCNBot", "traecn", "Trae CN", Color(red: 0.96, green: 0.31, blue: 0.0)),
        ("CopilotBot", "copilot", "GitHub Copilot", Color(red: 0.35, green: 0.75, blue: 0.95)),
        ("QoderBot", "qoder", "Qoder", Color(red: 0.165, green: 0.859, blue: 0.361)),
        ("QoderBot", "qoderwork", "QoderWork", Color(red: 0.165, green: 0.859, blue: 0.361)),
        ("Droid", "droid", "Factory", Color(red: 0.835, green: 0.416, blue: 0.149)),
        ("Buddy", "codebuddy", "CodeBuddy", Color(red: 0.424, green: 0.302, blue: 1.0)),
        ("BuddyCN", "codybuddycn", "CodyBuddyCN", Color(red: 0.424, green: 0.302, blue: 1.0)),
        ("StepFun", "stepfun", "StepFun", Color(red: 0.424, green: 0.302, blue: 1.0)),
        ("AntiGravity", "antigravity", "AntiGravity", Color(red: 0.424, green: 0.302, blue: 1.0)),
        ("WorkBuddy", "workbuddy", "WorkBuddy", Color(red: 0.475, green: 0.380, blue: 0.870)),
        ("Hermes", "hermes", "Hermes", Color(red: 0.424, green: 0.302, blue: 1.0)),
        ("Molty", "openclaw", "OpenClaw", Color(red: 0.93, green: 0.36, blue: 0.24)),
        ("QwenBot", "qwen", "Qwen Code", Color(red: 0.486, green: 0.228, blue: 0.929)),
        ("KimiBot", "kimi", "Kimi Code CLI", Color(red: 0.29, green: 0.56, blue: 1.0)),
        ("Kiro", "kiro", "Kiro", Color(red: 0.62, green: 0.45, blue: 1.0)),
        ("MiniMax", "minimax", "MiniMax Code CLI", Color(red: 1.0, green: 0.36, blue: 0.30)),
        ("Pi", "pi", "Pi", Color(red: 0.55, green: 0.43, blue: 0.95)),
        ("Oh My Pi", "omp", "Oh My Pi", Color(red: 0.55, green: 0.43, blue: 0.95)),
        ("OpBot", "opencode", "OpenCode", Color(red: 0.55, green: 0.55, blue: 0.57)),
        ("MiMoBot", "mimo", "MiMo Code / Xiaomi MiMo", Color(red: 1.0, green: 0.41, blue: 0.0)),
        ("ClineBot", "cline", "Cline", Color(red: 0.00, green: 0.70, blue: 0.49)),
        ("Gemini", "google-antigravity", "Google Antigravity", Color(red: 0.278, green: 0.588, blue: 0.894)),
        ("AiWorkBot", "aiwork", "AiWork", Color(red: 0.12, green: 0.72, blue: 0.28)),
        ("AiWorkBot", "aiwork-cli", "AiWork CLI", Color(red: 0.12, green: 0.55, blue: 0.90)),
        ("DeepSeek", "dsh", "DeepSeek Harness", Color(red: 0.302, green: 0.42, blue: 0.996)),
    ]

    var body: some View {
        FlowSettingsPageShell(page: .mascots, title: l10n["mascots"]) {
            FlowSettingsSection {
                FlowSettingsRow {
                    HStack(spacing: 12) {
                        Text(l10n["preview_status"])
                            .font(.system(size: 13.5))
                        Spacer()
                        Picker("", selection: $previewStatus) {
                            Text(l10n["processing"]).tag(AgentStatus.processing)
                            Text(l10n["idle"]).tag(AgentStatus.idle)
                            Text(l10n["waiting_approval"]).tag(AgentStatus.waitingApproval)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)
                    }
                }

                FlowSettingsDivider()
                FlowSettingsSliderRow(
                    title: l10n["mascot_speed"],
                    valueText: mascotSpeed == 0
                        ? l10n["speed_off"]
                        : String(format: "%.1f×", Double(mascotSpeed) / 100.0),
                    value: Binding(
                        get: { Double(mascotSpeed) },
                        set: { mascotSpeed = Int($0) }
                    ),
                    range: 0...300,
                    step: 25,
                    tickCount: 13
                )

                FlowSettingsDivider()
                FlowSettingsPickerRow(
                    title: l10n["default_mascot"],
                    subtitle: l10n["default_mascot_desc"],
                    selection: $defaultSource
                ) {
                    ForEach(mascotList, id: \.source) { mascot in
                        Text(mascot.desc).tag(mascot.source)
                    }
                }
                .onChange(of: defaultSource) { _, _ in
                    ESP32StatePublisher.shared.notifyDirty()
                }
            }

            FlowSettingsSection {
                ForEach(Array(mascotList.enumerated()), id: \.element.source) { idx, mascot in
                    if idx > 0 { FlowSettingsDivider() }
                    FlowSettingsRow(verticalPadding: 8) {
                        MascotRow(
                            name: mascot.name,
                            source: mascot.source,
                            desc: mascot.desc,
                            color: mascot.color,
                            status: previewStatus
                        )
                    }
                }
            }
        }
    }
}

private struct MascotRow: View {
    let name: String
    let source: String
    let desc: String
    let color: Color
    let status: AgentStatus

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black)
                    .frame(width: 52, height: 52)
                MascotView(source: source, status: status, size: 38)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    if let icon = cliIcon(source: source, size: 16) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                }
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
