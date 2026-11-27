import SwiftUI
import CodeIslandCore

// MARK: - Localization Helper

private func settingsLocalized(_ l10n: L10n, _ key: String, fallback: String) -> String {
    let value = l10n[key]
    return value == key ? fallback : value
}

// MARK: - 1. Session Hub Settings Section

/// Settings card for Today's Session Hub retention, collapsed unread badge,
/// and outside-click dismissal behavior. Designed to drop directly into
/// `BehaviorSettingsPage.swift`.
struct SessionHubSettingsSection: View {
    @Binding var keepTodaySessions: Bool
    @Binding var dismissOnOutsideClick: Bool
    @Binding var showUnreadBadge: Bool
    @ObservedObject private var l10n = L10n.shared

    init(
        keepTodaySessions: Binding<Bool>,
        dismissOnOutsideClick: Binding<Bool>,
        showUnreadBadge: Binding<Bool>
    ) {
        self._keepTodaySessions = keepTodaySessions
        self._dismissOnOutsideClick = dismissOnOutsideClick
        self._showUnreadBadge = showUnreadBadge
    }

    var body: some View {
        FlowSettingsSection(
            title: settingsLocalized(l10n, "hub_section_title", fallback: "Session Hub")
        ) {
            FlowSettingsToggleRow(
                title: settingsLocalized(l10n, "hub_keep_today", fallback: "Keep Today's Sessions"),
                subtitle: settingsLocalized(
                    l10n,
                    "hub_keep_today_desc",
                    fallback: "Keep finished sessions from today visible in the expanded Hub instead of clearing them after idle timeout."
                ),
                isOn: $keepTodaySessions
            )
            FlowSettingsDivider()
            FlowSettingsToggleRow(
                title: settingsLocalized(l10n, "hub_show_unread_badge", fallback: "Show Unread Badge on Island"),
                subtitle: settingsLocalized(
                    l10n,
                    "hub_show_unread_badge_desc",
                    fallback: "Display a glowing unread counter on the collapsed notch when background sessions finish or need attention."
                ),
                isOn: $showUnreadBadge
            )
            FlowSettingsDivider()
            FlowSettingsToggleRow(
                title: settingsLocalized(l10n, "hub_dismiss_outside_click", fallback: "Dismiss on Outside Click"),
                subtitle: settingsLocalized(
                    l10n,
                    "hub_dismiss_outside_click_desc",
                    fallback: "Collapse the expanded Session Hub automatically when clicking outside the island."
                ),
                isOn: $dismissOnOutsideClick
            )
        }
    }
}

// MARK: - 2. Silence Rules Settings Section

/// Settings card for built-in background noise presets and custom blocked
/// directory / prompt prefix rules. Backed by JSON-encoded `SilenceRuleConfig`.
struct SilenceRulesSettingsSection: View {
    @Binding var rulesJSON: String
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var scheme

    @State private var newDirectoryInput: String = ""
    @State private var newPromptInput: String = ""

    init(rulesJSON: Binding<String>) {
        self._rulesJSON = rulesJSON
    }

    private var config: SilenceRuleConfig {
        SessionSilenceFilter.decode(rulesJSON)
    }

    private func mutateConfig(_ transform: (inout SilenceRuleConfig) -> Void) {
        var updated = SessionSilenceFilter.decode(rulesJSON)
        transform(&updated)
        rulesJSON = SessionSilenceFilter.encode(updated)
    }

    private func presetBinding(for preset: BuiltInSilencePreset) -> Binding<Bool> {
        Binding(
            get: { config.enabledPresets.contains(preset) },
            set: { desired in
                mutateConfig { cfg in
                    let current = cfg.enabledPresets.contains(preset)
                    if current != desired {
                        SessionSilenceFilter.togglePreset(preset, in: &cfg)
                    }
                }
            }
        )
    }

    private func addDirectory() {
        let trimmed = newDirectoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutateConfig { cfg in
            _ = SessionSilenceFilter.addBlockedDirectory(trimmed, to: &cfg)
        }
        newDirectoryInput = ""
    }

    private func addPromptPrefix() {
        let trimmed = newPromptInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutateConfig { cfg in
            _ = SessionSilenceFilter.addBlockedPromptPrefix(trimmed, to: &cfg)
        }
        newPromptInput = ""
    }

    var body: some View {
        let currentConfig = config

        FlowSettingsSection(
            title: settingsLocalized(l10n, "silence_section_title", fallback: "Silence Noise Sessions"),
            footer: settingsLocalized(
                l10n,
                "silence_section_desc",
                fallback: "Automatically hide background helper and memory-summary sessions from the island."
            )
        ) {
            // Built-in noise presets
            ForEach(Array(BuiltInSilencePreset.allCases.enumerated()), id: \.element.id) { idx, preset in
                if idx > 0 {
                    FlowSettingsDivider()
                }
                FlowSettingsToggleRow(
                    title: presetTitle(for: preset),
                    isOn: presetBinding(for: preset)
                )
            }

            FlowSettingsDivider()

            // Custom blocked directories
            FlowSettingsRow(verticalPadding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(settingsLocalized(l10n, "silence_blocked_dirs", fallback: "Blocked Directories"))
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        if !currentConfig.blockedDirectories.isEmpty {
                            FlowValuePill(text: "\(currentConfig.blockedDirectories.count)")
                        }
                    }

                    if !currentConfig.blockedDirectories.isEmpty {
                        VStack(spacing: 5) {
                            ForEach(currentConfig.blockedDirectories, id: \.self) { dir in
                                SilenceRuleItemRow(text: dir, scheme: scheme) {
                                    mutateConfig { cfg in
                                        SessionSilenceFilter.removeBlockedDirectory(dir, from: &cfg)
                                    }
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField(
                            settingsLocalized(
                                l10n,
                                "silence_blocked_dir_placeholder",
                                fallback: "~/path/to/ignore"
                            ),
                            text: $newDirectoryInput
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .onSubmit { addDirectory() }

                        Button(settingsLocalized(l10n, "silence_add", fallback: "Add")) {
                            addDirectory()
                        }
                        .controlSize(.small)
                        .disabled(newDirectoryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            FlowSettingsDivider()

            // Custom blocked prompt prefixes
            FlowSettingsRow(verticalPadding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(settingsLocalized(l10n, "silence_blocked_prompts", fallback: "Blocked Prompt Prefixes"))
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        if !currentConfig.blockedPromptPrefixes.isEmpty {
                            FlowValuePill(text: "\(currentConfig.blockedPromptPrefixes.count)")
                        }
                    }

                    if !currentConfig.blockedPromptPrefixes.isEmpty {
                        VStack(spacing: 5) {
                            ForEach(currentConfig.blockedPromptPrefixes, id: \.self) { prefix in
                                SilenceRuleItemRow(text: prefix, scheme: scheme) {
                                    mutateConfig { cfg in
                                        SessionSilenceFilter.removeBlockedPromptPrefix(prefix, from: &cfg)
                                    }
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField(
                            settingsLocalized(
                                l10n,
                                "silence_blocked_prompt_placeholder",
                                fallback: "## Memory Writing Agent"
                            ),
                            text: $newPromptInput
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .onSubmit { addPromptPrefix() }

                        Button(settingsLocalized(l10n, "silence_add", fallback: "Add")) {
                            addPromptPrefix()
                        }
                        .controlSize(.small)
                        .disabled(newPromptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func presetTitle(for preset: BuiltInSilencePreset) -> String {
        switch preset {
        case .codexChronicle:
            return settingsLocalized(
                l10n,
                "silence_preset_codexChronicle",
                fallback: "Codex Chronicle (Memory Summary)"
            )
        case .codexAppGitHelper:
            return settingsLocalized(
                l10n,
                "silence_preset_codexAppGitHelper",
                fallback: "Codex App Git Helper"
            )
        case .codexAppSuggestions:
            return settingsLocalized(
                l10n,
                "silence_preset_codexAppSuggestions",
                fallback: "Codex App Prompt Suggestions"
            )
        case .codexMemoryWriter:
            return settingsLocalized(
                l10n,
                "silence_preset_codexMemoryWriter",
                fallback: "Codex Memory Writer"
            )
        case .claudeMem:
            return settingsLocalized(
                l10n,
                "silence_preset_claudeMem",
                fallback: "Claude-Mem Background Observer"
            )
        }
    }
}

private struct SilenceRuleItemRow: View {
    let text: String
    let scheme: ColorScheme
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer(minLength: 6)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHovered ? Color.red.opacity(0.85) : Color.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(FlowSettingsPalette.valuePillFill(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(FlowSettingsPalette.valuePillBorder(scheme), lineWidth: 0.6)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
