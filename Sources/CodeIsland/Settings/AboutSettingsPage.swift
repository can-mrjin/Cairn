import SwiftUI
import AppKit
import CodeIslandCore

// MARK: - About Page

struct AboutPage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var updater = UpdateChecker.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        FlowSettingsPageShell(page: .about, title: l10n["about"]) {
            FlowSettingsSection {
                FlowSettingsRow(verticalPadding: 22) {
                    VStack(spacing: 18) {
                        AppLogoView(size: 96)

                        VStack(spacing: 6) {
                            Text("FlowIsland")
                                .font(.system(size: 24, weight: .bold))
                            FlowValuePill(text: "Version \(AppVersion.current)")
                        }

                        VStack(spacing: 4) {
                            Text(l10n["about_desc1"])
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Text(String(format: l10n["about_desc2"], ConfigInstaller.builtInIntegrationCount))
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }

                        HStack(spacing: 10) {
                            aboutLink(
                                "GitHub",
                                icon: "chevron.left.forwardslash.chevron.right",
                                url: ReleaseNotesLink.repositoryURL
                            )
                            aboutLink(
                                "Issues",
                                icon: "ladybug",
                                url: ReleaseNotesLink.repositoryURL + "/issues"
                            )
                            aboutLink(
                                String(format: l10n["release_notes_for_version"], AppVersion.current),
                                icon: "doc.text",
                                url: ReleaseNotesLink.url(forVersion: AppVersion.current).absoluteString
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            FlowSettingsSection {
                FlowSettingsRow(verticalPadding: 14) {
                    VStack(spacing: 12) {
                        updateSection
                        if let reason = updater.readOnlyInstallReason {
                            readOnlyLocationNotice(reason)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                FlowSettingsDivider()

                FlowSettingsRow(verticalPadding: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l10n["export_diagnostics"])
                                .font(.system(size: 13.5))
                            Text(l10n["export_diagnostics_desc"])
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        aboutButton(l10n["export_diagnostics"], icon: "ladybug") {
                            DiagnosticsExporter.export()
                        }
                        .help(l10n["export_diagnostics_desc"])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var updateSection: some View {
        switch updater.state {
        case .idle:
            aboutButton(l10n["check_for_updates"], icon: "arrow.triangle.2.circlepath") {
                updater.checkForUpdates()
            }

        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(l10n["check_for_updates"])
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

        case .upToDate:
            Button {
                updater.checkForUpdates()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 13))
                    Text(String(format: l10n["no_update_body"], AppVersion.current))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .onHover { h in
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

        case let .available(version):
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 13))
                    Text(String(format: l10n["update_available_body"], version, AppVersion.current))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if updater.isHomebrewInstall {
                    HStack(spacing: 8) {
                        Text(l10n["update_homebrew_command"])
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(FlowSettingsPalette.valuePillFill(scheme))
                            )
                        aboutButton(l10n["update_copy_command"], icon: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(l10n["update_homebrew_command"], forType: .string)
                        }
                    }
                } else {
                    aboutButton(l10n["update_now"], icon: "arrow.down.to.line") {
                        updater.checkForUpdates()
                    }
                }
            }

        case let .failed(message):
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 13))
                    Text(String(format: l10n["update_failed_body"], message))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                aboutButton(l10n["update_retry"], icon: "arrow.clockwise") {
                    updater.checkForUpdates()
                }
            }
        }
    }

    /// Sparkle cannot replace a bundle it may not write, and its failure alert
    /// never says why. Say it up front, with the one fix that works.
    private func readOnlyLocationNotice(_ reason: AppInstallLocation.ReadOnlyReason) -> some View {
        let message: String
        switch reason {
        case .translocated: message = l10n["readonly_location_translocated"]
        case .diskImage: message = l10n["readonly_location_disk_image"]
        case .readOnlyVolume: message = l10n["readonly_location_volume"]
        }
        return VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 13))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            aboutButton(l10n["open_applications_folder"], icon: "folder") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
            }
        }
        .frame(maxWidth: 420)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
    }

    private func aboutButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(FlowSettingsPalette.valuePillFill(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(FlowSettingsPalette.valuePillBorder(scheme), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private func aboutLink(_ title: String, icon: String, url: String) -> some View {
        aboutButton(title, icon: icon) {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        }
    }
}
