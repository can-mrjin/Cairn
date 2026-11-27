import SwiftUI
import AppKit

/// Hooks-page section for Claude Desktop's Cowork / local Chat sessions. They
/// have no hook to install — the toggle only starts or stops the read-only
/// session-store watcher (AppState+CoworkWatch).
struct ClaudeDesktopCoworkSection: View {
    var appState: AppState?
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.trackClaudeDesktopCowork)
    private var trackCowork = SettingsDefaults.trackClaudeDesktopCowork

    var body: some View {
        FlowSettingsSection(title: "Claude Desktop") {
            FlowSettingsRow {
                HStack(alignment: .top, spacing: 10) {
                    if let icon = claudeDesktopIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 22, height: 22)
                            .padding(.top, 1)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l10n["cowork_tracking_toggle"])
                            .font(.system(size: 13.5))
                        Text(l10n["cowork_tracking_desc"])
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Toggle("", isOn: $trackCowork)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: trackCowork) { _, enabled in
                            if enabled {
                                appState?.startCoworkWatcher()
                            } else {
                                appState?.stopCoworkWatcher()
                            }
                        }
                }
            }
        }
    }

    private var claudeDesktopIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: AppState.claudeDesktopBundleId
        ) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
