import SwiftUI
import AppKit
import CodeIslandCore

// MARK: - Shortcuts Page

struct ShortcutsPage: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var recordingAction: ShortcutAction?
    @State private var eventMonitor: Any?
    @State private var refreshKey = 0

    var body: some View {
        FlowSettingsPageShell(page: .shortcuts, title: l10n["shortcuts"]) {
            FlowSettingsSection {
                ForEach(Array(ShortcutAction.allCases.enumerated()), id: \.element.id) { idx, action in
                    if idx > 0 { FlowSettingsDivider() }
                    FlowSettingsRow {
                        ShortcutRow(
                            action: action,
                            isRecording: recordingAction == action,
                            onStartRecording: { startRecording(action) },
                            onClear: { clearBinding(action) }
                        )
                        .id("\(action.rawValue)-\(refreshKey)")
                    }
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recordingAction = action
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape — cancel
                self.stopRecording()
                return nil
            }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.contains(.command) || mods.contains(.control) || mods.contains(.option) else {
                return nil
            }
            action.setBinding(keyCode: event.keyCode, modifiers: mods)
            if !action.isEnabled { action.setEnabled(true) }
            self.stopRecording()
            self.refreshKey += 1
            self.notifyChange()
            return nil
        }
    }

    private func clearBinding(_ action: ShortcutAction) {
        action.setEnabled(false)
        refreshKey += 1
        notifyChange()
    }

    private func stopRecording() {
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
            eventMonitor = nil
        }
        recordingAction = nil
    }

    private func notifyChange() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.setupGlobalShortcut()
        }
    }
}

private struct ShortcutRow: View {
    let action: ShortcutAction
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onClear: () -> Void
    @ObservedObject private var l10n = L10n.shared

    private var conflict: ShortcutAction? { action.conflictingAction() }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(l10n["shortcut_\(action.rawValue)"])
                    .font(.system(size: 13.5))
                Text(l10n["shortcut_\(action.rawValue)_desc"])
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                if let conflict {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("\(l10n["shortcut_conflict"]) \(l10n["shortcut_\(conflict.rawValue)"])")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                }
            }
            Spacer()
            if isRecording {
                Text(l10n["shortcut_recording"])
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).stroke(.orange, lineWidth: 1))
            } else if action.isEnabled {
                HStack(spacing: 6) {
                    Text(action.binding.displayString)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                        .onTapGesture { onStartRecording() }

                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(l10n["shortcut_none"])
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                    .onTapGesture { onStartRecording() }
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Remote Hosts Page

struct RemoteHostsPage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var remoteManager = RemoteManager.shared

    @State private var name = ""
    @State private var host = ""
    @State private var user = ""
    @State private var port = ""
    @State private var identityFile = ""
    @State private var authSocket = ""
    @State private var cwdFilter = ""
    @State private var autoConnect = false
    @State private var agentsRunAsOtherUsers = false

    var body: some View {
        FlowSettingsPageShell(page: .remote, title: l10n["remote"]) {
            FlowSettingsSection(title: l10n["remote_hosts"]) {
                if remoteManager.hosts.isEmpty {
                    FlowSettingsRow {
                        Text(l10n["remote_hosts_empty"])
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(Array(remoteManager.hosts.enumerated()), id: \.element.id) { idx, remoteHost in
                        if idx > 0 { FlowSettingsDivider() }
                        FlowSettingsRow {
                            RemoteHostRow(host: remoteHost)
                        }
                    }
                }
            }

            FlowSettingsSection(title: l10n["add_remote_host"], footer: l10n["remote_hint"]) {
                FlowSettingsRow {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(l10n["remote_name"], text: $name)
                            .textFieldStyle(.roundedBorder)
                        TextField(l10n["remote_host"], text: $host)
                            .textFieldStyle(.roundedBorder)
                        HStack(spacing: 8) {
                            TextField(l10n["remote_user"], text: $user)
                                .textFieldStyle(.roundedBorder)
                            TextField(l10n["remote_port"], text: $port)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                        }
                        TextField(l10n["remote_identity"], text: $identityFile)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        TextField(
                            l10n["remote_auth_socket"],
                            text: $authSocket,
                            prompt: Text(l10n["remote_auth_socket_placeholder"])
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        TextField(
                            l10n["remote_cwd_filter"],
                            text: $cwdFilter,
                            prompt: Text(l10n["remote_cwd_filter_placeholder"])
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        Text(l10n["remote_cwd_filter_hint"])
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                FlowSettingsDivider()
                FlowSettingsToggleRow(title: l10n["remote_auto_connect"], isOn: $autoConnect)
                FlowSettingsDivider()
                FlowSettingsToggleRow(
                    title: l10n["remote_other_users"],
                    subtitle: l10n["remote_other_users_hint"],
                    isOn: $agentsRunAsOtherUsers
                )

                FlowSettingsDivider()
                FlowSettingsRow {
                    HStack {
                        Spacer()
                        Button(l10n["remote_add_button"]) {
                            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmedName.isEmpty, !trimmedHost.isEmpty else { return }

                            remoteManager.addHost(RemoteHost(
                                name: trimmedName,
                                host: trimmedHost,
                                user: user.trimmingCharacters(in: .whitespacesAndNewlines),
                                port: Int(port.trimmingCharacters(in: .whitespacesAndNewlines)),
                                identityFile: identityFile.trimmingCharacters(in: .whitespacesAndNewlines),
                                autoConnect: autoConnect,
                                authSocket: authSocket.trimmingCharacters(in: .whitespacesAndNewlines),
                                cwdFilter: cwdFilter.trimmingCharacters(in: .whitespacesAndNewlines),
                                agentsRunAsOtherUsers: agentsRunAsOtherUsers
                            ))

                            name = ""
                            host = ""
                            user = ""
                            port = ""
                            identityFile = ""
                            authSocket = ""
                            cwdFilter = ""
                            autoConnect = false
                            agentsRunAsOtherUsers = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }
            }
        }
    }
}

private struct RemoteHostRow: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var remoteManager = RemoteManager.shared
    let host: RemoteHost

    @State private var cwdFilterDraft = ""

    private var status: SSHForwarder.Status {
        remoteManager.connectionStatus[host.id] ?? .disconnected
    }

    private var statusText: String {
        switch status {
        case .connected: return l10n["remote_connected"]
        case .connecting: return l10n["remote_connecting"]
        case .disconnected: return l10n["remote_disconnected"]
        case .failed(let message): return message
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.name)
                        .font(.system(size: 13.5, weight: .medium))
                    Text(host.displayAddress)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if remoteManager.installRunning[host.id] == true {
                    ProgressView().controlSize(.small)
                }
            }

            Text(statusText)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            if let message = remoteManager.lastMessage[host.id], !message.isEmpty {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(5)
                    .textSelection(.enabled)
                    .help(message)
            }

            TextField(
                l10n["remote_cwd_filter"],
                text: $cwdFilterDraft,
                prompt: Text(l10n["remote_cwd_filter_placeholder"])
            )
            .font(.system(size: 11.5, design: .monospaced))
            .textFieldStyle(.roundedBorder)
            .onAppear { cwdFilterDraft = host.cwdFilter }
            .onChange(of: host.cwdFilter) { _, newValue in cwdFilterDraft = newValue }
            .onSubmit { saveCwdFilter() }

            Toggle(l10n["remote_other_users"], isOn: Binding(
                get: { host.agentsRunAsOtherUsers },
                set: { newValue in
                    guard newValue != host.agentsRunAsOtherUsers else { return }
                    var updated = host
                    updated.agentsRunAsOtherUsers = newValue
                    remoteManager.updateHost(updated)
                }
            ))
            .font(.system(size: 11.5))
            .help(l10n["remote_other_users_hint"])

            HStack(spacing: 8) {
                switch status {
                case .connected, .connecting:
                    Button(l10n["remote_disconnect"]) {
                        remoteManager.disconnect(id: host.id)
                    }
                default:
                    Button(l10n["remote_connect"]) {
                        remoteManager.connect(id: host.id)
                    }
                    if remoteManager.wantsConnection(id: host.id) {
                        Button(l10n["remote_disconnect"]) {
                            remoteManager.disconnect(id: host.id)
                        }
                    }
                }

                Button(l10n["reinstall"]) {
                    remoteManager.reconnect(id: host.id)
                }

                Button(role: .destructive) {
                    remoteManager.removeHost(id: host.id)
                } label: {
                    Text(l10n["remote_remove"])
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private func saveCwdFilter() {
        let trimmed = cwdFilterDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != host.cwdFilter else { return }
        var updated = host
        updated.cwdFilter = trimmed
        remoteManager.updateHost(updated)
    }
}

// MARK: - Buddy Page

struct BuddyPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.esp32BridgeEnabled) private var enabled: Bool = SettingsDefaults.esp32BridgeEnabled
    @AppStorage(SettingsKey.esp32HeartbeatSeconds) private var heartbeat: Double = SettingsDefaults.esp32HeartbeatSeconds
    @AppStorage(SettingsKey.buddyScreenBrightnessPercent) private var brightness: Double = SettingsDefaults.buddyScreenBrightnessPercent
    @AppStorage(SettingsKey.buddyScreenOrientation) private var screenOrientation: String = SettingsDefaults.buddyScreenOrientation
    @AppStorage(SettingsKey.appleCompanionEnabled) private var appleCompanionEnabled: Bool = SettingsDefaults.appleCompanionEnabled
    @AppStorage(SettingsKey.appleCompanionHeartbeatSeconds) private var appleCompanionHeartbeat: Double = SettingsDefaults.appleCompanionHeartbeatSeconds
    @ObservedObject private var appleCompanion = AppleCompanionPublisher.shared
    @State private var refreshTick = 0

    private var bridge: ESP32BridgeManager { ESP32BridgeManager.shared }

    private var localizedPowerError: String {
        switch bridge.lastError {
        case "Bluetooth permission denied":
            return l10n["buddy_status_bluetooth_denied"]
        case "Bluetooth unsupported on this Mac":
            return l10n["buddy_status_bluetooth_unsupported"]
        case "Bluetooth is resetting":
            return l10n["buddy_status_bluetooth_resetting"]
        default:
            return l10n["buddy_status_bluetooth_off"]
        }
    }

    private var statusText: String {
        _ = refreshTick
        switch bridge.status {
        case .off: return l10n["buddy_status_disabled"]
        case .poweredOff: return localizedPowerError
        case .noSelection: return l10n["buddy_status_no_selection"]
        case .scanning: return l10n["buddy_status_scanning"]
        case .searchingSelected: return l10n["buddy_status_searching_selected"]
        case .connecting: return l10n["buddy_status_connecting"]
        case .pairing: return l10n["buddy_status_pairing"]
        case .pairWaitingConfirm: return l10n["buddy_status_pair_waiting_confirm"]
        case .pairRejected: return l10n["buddy_status_pair_rejected"]
        case .connected: return l10n["buddy_status_connected"]
        case .reconnecting(let s): return String(format: l10n["buddy_status_reconnecting"], s)
        }
    }

    private var statusColor: Color {
        _ = refreshTick
        switch bridge.status {
        case .connected: return .green
        case .scanning, .connecting, .searchingSelected, .pairing: return .orange
        case .pairWaitingConfirm: return .blue
        case .reconnecting: return .yellow
        case .off, .noSelection: return .secondary
        case .poweredOff, .pairRejected: return .red
        }
    }

    private func configurePublisher() {
        ESP32StatePublisher.shared.configure(
            enabled: enabled,
            heartbeatSeconds: heartbeat,
            brightnessPercent: brightness,
            screenOrientation: BuddyScreenOrientation(settingsValue: screenOrientation)
        )
    }

    private func configureAppleCompanion() {
        AppleCompanionPublisher.shared.configure(
            enabled: appleCompanionEnabled,
            heartbeatSeconds: appleCompanionHeartbeat
        )
    }

    var body: some View {
        FlowSettingsPageShell(page: .buddy, title: l10n["buddy"]) {
            FlowSettingsSection(title: l10n["buddy"]) {
                FlowSettingsToggleRow(title: l10n["buddy_enable_bluetooth"], isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        configurePublisher()
                    }

                FlowSettingsDivider()
                FlowSettingsRow {
                    HStack {
                        Text(l10n["buddy_connection_status"])
                            .font(.system(size: 13.5))
                        Spacer()
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                if bridge.status == .pairWaitingConfirm {
                    FlowSettingsDivider()
                    FlowSettingsRow {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.tap.fill")
                                .foregroundStyle(.blue)
                            Text(l10n["buddy_pair_confirm_hint"])
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }

                if bridge.status == .pairRejected {
                    FlowSettingsDivider()
                    FlowSettingsRow {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(l10n["buddy_pair_rejected_hint"])
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                if bridge.usesLegacyPairingFallback {
                    FlowSettingsDivider()
                    FlowSettingsRow {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text(l10n["buddy_legacy_firmware_hint"])
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                FlowSettingsDivider()
                FlowSettingsRow {
                    Button {
                        bridge.stop()
                        if enabled { bridge.start() }
                    } label: {
                        Label(l10n["buddy_reconnect"], systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!enabled || bridge.selectedBuddyIdentifier == nil)
                }
            }

            FlowSettingsSection(title: l10n["buddy_select_section"]) {
                if let selectedId = bridge.selectedBuddyIdentifier {
                    FlowSettingsRow {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l10n["buddy_selected_label"])
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(bridge.connectedPeripheralName ?? bridge.selectedBuddyName ?? selectedId.uuidString)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                bridge.forgetSelection()
                            } label: {
                                Text(l10n["buddy_forget"])
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    FlowSettingsDivider()
                }

                ForEach(Array(bridge.discovered.enumerated()), id: \.element.id) { idx, device in
                    if idx > 0 { FlowSettingsDivider() }
                    FlowSettingsRow {
                        Button {
                            bridge.select(buddyId: device.id)
                        } label: {
                            HStack {
                                Image(systemName: device.id == bridge.selectedBuddyIdentifier
                                    ? "largecircle.fill.circle"
                                    : "circle")
                                    .foregroundStyle(device.id == bridge.selectedBuddyIdentifier ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.system(size: 13))
                                    Text("\(l10n["buddy_signal"]) \(device.rssi) dBm")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                Spacer()
                                Image(systemName: rssiIconName(device.rssi))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if bridge.discovered.isEmpty {
                    FlowSettingsRow {
                        Text(l10n["buddy_no_devices"])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                FlowSettingsDivider()
                FlowSettingsRow {
                    HStack {
                        Button {
                            bridge.stopDiscovery()
                            bridge.startDiscovery()
                        } label: {
                            Label(l10n["buddy_refresh"], systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!enabled)
                        Spacer()
                        if bridge.status == .scanning {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(l10n["buddy_scanning"])
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            FlowSettingsSection(title: l10n["buddy_sync"]) {
                FlowSettingsSliderRow(
                    title: l10n["buddy_sync_interval"],
                    subtitle: l10n["buddy_sync_desc"],
                    valueText: String(format: l10n["buddy_seconds_format"], heartbeat),
                    value: $heartbeat,
                    range: 1...30,
                    step: 1,
                    tickCount: 10
                )
                .onChange(of: heartbeat) { _, _ in
                    configurePublisher()
                }
            }

            FlowSettingsSection(title: l10n["buddy_display"]) {
                FlowSettingsSliderRow(
                    title: l10n["buddy_brightness"],
                    subtitle: l10n["buddy_brightness_desc"],
                    valueText: "\(Int(brightness.rounded()))%",
                    value: $brightness,
                    range: Double(ESP32Protocol.minBrightnessPercent)...Double(ESP32Protocol.maxBrightnessPercent),
                    step: 1,
                    tickCount: 11
                )
                .onChange(of: brightness) { _, newValue in
                    brightness = Double(ESP32Protocol.clampedBrightnessPercent(newValue))
                    configurePublisher()
                }

                FlowSettingsDivider()
                FlowSettingsRow {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(l10n["buddy_screen_orientation"])
                                .font(.system(size: 13.5))
                            Spacer()
                            Picker("", selection: $screenOrientation) {
                                Text(l10n["buddy_screen_orientation_up"]).tag(BuddyScreenOrientation.up.rawValue)
                                Text(l10n["buddy_screen_orientation_down"]).tag(BuddyScreenOrientation.down.rawValue)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 200)
                            .onChange(of: screenOrientation) { _, _ in
                                configurePublisher()
                            }
                        }
                        Text(l10n["buddy_screen_orientation_desc"])
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            FlowSettingsSection(title: l10n["apple_companion"], footer: l10n["buddy_desc"]) {
                FlowSettingsToggleRow(title: l10n["apple_companion_enable"], isOn: $appleCompanionEnabled)
                    .onChange(of: appleCompanionEnabled) { _, _ in
                        configureAppleCompanion()
                    }

                FlowSettingsDivider()
                FlowSettingsRow {
                    HStack {
                        Text(l10n["apple_companion_status"])
                            .font(.system(size: 13.5))
                        Spacer()
                        Circle()
                            .fill(appleCompanionStatusColor)
                            .frame(width: 8, height: 8)
                        Text(appleCompanionStatusText)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                }

                FlowSettingsDivider()
                FlowSettingsRow {
                    VStack(alignment: .leading, spacing: 6) {
                        if appleCompanion.connectedPeerNames.isEmpty {
                            Label(l10n["apple_companion_no_devices"], systemImage: "iphone")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(appleCompanion.connectedPeerNames, id: \.self) { name in
                                Label(name, systemImage: "iphone")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                FlowSettingsDivider()
                FlowSettingsSliderRow(
                    title: l10n["apple_companion_sync_interval"],
                    valueText: String(format: l10n["buddy_seconds_format"], appleCompanionHeartbeat),
                    value: $appleCompanionHeartbeat,
                    range: 1...30,
                    step: 1,
                    tickCount: 10,
                    disabled: !appleCompanionEnabled
                )
                .onChange(of: appleCompanionHeartbeat) { _, _ in
                    configureAppleCompanion()
                }

                FlowSettingsDivider()
                FlowSettingsRow {
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            appleCompanion.reconnect()
                        } label: {
                            Label(l10n["apple_companion_restart"], systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!appleCompanionEnabled)

                        if let error = appleCompanion.lastError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Text(l10n["apple_companion_desc"])
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Text(l10n["apple_companion_read_only"])
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            refreshTick &+= 1
        }
        .onAppear {
            if enabled {
                bridge.startDiscovery()
            }
        }
        .onDisappear {
            bridge.stopDiscovery()
        }
        .onChange(of: enabled) { _, newValue in
            if newValue {
                bridge.startDiscovery()
            } else {
                bridge.stopDiscovery()
            }
        }
    }

    private func rssiIconName(_ rssi: Int) -> String {
        switch rssi {
        case ..<(-85): return "wifi.exclamationmark"
        case ..<(-70): return "wifi"
        default: return "wifi"
        }
    }

    private var appleCompanionStatusText: String {
        guard appleCompanion.enabled else {
            return l10n["apple_companion_status_off"]
        }
        return appleCompanion.connectedPeerNames.isEmpty
            ? l10n["apple_companion_status_waiting"]
            : l10n["apple_companion_status_connected"]
    }

    private var appleCompanionStatusColor: Color {
        guard appleCompanion.enabled else { return .secondary }
        return appleCompanion.connectedPeerNames.isEmpty ? .orange : .green
    }
}
