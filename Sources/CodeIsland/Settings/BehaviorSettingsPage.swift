import SwiftUI
import AppKit
import CodeIslandCore

// MARK: - Behavior Page

struct BehaviorPage: View {
    @ObservedObject private var l10n = L10n.shared
    var appState: AppState?

    @AppStorage(SettingsKey.hideInFullscreen) private var hideInFullscreen = SettingsDefaults.hideInFullscreen
    @AppStorage(SettingsKey.hideWhenNoSession) private var hideWhenNoSession = SettingsDefaults.hideWhenNoSession
    @AppStorage(SettingsKey.showMenuBarIcon) private var showMenuBarIcon = SettingsDefaults.showMenuBarIcon
    @AppStorage(SettingsKey.smartSuppress) private var smartSuppress = SettingsDefaults.smartSuppress
    @AppStorage(SettingsKey.collapseOnMouseLeave) private var collapseOnMouseLeave = SettingsDefaults.collapseOnMouseLeave
    @AppStorage(SettingsKey.autoCollapseAfterSessionJump) private var autoCollapseAfterSessionJump = SettingsDefaults.autoCollapseAfterSessionJump
    @AppStorage(SettingsKey.autoExpandOnPermission) private var autoExpandOnPermission = SettingsDefaults.autoExpandOnPermission
    @AppStorage(SettingsKey.followUpReminderMinutes) private var followUpReminderMinutes = SettingsDefaults.followUpReminderMinutes
    // Seeded through the migration shim so a legacy autoExpandOnCompletion=false
    // shows up as "off" here; writes go to the new key via onChange.
    @State private var completionStyle: String = AppState.completionStyle().rawValue
    @AppStorage(SettingsKey.pluginSessionMode) private var pluginSessionMode = SettingsDefaults.pluginSessionMode
    @AppStorage(SettingsKey.hapticOnHover) private var hapticOnHover = SettingsDefaults.hapticOnHover
    @AppStorage(SettingsKey.hapticIntensity) private var hapticIntensity = SettingsDefaults.hapticIntensity
    @AppStorage(SettingsKey.hoverExpandDelay) private var hoverExpandDelay = SettingsDefaults.hoverExpandDelay
    @AppStorage(SettingsKey.autoExpandOnQuestion) private var autoExpandOnQuestion = SettingsDefaults.autoExpandOnQuestion
    @AppStorage(SettingsKey.sessionTimeout) private var sessionTimeout = SettingsDefaults.sessionTimeout
    @AppStorage(SettingsKey.rotationInterval) private var rotationInterval = SettingsDefaults.rotationInterval
    @AppStorage(SettingsKey.maxToolHistory) private var maxToolHistory = SettingsDefaults.maxToolHistory
    @AppStorage(SettingsKey.autoApproveTools) private var autoApproveRaw: String = SettingsDefaults.autoApproveTools
    @AppStorage(SettingsKey.autoApproveSources) private var autoApproveSources: String = SettingsDefaults.autoApproveSources
    @AppStorage(SettingsKey.excludedHookCwdSubstrings) private var excludedHookCwdSubstrings: String = SettingsDefaults.excludedHookCwdSubstrings
    @AppStorage(SettingsKey.claudeConfigDir) private var claudeConfigDir: String = SettingsDefaults.claudeConfigDir
    @AppStorage(SettingsKey.webhookEnabled) private var webhookEnabled: Bool = SettingsDefaults.webhookEnabled
    @AppStorage(SettingsKey.webhookURL) private var webhookURL: String = SettingsDefaults.webhookURL
    @AppStorage(SettingsKey.webhookEventFilter) private var webhookEventFilter: String = SettingsDefaults.webhookEventFilter
    @AppStorage(SettingsKey.keepTodaySessions) private var keepTodaySessions: Bool = SettingsDefaults.keepTodaySessions
    @AppStorage(SettingsKey.showUnreadBadge) private var showUnreadBadge: Bool = SettingsDefaults.showUnreadBadge
    @AppStorage(SettingsKey.dismissOnOutsideClick) private var dismissOnOutsideClick: Bool = SettingsDefaults.dismissOnOutsideClick
    @AppStorage(SettingsKey.childAgentNotificationTiming) private var childAgentNotifTiming: String = SettingsDefaults.childAgentNotificationTiming
    @AppStorage(SettingsKey.silenceRulesJSON) private var silenceRulesJSON: String = SettingsDefaults.silenceRulesJSON

    private var pluginSessionModeBinding: Binding<String> {
        Binding(
            get: { pluginSessionMode },
            set: { newMode in
                guard pluginSessionMode != newMode else { return }
                pluginSessionMode = newMode
                appState?.applyCurrentPluginSessionMode()
            }
        )
    }

    private func autoApproveBinding(for name: String) -> Binding<Bool> {
        Binding(
            get: { autoApproveRaw.split(separator: ",").contains(Substring(name)) },
            set: { isOn in
                var set = Set(autoApproveRaw.split(separator: ",").map(String.init))
                if isOn { set.insert(name) } else { set.remove(name) }
                autoApproveRaw = set.sorted().joined(separator: ",")
            }
        )
    }

    var body: some View {
        FlowSettingsPageShell(page: .behavior, title: l10n["behavior"]) {
            SessionHubSettingsSection(
                keepTodaySessions: $keepTodaySessions,
                dismissOnOutsideClick: $dismissOnOutsideClick,
                showUnreadBadge: $showUnreadBadge
            )

            SilenceRulesSettingsSection(rulesJSON: $silenceRulesJSON)

            FlowSettingsSection(title: l10n["display_section"]) {
                BehaviorToggleRow(
                    title: l10n["hide_in_fullscreen"],
                    desc: l10n["hide_in_fullscreen_desc"],
                    isOn: $hideInFullscreen,
                    animation: .hideFullscreen
                )
                FlowSettingsDivider()
                BehaviorToggleRow(
                    title: l10n["hide_when_no_session"],
                    desc: l10n["hide_when_no_session_desc"],
                    isOn: $hideWhenNoSession,
                    animation: .hideNoSession
                )
                if hideWhenNoSession {
                    FlowSettingsDivider()
                    FlowSettingsToggleRow(
                        title: l10n["show_menu_bar_icon"],
                        subtitle: l10n["show_menu_bar_icon_desc"],
                        isOn: $showMenuBarIcon
                    )
                }
                FlowSettingsDivider()
                BehaviorToggleRow(
                    title: l10n["smart_suppress"],
                    desc: l10n["smart_suppress_desc"],
                    isOn: $smartSuppress,
                    animation: .smartSuppress
                )
                FlowSettingsDivider()
                BehaviorToggleRow(
                    title: l10n["auto_expand_on_permission"],
                    desc: l10n["auto_expand_on_permission_desc"],
                    isOn: $autoExpandOnPermission,
                    animation: .smartSuppress
                )
                FlowSettingsDivider()
                BehaviorToggleRow(
                    title: l10n["auto_expand_on_question"],
                    desc: l10n["auto_expand_on_question_desc"],
                    isOn: $autoExpandOnQuestion,
                    animation: .smartSuppress
                )
                FlowSettingsDivider()
                BehaviorToggleRow(
                    title: l10n["collapse_on_mouse_leave"],
                    desc: l10n["collapse_on_mouse_leave_desc"],
                    isOn: $collapseOnMouseLeave,
                    animation: .collapseMouseLeave
                )
                FlowSettingsDivider()
                BehaviorToggleRow(
                    title: l10n["auto_collapse_after_session_jump"],
                    desc: l10n["auto_collapse_after_session_jump_desc"],
                    isOn: $autoCollapseAfterSessionJump,
                    animation: .clickJumpCollapse
                )
                FlowSettingsDivider()
                FlowSettingsPickerRow(
                    title: l10n["completion_notification"],
                    subtitle: l10n["completion_notification_desc"],
                    selection: $completionStyle
                ) {
                    Text(l10n["completion_style_expand"]).tag(AppState.CompletionStyle.expand.rawValue)
                    Text(l10n["completion_style_glance"]).tag(AppState.CompletionStyle.glance.rawValue)
                    Text(l10n["completion_style_off"]).tag(AppState.CompletionStyle.off.rawValue)
                }
                .onChange(of: completionStyle) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: SettingsKey.completionNotificationStyle)
                }

                FlowSettingsDivider()
                FlowSettingsPickerRow(
                    title: l10n["follow_up_reminders"],
                    subtitle: l10n["follow_up_reminders_desc"],
                    selection: $followUpReminderMinutes
                ) {
                    ForEach(FollowUpReminderController.intervalChoices, id: \.self) { minutes in
                        Text(minutes == 0
                             ? l10n["follow_up_off"]
                             : String(format: l10n["follow_up_after_minutes"], minutes))
                            .tag(minutes)
                    }
                }
                .onChange(of: followUpReminderMinutes) { _, _ in
                    appState?.followUps.settingsChanged()
                }

                FlowSettingsDivider()
                let delay = NotchHoverInteraction.expandDelay(forSetting: hoverExpandDelay)
                FlowSettingsSliderRow(
                    title: l10n["hover_expand_delay"],
                    subtitle: l10n["hover_expand_delay_desc"],
                    valueText: String(format: l10n["hover_expand_delay_value"], delay),
                    value: Binding(
                        get: { NotchHoverInteraction.expandDelay(forSetting: hoverExpandDelay) },
                        set: { hoverExpandDelay = NotchHoverInteraction.expandDelay(forSetting: $0) }
                    ),
                    range: NotchHoverInteraction.expandDelayRange,
                    step: NotchHoverInteraction.expandDelayStep,
                    tickCount: 9
                )

                FlowSettingsDivider()
                BehaviorToggleRow(
                    title: l10n["haptic_on_hover"],
                    desc: l10n["haptic_on_hover_desc"],
                    isOn: $hapticOnHover,
                    animation: .hapticHover
                )
                if hapticOnHover {
                    FlowSettingsRow(verticalPadding: 8) {
                        Picker("", selection: $hapticIntensity) {
                            Text(l10n["haptic_light"]).tag(1)
                            Text(l10n["haptic_medium"]).tag(2)
                            Text(l10n["haptic_strong"]).tag(3)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .padding(.leading, 84)
                    }
                }
            }

            FlowSettingsSection(title: l10n["auto_approve_tools"], footer: l10n["auto_approve_tools_desc"]) {
                ForEach(Array(SettingsManager.allAutoApproveTools.enumerated()), id: \.element.name) { idx, tool in
                    if idx > 0 { FlowSettingsDivider() }
                    FlowSettingsRow {
                        HStack(alignment: .center, spacing: 14) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tool.name)
                                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                                Text(l10n["auto_approve_\(tool.name)"])
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            Toggle("", isOn: autoApproveBinding(for: tool.name))
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                }

                FlowSettingsDivider()
                FlowSettingsRow {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(l10n["auto_approve_sources"])
                            .font(.system(size: 13, weight: .medium))
                        Text(l10n["auto_approve_sources_desc"])
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        TextField(
                            l10n["auto_approve_sources_placeholder"],
                            text: $autoApproveSources
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    }
                }
            }

            FlowSettingsSection(title: l10n["claude_config_dir_title"], footer: l10n["extra_config_dirs_more_hint"]) {
                FlowSettingsRow {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(l10n["claude_config_dir_desc"])
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        TextField(l10n["claude_config_dir_placeholder"], text: $claudeConfigDir)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        Text(String(
                            format: l10n["claude_config_dir_resolved"],
                            ClaudeConfigPaths.displayPath(ClaudeConfigPaths.configDir())
                        ))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }
                }
            }

            FlowSettingsSection(title: l10n["excluded_hook_cwd_title"]) {
                FlowSettingsRow {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(l10n["excluded_hook_cwd_desc"])
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        TextField(l10n["excluded_hook_cwd_placeholder"], text: $excludedHookCwdSubstrings)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
            }

            FlowSettingsSection(title: l10n["webhook_title"]) {
                FlowSettingsToggleRow(
                    title: l10n["webhook_enable"],
                    subtitle: l10n["webhook_desc"],
                    isOn: $webhookEnabled
                )
                if webhookEnabled {
                    FlowSettingsDivider()
                    FlowSettingsRow {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField(l10n["webhook_url_placeholder"], text: $webhookURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .autocorrectionDisabled(true)
                            TextField(l10n["webhook_filter_placeholder"], text: $webhookEventFilter)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .autocorrectionDisabled(true)
                            Text(l10n["webhook_filter_hint"])
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            PushNotificationsSection()

            FlowSettingsSection(title: l10n["sessions"]) {
                FlowSettingsPickerRow(
                    title: l10n["session_cleanup"],
                    subtitle: l10n["session_cleanup_desc"],
                    selection: $sessionTimeout
                ) {
                    Text(l10n["no_cleanup"]).tag(0)
                    Text(l10n["10_minutes"]).tag(10)
                    Text(l10n["30_minutes"]).tag(30)
                    Text(l10n["1_hour"]).tag(60)
                    Text(l10n["2_hours"]).tag(120)
                }

                FlowSettingsDivider()
                FlowSettingsPickerRow(
                    title: l10n["rotation_interval"],
                    subtitle: l10n["rotation_interval_desc"],
                    selection: $rotationInterval
                ) {
                    Text(l10n["3_seconds"]).tag(3)
                    Text(l10n["5_seconds"]).tag(5)
                    Text(l10n["8_seconds"]).tag(8)
                    Text(l10n["10_seconds"]).tag(10)
                }

                FlowSettingsDivider()
                FlowSettingsPickerRow(
                    title: l10n["tool_history_limit"],
                    subtitle: l10n["tool_history_limit_desc"],
                    selection: $maxToolHistory
                ) {
                    Text("10").tag(10)
                    Text("20").tag(20)
                    Text("50").tag(50)
                    Text("100").tag(100)
                }

                FlowSettingsDivider()
                FlowSettingsPickerRow(
                    title: l10n["child_agent_notif_timing"],
                    subtitle: l10n["child_agent_notif_timing_desc"],
                    selection: $childAgentNotifTiming
                ) {
                    Text(l10n["child_agent_notif_root_only"]).tag(ChildAgentNotificationTiming.rootOnly.rawValue)
                    Text(l10n["child_agent_notif_all_finished"]).tag(ChildAgentNotificationTiming.allFinished.rawValue)
                    Text(l10n["child_agent_notif_every"]).tag(ChildAgentNotificationTiming.everyCompletion.rawValue)
                }

                FlowSettingsDivider()
                FlowSettingsPickerRow(
                    title: l10n["plugin_session_mode"],
                    subtitle: l10n["plugin_session_mode_desc"],
                    selection: pluginSessionModeBinding
                ) {
                    Text(l10n["plugin_session_mode_separate"]).tag("separate")
                    Text(l10n["plugin_session_mode_merge"]).tag("merge")
                    Text(l10n["plugin_session_mode_hide"]).tag("hide")
                }
            }
        }
    }
}

// MARK: - Behavior Animation Previews

private enum BehaviorAnim {
    case hideFullscreen, hideNoSession, smartSuppress, collapseMouseLeave, clickJumpCollapse, hapticHover
}

struct ClickJumpCollapsePreviewTimeline {
    let expand: Double
    let showClickRing: Bool
    let ringOpacity: Double
    let ringRadius: CGFloat
    let cursorX: CGFloat
    let cursorY: CGFloat
    let clickPointY: CGFloat
    let showSuccessArrow: Bool
    let successArrowOpacity: Double
}

func clickJumpCollapsePreviewTimeline(progress: Double) -> ClickJumpCollapsePreviewTimeline {
    // Wrap to [0,1) so loop seam is identical between end and start.
    let p = progress >= 1 ? progress.truncatingRemainder(dividingBy: 1) : min(1, max(0, progress))

    let clickPointY: CGFloat = 16

    // Seam-friendly phases:
    // [0.00, 0.08): expanded + cursor very fast move in (from offscreen)
    // [0.08, 0.26): expanded + cursor hover before click
    // [0.26, 0.32): click ring pulse
    // [0.32, 0.47): collapse (match mouse-leave collapse speed)
    // [0.47, 0.62): collapsed hold
    // [0.62, 0.80): cursor moves fully offscreen
    // [0.80, 0.93): expand back (match mouse-leave expand speed, after cursor is offscreen)
    // [0.93, 1.00): fully expanded idle with cursor still offscreen
    let expand: Double
    switch p {
    case ..<0.32:
        expand = 1.0
    case ..<0.47:
        expand = max(0, 1.0 - (p - 0.32) / 0.15)
    case ..<0.80:
        expand = 0
    case ..<0.93:
        expand = min(1, (p - 0.80) / 0.13)
    default:
        expand = 1.0
    }

    let cursorX: CGFloat
    let cursorY: CGFloat
    switch p {
    case ..<0.08:
        let m = p / 0.08
        cursorX = CGFloat((1 - m) * 34)
        cursorY = CGFloat((1 - m) * 28)
    case ..<0.62:
        cursorX = 0
        cursorY = 0
    case ..<0.80:
        let m = (p - 0.62) / 0.18
        cursorX = CGFloat(m * 34)
        cursorY = CGFloat(m * 28)
    default:
        cursorX = 34
        cursorY = 28
    }

    let ringWindow = p >= 0.26 && p <= 0.32
    let ringPhase = ringWindow ? (p - 0.26) / 0.06 : 0
    let ringOpacity = ringWindow ? sin(ringPhase * .pi) : 0
    let ringRadius: CGFloat = 4 + CGFloat(ringPhase) * 6

    let arrowWindow = p >= 0.34 && p <= 0.42
    let arrowPhase = arrowWindow ? (p - 0.34) / 0.08 : 0
    let arrowOpacity = arrowWindow ? sin(arrowPhase * .pi) : 0

    return ClickJumpCollapsePreviewTimeline(
        expand: expand,
        showClickRing: ringWindow,
        ringOpacity: ringOpacity,
        ringRadius: ringRadius,
        cursorX: cursorX,
        cursorY: cursorY,
        clickPointY: clickPointY,
        showSuccessArrow: arrowWindow,
        successArrowOpacity: arrowOpacity
    )
}

private struct BehaviorToggleRow: View {
    let title: String
    let desc: String
    @Binding var isOn: Bool
    let animation: BehaviorAnim

    var body: some View {
        FlowSettingsRow {
            HStack(alignment: .center, spacing: 12) {
                NotchMiniAnim(animation: animation)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.primary)
                    Text(desc)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }
}

/// Canvas-based notch animation with smooth interpolation.
private struct NotchMiniAnim: View {
    let animation: BehaviorAnim
    private let orange = Color(red: 0.96, green: 0.65, blue: 0.14)

    var body: some View {
        FrameClock(interval: FrameTicker.step) { now in
            Canvas { c, sz in
                draw(c, sz: sz, t: now)
            }
        }
        .frame(width: 72, height: 48)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(min(1, max(0, t)))
    }

    private func draw(_ c: GraphicsContext, sz: CGSize, t: Double) {
        switch animation {
        case .hideFullscreen: drawFullscreen(c, sz: sz, t: t)
        case .hideNoSession: drawNoSession(c, sz: sz, t: t)
        case .smartSuppress: drawSuppress(c, sz: sz, t: t)
        case .collapseMouseLeave: drawMouseLeave(c, sz: sz, t: t)
        case .clickJumpCollapse: drawClickJumpCollapse(c, sz: sz, t: t)
        case .hapticHover: drawHaptic(c, sz: sz, t: t)
        }
    }

    private func drawPill(
        _ c: GraphicsContext,
        sz: CGSize,
        w: CGFloat,
        h: CGFloat,
        op: Double,
        flashColor: Color? = nil
    ) {
        guard op > 0.01 else { return }
        let x = (sz.width - w) / 2
        let r = min(w, h) * 0.45
        let rect = CGRect(x: x, y: 0, width: w, height: h)
        let pill = Path(roundedRect: rect, cornerRadius: r, style: .continuous)
        c.fill(pill, with: .color(Color(white: 0.06).opacity(op)))

        let eyeSize: CGFloat = h > 16 ? 3.5 : 2.5
        let eyeY: CGFloat = h > 16 ? 5 : max(2, (h - eyeSize) / 2)
        let eyeGap: CGFloat = h > 16 ? 5 : 3
        c.fill(
            Path(CGRect(x: sz.width / 2 - eyeGap - eyeSize / 2, y: eyeY, width: eyeSize, height: eyeSize)),
            with: .color(orange.opacity(op))
        )
        c.fill(
            Path(CGRect(x: sz.width / 2 + eyeGap - eyeSize / 2, y: eyeY, width: eyeSize, height: eyeSize)),
            with: .color(orange.opacity(op))
        )

        if h > 16 {
            let contentOp = op * Double(min(1, (h - 16) / 10))
            let lx = x + 6
            let widths: [CGFloat] = [w * 0.6, w * 0.45, w * 0.55]
            for (i, lw) in widths.enumerated() {
                let ly = 12 + CGFloat(i) * 5
                if ly + 2 < h - 3 {
                    c.fill(
                        Path(CGRect(x: lx, y: ly, width: lw, height: 2)),
                        with: .color(.white.opacity(0.3 * contentOp * (1 - Double(i) * 0.2)))
                    )
                }
            }
        }

        if let color = flashColor {
            c.fill(pill, with: .color(color))
        }
    }

    private func drawFullscreen(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.5) / 3.5
        let vis: Double = cycle < 0.3 ? 1.0 :
            cycle < 0.45 ? 1.0 - (cycle - 0.3) / 0.15 :
            cycle < 0.7 ? 0.0 :
            min(1, (cycle - 0.7) / 0.15)
        if vis < 0.95 {
            c.fill(
                Path(CGRect(origin: .zero, size: sz)),
                with: .color(Color(white: 0.08).opacity(0.85 * (1 - vis)))
            )
            let iconOp = cycle > 0.45 && cycle < 0.65 ? sin((cycle - 0.45) / 0.2 * .pi) * 0.5 : 0
            if iconOp > 0.01 {
                c.draw(
                    Text("⛶").font(.system(size: 16)).foregroundColor(.white.opacity(iconOp)),
                    at: CGPoint(x: sz.width / 2, y: sz.height / 2 + 2)
                )
            }
        }
        drawPill(c, sz: sz, w: 28, h: 10, op: vis)
    }

    private func drawNoSession(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.5) / 3.5
        let dotOp: Double = cycle < 0.25 ? 1.0 :
            cycle < 0.4 ? 1.0 - (cycle - 0.25) / 0.15 :
            cycle < 0.7 ? 0.0 :
            min(1, (cycle - 0.7) / 0.15)
        let pillOp: Double = cycle < 0.35 ? 1.0 :
            cycle < 0.55 ? 1.0 - (cycle - 0.35) / 0.2 :
            cycle < 0.7 ? 0.0 :
            min(1, (cycle - 0.7) / 0.15)

        drawPill(c, sz: sz, w: 28, h: 10, op: pillOp)
        if dotOp > 0.01 {
            let cx = sz.width / 2
            for i in 0..<2 {
                let dx: CGFloat = CGFloat(i) * 6 - 3
                c.fill(
                    Path(ellipseIn: CGRect(x: cx + dx - 1.5, y: 3, width: 3, height: 3)),
                    with: .color(.green.opacity(0.85 * dotOp * pillOp))
                )
            }
        }
    }

    private func drawSuppress(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.0) / 3.0
        let p1 = (cycle > 0.15 && cycle < 0.4) ? sin((cycle - 0.15) / 0.25 * .pi) : 0.0
        let p2 = (cycle > 0.55 && cycle < 0.75) ? sin((cycle - 0.55) / 0.2 * .pi) : 0.0
        let pulse = max(p1, p2)
        let pw = 28 + CGFloat(pulse) * 8
        let ph: CGFloat = 10 + CGFloat(pulse) * 3

        let flashColor: Color? = pulse > 0.05 ? .green.opacity(0.3 * pulse) : nil
        drawPill(c, sz: sz, w: pw, h: ph, op: 1.0, flashColor: flashColor)

        let xOp1 = (cycle > 0.3 && cycle < 0.48) ? sin((cycle - 0.3) / 0.18 * .pi) : 0.0
        let xOp2 = (cycle > 0.68 && cycle < 0.82) ? sin((cycle - 0.68) / 0.14 * .pi) : 0.0
        let xOp = max(xOp1, xOp2)
        if xOp > 0.01 {
            c.draw(
                Text("✕").font(.system(size: 9, weight: .bold)).foregroundColor(.orange.opacity(0.7 * xOp)),
                at: CGPoint(x: sz.width / 2, y: 18)
            )
        }
    }

    private func drawMouseLeave(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.5) / 3.5
        let expand: Double = cycle < 0.12 ? 0 :
            cycle < 0.25 ? (cycle - 0.12) / 0.13 :
            cycle < 0.5 ? 1.0 :
            cycle < 0.65 ? 1.0 - (cycle - 0.5) / 0.15 : 0

        let pw = lerp(28, 64, expand)
        let ph = lerp(10, 34, expand)
        drawPill(c, sz: sz, w: pw, h: ph, op: 1.0)

        let cursorPhase = cycle
        if cursorPhase > 0.05 && cursorPhase < 0.68 {
            let cx: CGFloat, cy: CGFloat
            if cursorPhase < 0.12 {
                let p = (cursorPhase - 0.05) / 0.07
                cx = lerp(sz.width / 2 + 15, sz.width / 2 + 2, p)
                cy = lerp(sz.height - 5, 8, p)
            } else if cursorPhase < 0.5 {
                cx = sz.width / 2 + 2
                cy = lerp(8, 6, expand)
            } else {
                let p = (cursorPhase - 0.5) / 0.18
                cx = lerp(sz.width / 2 + 2, sz.width - 2, min(1, p))
                cy = lerp(6, sz.height - 2, min(1, p))
            }
            drawCursorArrow(c, x: cx, y: cy)
        }
    }

    private func drawClickJumpCollapse(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.5) / 3.5
        let timeline = clickJumpCollapsePreviewTimeline(progress: cycle)

        let pw = lerp(28, 64, timeline.expand)
        let ph = lerp(10, 34, timeline.expand)
        drawPill(c, sz: sz, w: pw, h: ph, op: 1.0)

        if timeline.showClickRing {
            let r = timeline.ringRadius
            let circle = Path(ellipseIn: CGRect(
                x: sz.width / 2 - r,
                y: timeline.clickPointY - r / 2,
                width: r * 2,
                height: r * 2
            ))
            c.stroke(circle, with: .color(.white.opacity(0.45 * timeline.ringOpacity)), lineWidth: 1)
        }

        if timeline.showSuccessArrow {
            c.draw(
                Text("↗").font(.system(size: 10, weight: .bold)).foregroundColor(.green.opacity(0.75 * timeline.successArrowOpacity)),
                at: CGPoint(x: sz.width / 2 + 13, y: timeline.clickPointY + 10)
            )
        }

        drawCursorArrow(c, x: sz.width / 2 + 2 + timeline.cursorX, y: timeline.clickPointY + timeline.cursorY)
    }

    private func drawHaptic(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 2.5) / 2.5
        let cursorIn = cycle > 0.05 && cycle < 0.55
        let shakePhase = cycle > 0.15 && cycle < 0.35
        let shakeOffset: CGFloat = shakePhase ? CGFloat(sin(cycle * 180)) * 2.5 : 0

        drawPill(c, sz: CGSize(width: sz.width + shakeOffset, height: sz.height), w: 28, h: 10, op: 1.0)

        if shakePhase {
            let lineOp = sin((cycle - 0.15) / 0.2 * .pi)
            let cx = sz.width / 2
            for dx: CGFloat in [-10, -6, 6, 10] {
                let x = cx + dx + shakeOffset / 2
                c.fill(
                    Path(CGRect(x: x, y: 13, width: 0.8, height: 3)),
                    with: .color(orange.opacity(0.6 * lineOp))
                )
            }
        }

        if cursorIn {
            let cx: CGFloat, cy: CGFloat
            if cycle < 0.15 {
                let p = (cycle - 0.05) / 0.1
                cx = lerp(sz.width / 2 + 15, sz.width / 2 + 2, p)
                cy = lerp(sz.height - 5, 8, p)
            } else {
                cx = sz.width / 2 + 2
                cy = 8
            }
            drawCursorArrow(c, x: cx, y: cy)
        }
    }

    private func drawCursorArrow(_ c: GraphicsContext, x cx: CGFloat, y cy: CGFloat) {
        var arrow = Path()
        arrow.move(to: CGPoint(x: cx, y: cy))
        arrow.addLine(to: CGPoint(x: cx, y: cy + 8))
        arrow.addLine(to: CGPoint(x: cx + 2.5, y: cy + 6))
        arrow.addLine(to: CGPoint(x: cx + 5.5, y: cy + 6))
        arrow.closeSubpath()
        c.fill(arrow, with: .color(.white.opacity(0.9)))
        c.stroke(arrow, with: .color(.black.opacity(0.4)), lineWidth: 0.5)
    }
}
