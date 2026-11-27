import SwiftUI
import AppKit
import CodeIslandCore

// MARK: - General Page

struct GeneralPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.displayChoice) private var displayChoice = SettingsDefaults.displayChoice
    @AppStorage(SettingsKey.allowHorizontalDrag) private var allowHorizontalDrag = SettingsDefaults.allowHorizontalDrag
    @AppStorage(SettingsKey.avoidMenuBarIcons) private var avoidMenuBarIcons = SettingsDefaults.avoidMenuBarIcons
    @AppStorage(SettingsKey.hoverToExpand) private var hoverToExpand = SettingsDefaults.hoverToExpand
    @AppStorage(SettingsKey.hoverExpandDelay) private var hoverExpandDelay = SettingsDefaults.hoverExpandDelay
    @AppStorage(SettingsKey.smartSuppress) private var smartSuppress = SettingsDefaults.smartSuppress
    @AppStorage(SettingsKey.collapseOnMouseLeave) private var collapseOnMouseLeave = SettingsDefaults.collapseOnMouseLeave
    @State private var launchAtLogin: Bool

    init() {
        _launchAtLogin = State(initialValue: SettingsManager.shared.launchAtLogin)
    }

    /// The stored choice as the picker's rows name it: a pin saved as a
    /// screen index selects its display's row.
    private var displayChoiceSelection: Binding<String> {
        Binding(
            get: {
                DisplayChoice.pickerSelection(
                    displayChoice, displayUUIDs: NSScreen.screens.map(ScreenDetector.displayUUID(for:))
                )
            },
            set: { displayChoice = $0 }
        )
    }

    var body: some View {
        FlowSettingsPageShell(page: .general, title: l10n["general"]) {
            FlowSettingsSection {
                FlowSettingsPickerRow(title: l10n["language"], selection: $l10n.language) {
                    Text(l10n["system_language"]).tag("system")
                    Text("English").tag("en")
                    Text("简体中文").tag("zh")
                    Text("繁體中文").tag("zh-Hant")
                    Text("Deutsch").tag("de")
                    Text("日本語").tag("ja")
                    Text("한국어").tag("ko")
                    Text("Türkçe").tag("tr")
                }

                FlowSettingsDivider()

                FlowSettingsToggleRow(title: l10n["launch_at_login"], isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in
                        SettingsManager.shared.launchAtLogin = v
                    }
            }

            FlowSettingsSection(title: l10n["expand_and_collapse"]) {
                FlowSettingsToggleRow(
                    title: l10n["hover_to_expand"],
                    subtitle: l10n["hover_to_expand_desc"],
                    isOn: $hoverToExpand
                )

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
                    tickCount: 10,
                    disabled: !hoverToExpand
                )

                FlowSettingsDivider()

                FlowSettingsToggleRow(
                    title: l10n["smart_suppress"],
                    subtitle: l10n["smart_suppress_desc"],
                    isOn: $smartSuppress
                )

                FlowSettingsDivider()

                FlowSettingsToggleRow(
                    title: l10n["collapse_on_mouse_leave"],
                    subtitle: l10n["collapse_on_mouse_leave_desc"],
                    isOn: $collapseOnMouseLeave
                )
            }

            FlowSettingsSection(title: l10n["display"]) {
                FlowSettingsPickerRow(title: l10n["display"], selection: displayChoiceSelection) {
                    let uuids = NSScreen.screens.map(ScreenDetector.displayUUID(for:))
                    Text(l10n["auto"]).tag(DisplayChoice.auto)
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        let name = screen.localizedName
                        let isBuiltin = name.contains("Built-in") || name.contains("内置")
                        let label = isBuiltin ? l10n["builtin_display"] : name
                        Text(label).tag(DisplayChoice.tag(forDisplayAt: index, displayUUIDs: uuids))
                    }
                    // The pin stays while its display is away; so does its row.
                    if DisplayChoice.resolve(displayChoice, displayUUIDs: uuids) == .pinnedDisplayMissing {
                        Text(l10n["display_not_connected"]).tag(displayChoice)
                    }
                }

                FlowSettingsDivider()

                FlowSettingsToggleRow(
                    title: l10n["allow_horizontal_drag"],
                    subtitle: l10n["allow_horizontal_drag_desc"],
                    isOn: $allowHorizontalDrag
                )
                .onChange(of: allowHorizontalDrag) { _, enabled in
                    if !enabled {
                        SettingsManager.shared.panelHorizontalOffset = 0
                    }
                }

                FlowSettingsDivider()

                FlowSettingsToggleRow(
                    title: l10n["avoid_menu_bar_icons"],
                    subtitle: l10n["avoid_menu_bar_icons_desc"],
                    isOn: $avoidMenuBarIcons
                )
            }
        }
    }
}

// MARK: - Hooks Page

struct HooksPage: View {
    var appState: AppState?
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var socketHealth = HookSocketHealth.shared
    @State private var cliStatuses: [String: Bool] = [:]
    @State private var statusMessage = ""
    @State private var statusIsError = false
    @State private var refreshKey = 0
    @State private var customName = ""
    @State private var customSource = ""
    @State private var customConfigPath = ""
    @State private var customConfigKey = "hooks"
    @State private var customFormat: HookFormat = .claude
    @State private var extraDirStatuses: [ExtraConfigDirStatus] = []
    @State private var newExtraDirCLI: ConfigDirCLI = .claude
    @State private var newExtraDirPath = ""
    @State private var extraDirMessage = ""
    @State private var extraDirMessageIsError = false

    private func refreshCLIStatuses() {
        for cli in ConfigInstaller.allCLIs {
            cliStatuses[cli.source] = ConfigInstaller.isInstalled(source: cli.source)
        }
        cliStatuses["opencode"] = ConfigInstaller.isInstalled(source: "opencode")
        cliStatuses["mimo"] = ConfigInstaller.isInstalled(source: "mimo")
        cliStatuses["aiwork"] = ConfigInstaller.isInstalled(source: "aiwork")
        cliStatuses["aiwork-cli"] = ConfigInstaller.isInstalled(source: "aiwork-cli")
        extraDirStatuses = ConfigInstaller.extraConfigDirStatuses()
    }

    // MARK: Extra config directories

    private func addExtraConfigDir() {
        let cli = newExtraDirCLI
        switch ConfigInstaller.addExtraConfigDir(cli: cli, rawPath: newExtraDirPath) {
        case .failure(let error):
            extraDirMessage = ExtraConfigDirText.error(error, cli: cli, l10n: l10n)
            extraDirMessageIsError = true
        case .success(let added):
            extraDirMessage = ExtraConfigDirText.added(added.dir, outcome: added.outcome, l10n: l10n)
            extraDirMessageIsError = added.outcome == .failed
            newExtraDirPath = ""
            // Its session store joins the discovery watcher, and sessions
            // already running under it show up without waiting for a hook.
            appState?.restartProjectsWatcher()
        }
        refreshCLIStatuses()
    }

    private func removeExtraConfigDir(_ status: ExtraConfigDirStatus) {
        if let removed = ConfigInstaller.removeExtraConfigDir(id: status.id) {
            extraDirMessage = String(format: l10n["extra_config_dirs_removed"], ClaudeConfigPaths.displayPath(removed.path))
            extraDirMessageIsError = false
            appState?.restartProjectsWatcher()
        }
        refreshCLIStatuses()
    }

    private func setExtraConfigDir(_ status: ExtraConfigDirStatus, enabled: Bool) {
        if let outcome = ConfigInstaller.setExtraConfigDirEnabled(id: status.id, enabled: enabled),
           outcome == .failed {
            extraDirMessage = String(format: l10n["extra_config_dirs_write_failed"], status.displayConfigPath)
            extraDirMessageIsError = true
        }
        appState?.restartProjectsWatcher()
        refreshCLIStatuses()
    }

    /// Config dirs are dot-directories, so the panel shows hidden files.
    private func chooseExtraConfigDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        panel.message = String(format: l10n["extra_config_dirs_panel_message"], newExtraDirCLI.displayName)
        panel.prompt = l10n["extra_config_dirs_choose_prompt"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        newExtraDirPath = ClaudeConfigPaths.displayPath(url.path)
    }

    private func applySourceToggle(source: String, enabled: Bool) {
        if source == "aiwork" || source == "aiwork-cli" {
            if enabled {
                appState?.startAiWorkWatcher()
            } else {
                appState?.removeAiWorkSessions(source: source)
                if !ConfigInstaller.isAnyAiWorkMonitoringEnabled() {
                    appState?.stopAiWorkWatcher()
                } else {
                    appState?.pruneDisabledAiWorkSessions()
                }
            }
        }
        refreshCLIStatuses()
    }

    var body: some View {
        FlowSettingsPageShell(page: .hooks, title: l10n["hooks"]) {
            if let problem = socketHealth.problem {
                FlowSettingsSection {
                    FlowSettingsRow {
                        HookSocketProblemRow(problem: problem) { socketHealth.retryIfDown() }
                    }
                }
            }

            FlowSettingsSection(title: l10n["cli_status"]) {
                ForEach(Array(ConfigInstaller.allCLIs.enumerated()), id: \.element.source) { idx, cli in
                    if idx > 0 {
                        FlowSettingsDivider()
                    }
                    let installed = cliStatuses[cli.source] ?? false
                    let exists = ConfigInstaller.cliExists(source: cli.source)
                    FlowSettingsRow(verticalPadding: 9) {
                        CLIStatusRow(
                            name: cli.name,
                            source: cli.source,
                            configPath: cli.displayConfigPath,
                            fullPath: cli.fullPath,
                            installed: installed,
                            exists: exists
                        ) { enabled in applySourceToggle(source: cli.source, enabled: enabled) }
                        .id("\(cli.source)-\(refreshKey)")
                    }
                    // Extra config roots of this CLI, each with its own status.
                    ForEach(extraDirStatuses.filter { $0.dir.cli.source == cli.source }) { status in
                        FlowSettingsDivider(leadingInset: 38)
                        FlowSettingsRow(verticalPadding: 8) {
                            ExtraConfigDirRow(
                                status: status,
                                onToggle: { setExtraConfigDir(status, enabled: $0) },
                                onRemove: { removeExtraConfigDir(status) }
                            )
                        }
                    }
                }

                // OpenCode (plugin-based, not hooks)
                FlowSettingsDivider()
                FlowSettingsRow(verticalPadding: 9) {
                    CLIStatusRow(
                        name: "OpenCode",
                        source: "opencode",
                        configPath: "~/.config/opencode/config.json",
                        fullPath: NSHomeDirectory() + "/.config/opencode/config.json",
                        installed: cliStatuses["opencode"] ?? false,
                        exists: ConfigInstaller.cliExists(source: "opencode")
                    ) { enabled in applySourceToggle(source: "opencode", enabled: enabled) }
                    .id("opencode-\(refreshKey)")
                }

                // MiMo Code CLI + Xiaomi MiMo desktop (one plugin, auto-loaded)
                FlowSettingsDivider()
                FlowSettingsRow(verticalPadding: 9) {
                    CLIStatusRow(
                        name: "MiMo Code / Xiaomi MiMo",
                        source: "mimo",
                        configPath: "~/.config/mimocode/plugins/codeisland.js",
                        fullPath: ConfigInstaller.mimoPluginPath(),
                        installed: cliStatuses["mimo"] ?? false,
                        exists: ConfigInstaller.cliExists(source: "mimo")
                    ) { enabled in applySourceToggle(source: "mimo", enabled: enabled) }
                    .id("mimo-\(refreshKey)")
                }

                // AiWork GUI + CLI/TUI (Agentix daemon watch — no hooks)
                FlowSettingsDivider()
                FlowSettingsRow(verticalPadding: 9) {
                    CLIStatusRow(
                        name: "AiWork",
                        source: "aiwork",
                        configPath: ConfigInstaller.aiworkDisplayConfigPath,
                        fullPath: ConfigInstaller.aiworkFullConfigPath,
                        installed: cliStatuses["aiwork"] ?? false,
                        exists: ConfigInstaller.cliExists(source: "aiwork")
                    ) { enabled in applySourceToggle(source: "aiwork", enabled: enabled) }
                    .id("aiwork-\(refreshKey)")
                }

                FlowSettingsDivider()
                FlowSettingsRow(verticalPadding: 9) {
                    CLIStatusRow(
                        name: "AiWork CLI",
                        source: "aiwork-cli",
                        configPath: ConfigInstaller.aiworkCliDisplayConfigPath,
                        fullPath: ConfigInstaller.aiworkFullConfigPath,
                        installed: cliStatuses["aiwork-cli"] ?? false,
                        exists: ConfigInstaller.cliExists(source: "aiwork-cli")
                    ) { enabled in applySourceToggle(source: "aiwork-cli", enabled: enabled) }
                    .id("aiwork-cli-\(refreshKey)")
                }
            }

            ClaudeDesktopCoworkSection(appState: appState)

            FlowSettingsSection(title: l10n["extra_config_dirs_title"], footer: l10n["extra_config_dirs_desc"]) {
                FlowSettingsRow {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Picker("", selection: $newExtraDirCLI) {
                                ForEach(ConfigDirCLI.allCases, id: \.self) { cli in
                                    Text(cli.displayName).tag(cli)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()

                            TextField(
                                "",
                                text: $newExtraDirPath,
                                prompt: Text(String(format: l10n["extra_config_dirs_placeholder"], newExtraDirCLI.environmentKey))
                            )
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .autocorrectionDisabled(true)
                            .onSubmit(addExtraConfigDir)

                            Button(l10n["extra_config_dirs_choose"], action: chooseExtraConfigDir)
                            Button(l10n["extra_config_dirs_add"], action: addExtraConfigDir)
                                .disabled(newExtraDirPath.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        if !extraDirMessage.isEmpty {
                            HStack(alignment: .top, spacing: 5) {
                                Image(systemName: extraDirMessageIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(extraDirMessageIsError ? .red : .green)
                                Text(extraDirMessage)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            FlowSettingsSection(title: "Custom CLIs") {
                let customItems = ConfigInstaller.customCLIConfigs()
                if customItems.isEmpty {
                    FlowSettingsRow {
                        Text("No custom CLI configured")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(Array(customItems.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 { FlowSettingsDivider() }
                        FlowSettingsRow {
                            HStack(alignment: .center, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.system(size: 13.5))
                                    Text("\(item.source) · \(item.configPath)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    _ = ConfigInstaller.setEnabled(source: item.source, enabled: false)
                                    _ = ConfigInstaller.removeCustomCLI(source: item.source)
                                    refreshCLIStatuses()
                                    refreshKey += 1
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                FlowSettingsDivider()

                FlowSettingsRow {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Name (e.g. MyTool)", text: $customName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Source (e.g. mytool)", text: $customSource)
                            .textFieldStyle(.roundedBorder)
                        TextField("Config path (e.g. .mytool/settings.json)", text: $customConfigPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        TextField("Config key", text: $customConfigKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        HStack {
                            Text("Template")
                                .font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $customFormat) {
                                Text("Claude").tag(HookFormat.claude)
                                Text("Codex/Gemini").tag(HookFormat.nested)
                                Text("Cursor").tag(HookFormat.flat)
                                Text("Copilot").tag(HookFormat.copilot)
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        HStack {
                            Spacer()
                            Button("Add Custom CLI") {
                                let result = ConfigInstaller.addCustomCLI(
                                    name: customName,
                                    source: customSource,
                                    configPath: customConfigPath,
                                    format: customFormat,
                                    configKey: customConfigKey
                                )
                                statusMessage = result.message
                                statusIsError = !result.ok
                                guard result.ok else { return }

                                let normalizedSource = customSource
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .lowercased()
                                _ = ConfigInstaller.setEnabled(source: normalizedSource, enabled: true)
                                customName = ""
                                customSource = ""
                                customConfigPath = ""
                                customConfigKey = "hooks"
                                customFormat = .claude
                                refreshCLIStatuses()
                                refreshKey += 1
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                    }
                }
            }

            FlowSettingsSection(title: l10n["management"]) {
                FlowSettingsRow {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Button {
                                for cli in ConfigInstaller.allCLIs where ConfigInstaller.cliExists(source: cli.source) {
                                    UserDefaults.standard.set(true, forKey: "cli_enabled_\(cli.source)")
                                }
                                if ConfigInstaller.cliExists(source: "opencode") {
                                    UserDefaults.standard.set(true, forKey: "cli_enabled_opencode")
                                }
                                if ConfigInstaller.cliExists(source: "mimo") {
                                    UserDefaults.standard.set(true, forKey: "cli_enabled_mimo")
                                }
                                if ConfigInstaller.cliExists(source: "aiwork") {
                                    UserDefaults.standard.set(true, forKey: "cli_enabled_aiwork")
                                }
                                if ConfigInstaller.cliExists(source: "aiwork-cli") {
                                    UserDefaults.standard.set(true, forKey: "cli_enabled_aiwork-cli")
                                }
                                if ConfigInstaller.install() {
                                    if ConfigInstaller.isAnyAiWorkMonitoringEnabled() {
                                        appState?.startAiWorkWatcher()
                                    }
                                    refreshCLIStatuses()
                                    refreshKey += 1
                                    statusMessage = l10n["hooks_installed"]
                                    statusIsError = false
                                } else {
                                    statusMessage = l10n["install_failed"]
                                    statusIsError = true
                                }
                            } label: {
                                Text(l10n["reinstall"])
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button(role: .destructive) {
                                for cli in ConfigInstaller.allCLIs {
                                    UserDefaults.standard.set(false, forKey: "cli_enabled_\(cli.source)")
                                }
                                UserDefaults.standard.set(false, forKey: "cli_enabled_opencode")
                                UserDefaults.standard.set(false, forKey: "cli_enabled_mimo")
                                UserDefaults.standard.set(false, forKey: "cli_enabled_aiwork")
                                UserDefaults.standard.set(false, forKey: "cli_enabled_aiwork-cli")
                                appState?.stopAiWorkWatcher()
                                ConfigInstaller.uninstall()
                                refreshCLIStatuses()
                                refreshKey += 1
                                statusMessage = l10n["hooks_uninstalled"]
                                statusIsError = false
                            } label: {
                                Text(l10n["uninstall"])
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }

                        if !statusMessage.isEmpty {
                            HStack(spacing: 5) {
                                Image(systemName: statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(statusIsError ? .red : .green)
                                Text(statusMessage)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { refreshCLIStatuses() }
    }
}

// MARK: - Extra Config Dir Row & Text

/// One extra config root, listed under its CLI in "CLI status": where it is,
/// whether its hooks are in, and — when they cannot be — why.
private struct ExtraConfigDirRow: View {
    @ObservedObject private var l10n = L10n.shared
    let status: ExtraConfigDirStatus
    let onToggle: (Bool) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(ClaudeConfigPaths.displayPath(status.dir.path))
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(status.dir.path)
                detail
            }
            Spacer()
            Toggle("", isOn: Binding(get: { status.dir.enabled }, set: onToggle))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!status.sourceEnabled || status.sameAsPrimary)
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(l10n["extra_config_dirs_remove_help"])
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let problem = ExtraConfigDirText.statusProblem(status, l10n: l10n) {
            HStack(alignment: .top, spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(problem)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11))
        } else if let note = ExtraConfigDirText.statusNote(status, l10n: l10n) {
            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 3) {
                Text(status.displayConfigPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: status.fullConfigPath)])
                } label: {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

enum ExtraConfigDirText {
    static func inspection(_ inspection: ConfigDirInspection, cli: ConfigDirCLI, l10n: L10n) -> String? {
        switch inspection {
        case .ready:
            return nil
        case .missing:
            return l10n["extra_dir_missing"]
        case .notADirectory:
            return l10n["extra_dir_not_directory"]
        case .unrecognized:
            return String(format: l10n["extra_dir_unrecognized"], cli.displayName, cli.environmentKey)
        case .belongsTo(let other):
            return String(format: l10n["extra_dir_belongs_to"], other.displayName, cli.displayName)
        }
    }

    static func error(_ error: ExtraConfigDirError, cli: ConfigDirCLI, l10n: L10n) -> String {
        switch error {
        case .invalidPath:
            return l10n["extra_dir_invalid_path"]
        case .isPrimary:
            return String(format: l10n["extra_dir_is_primary"], cli.displayName)
        case .isHomeDirectory:
            return String(format: l10n["extra_dir_is_home"], cli.environmentKey)
        case .containsPrimary(let primary):
            return String(
                format: l10n["extra_dir_contains_primary"],
                cli.displayName, ClaudeConfigPaths.displayPath(primary)
            )
        case .duplicate:
            return l10n["extra_dir_duplicate"]
        case .unusable(let inspection):
            return self.inspection(inspection, cli: cli, l10n: l10n) ?? l10n["extra_dir_invalid_path"]
        }
    }

    static func added(_ dir: ExtraConfigDir, outcome: ExtraConfigDirInstallOutcome, l10n: L10n) -> String {
        let path = ClaudeConfigPaths.displayPath(dir.path)
        switch outcome {
        case .installed:
            return String(format: l10n["extra_config_dirs_added"], path)
        case .sourceDisabled:
            return String(format: l10n["extra_config_dirs_added_source_off"], path, dir.cli.displayName)
        case .skipped(let inspection):
            let reason = self.inspection(inspection, cli: dir.cli, l10n: l10n) ?? ""
            return String(format: l10n["extra_config_dirs_added_skipped"], path, reason)
        case .shared(let owner):
            let file = ConfigInstaller.extraConfigDirCLI(for: dir)?.configPath ?? ""
            return String(
                format: l10n["extra_config_dirs_added_shared"],
                path, file, ClaudeConfigPaths.displayPath(owner)
            )
        case .failed:
            let configPath = ConfigInstaller.extraConfigDirCLI(for: dir)?.displayConfigPath ?? path
            return String(format: l10n["extra_config_dirs_write_failed"], configPath)
        }
    }

    /// Why a registered root has no hooks right now, if something is wrong.
    static func statusProblem(_ status: ExtraConfigDirStatus, l10n: L10n) -> String? {
        guard status.sourceEnabled, status.dir.enabled, !status.sameAsPrimary else { return nil }
        if let reason = inspection(status.inspection, cli: status.dir.cli, l10n: l10n) {
            return String(format: l10n["extra_dir_hooks_skipped"], reason)
        }
        return nil
    }

    /// Neutral state line (same as the main dir, paused, CLI off, hooks file
    /// shared with another root, not installed yet); nil when the hooks are
    /// in and the row shows the config file instead.
    static func statusNote(_ status: ExtraConfigDirStatus, l10n: L10n) -> String? {
        if status.sameAsPrimary {
            return String(format: l10n["extra_dir_same_as_primary"], status.dir.cli.displayName)
        }
        if !status.sourceEnabled {
            return String(format: l10n["extra_dir_source_off"], status.dir.cli.displayName)
        }
        if !status.dir.enabled { return l10n["extra_dir_paused"] }
        if let owner = status.sharedHooksWith {
            let file = String(status.fullConfigPath.dropFirst(status.dir.path.count + 1))
            return String(format: l10n["extra_dir_shared_hooks"], file, ClaudeConfigPaths.displayPath(owner))
        }
        if !status.hooksInstalled { return l10n["not_installed"] }
        return nil
    }
}

// MARK: - CLI Status Row

private struct CLIStatusRow: View {
    @ObservedObject private var l10n = L10n.shared
    let name: String
    let source: String
    let configPath: String
    let fullPath: String
    let installed: Bool
    let exists: Bool
    var onToggle: ((Bool) -> Void)?

    @State private var enabled: Bool

    init(
        name: String,
        source: String,
        configPath: String,
        fullPath: String,
        installed: Bool,
        exists: Bool,
        onToggle: ((Bool) -> Void)? = nil
    ) {
        self.name = name
        self.source = source
        self.configPath = configPath
        self.fullPath = fullPath
        self.installed = installed
        self.exists = exists
        self.onToggle = onToggle
        _enabled = State(initialValue: ConfigInstaller.isEnabled(source: source))
    }

    var body: some View {
        HStack(spacing: 10) {
            if let icon = cliIcon(source: source, size: 22) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13.5))
                if !exists {
                    Text(l10n["not_detected"])
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                } else if installed {
                    HStack(spacing: 3) {
                        Text(configPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: fullPath)])
                        } label: {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 12)
            if exists {
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: enabled) { _, newValue in
                        ConfigInstaller.setEnabled(source: source, enabled: newValue)
                        onToggle?(newValue)
                    }
            }
        }
    }
}
