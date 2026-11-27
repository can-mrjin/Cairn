import SwiftUI
import CodeIslandCore

/// Sleek, collapsible tree view rendering subagents / swarm workers beneath a parent session card.
/// Uses pure lightweight SwiftUI paths (zero `.blur`) for 120Hz responsiveness in the dark notch.
struct SubagentTreeView: View {
    let subagents: [SubagentState]
    let fontSize: CGFloat
    var onSelectSubagent: ((SubagentState) -> Void)? = nil

    @AppStorage(SettingsKey.showModelLabel) private var showModelLabel = SettingsDefaults.showModelLabel
    @State private var userExpandedOverride: Bool? = nil

    init(
        subagents: [SubagentState],
        fontSize: CGFloat,
        onSelectSubagent: ((SubagentState) -> Void)? = nil
    ) {
        self.subagents = subagents
        self.fontSize = fontSize
        self.onSelectSubagent = onSelectSubagent
    }

    private var sortedSubagents: [SubagentState] {
        subagents.sorted {
            if $0.startTime != $1.startTime {
                return $0.startTime < $1.startTime
            }
            return $0.agentId < $1.agentId
        }
    }

    private var hasActiveSubagent: Bool {
        subagents.contains { $0.status != .idle }
    }

    private var isExpanded: Bool {
        userExpandedOverride ?? (hasActiveSubagent || subagents.count <= 5)
    }

    private var smallSize: CGFloat {
        max(9, fontSize - 1)
    }

    private var summaryText: String {
        var waiting = 0
        var running = 0
        var done = 0
        for sub in subagents {
            switch sub.status {
            case .waitingApproval, .waitingQuestion:
                waiting += 1
            case .running, .processing:
                running += 1
            case .idle:
                done += 1
            }
        }

        let isChinese = L10n.shared.effectiveLanguage.hasPrefix("zh")
        var parts: [String] = []
        if waiting > 0 {
            parts.append(isChinese ? "\(waiting) 等待" : "\(waiting) waiting")
        }
        if running > 0 {
            parts.append(isChinese ? "\(running) 运行中" : "\(running) running")
        }
        if done > 0 {
            parts.append(isChinese ? "\(done) 已完成" : "\(done) done")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        if !subagents.isEmpty {
            let ordered = sortedSubagents
            VStack(alignment: .leading, spacing: 0) {
                headerToggle

                if isExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(ordered.enumerated()), id: \.element.agentId) { index, sub in
                            SubagentTreeRow(
                                subagent: sub,
                                isLast: index == ordered.count - 1,
                                fontSize: smallSize,
                                showModelLabel: showModelLabel,
                                onSelect: onSelectSubagent
                            )
                        }
                    }
                    .padding(.top, 1)
                    .transition(.opacity)
                }
            }
            .padding(.leading, 4)
        }
    }

    private var headerToggle: some View {
        Button {
            withAnimation(NotchAnimation.micro) {
                userExpandedOverride = !isExpanded
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: max(9, smallSize - 0.5), weight: .semibold))
                    .foregroundStyle(
                        hasActiveSubagent
                            ? Color(red: 0.68, green: 0.60, blue: 0.96).opacity(0.92)
                            : .white.opacity(0.45)
                    )
                    .frame(width: 12, alignment: .center)

                Text(summaryText)
                    .font(.system(size: smallSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(hasActiveSubagent ? 0.72 : 0.48))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(width: 10, alignment: .center)
            }
            .padding(.vertical, 2.5)
            .padding(.trailing, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SubagentTreeRow: View {
    let subagent: SubagentState
    let isLast: Bool
    let fontSize: CGFloat
    let showModelLabel: Bool
    let onSelect: ((SubagentState) -> Void)?

    @State private var isHovered = false

    private static let runningColor = Color(red: 0.30, green: 0.85, blue: 0.45)
    private static let waitingColor = Color(red: 1.0, green: 0.62, blue: 0.22)
    private static let doneColor = Color(red: 0.30, green: 0.85, blue: 0.52).opacity(0.65)
    private static let branchLineColor = Color.white.opacity(0.22)

    private var displayName: String {
        let trimmed = subagent.agentType.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(subagent.agentId.prefix(6)) : trimmed
    }

    private var activityText: String? {
        let tool = subagent.currentTool?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let desc = subagent.toolDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !tool.isEmpty && !desc.isEmpty {
            return "\(tool) \(desc)"
        }
        if !tool.isEmpty {
            return tool
        }
        if !desc.isEmpty {
            return desc
        }
        return nil
    }

    var body: some View {
        Button {
            onSelect?(subagent)
        } label: {
            HStack(spacing: 0) {
                TreeBranchConnector(isLast: isLast)
                    .stroke(
                        Self.branchLineColor,
                        style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 14)
                    .frame(maxHeight: .infinity)

                HStack(spacing: 5) {
                    statusGlyph

                    Text(displayName)
                        .font(.system(size: fontSize + 0.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(subagent.status == .idle ? 0.56 : 0.90))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    if let activity = activityText {
                        Text(activity)
                            .font(.system(size: max(9.5, fontSize)))
                            .foregroundStyle(.white.opacity(subagent.status == .idle ? 0.36 : 0.54))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer(minLength: 0)
                    }

                    if showModelLabel, let modelLabel = subagent.modelLabel {
                        Text(modelLabel)
                            .font(.system(size: max(9, fontSize - 1), weight: .medium))
                            .foregroundStyle(.white.opacity(subagent.status == .idle ? 0.38 : 0.58))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.06 : 0))
                )
            }
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch subagent.status {
        case .running, .processing:
            Circle()
                .fill(Self.runningColor)
                .frame(width: 5.5, height: 5.5)
                .frame(width: 9, height: 9, alignment: .center)
        case .waitingApproval, .waitingQuestion:
            Circle()
                .fill(Self.waitingColor)
                .frame(width: 5.5, height: 5.5)
                .frame(width: 9, height: 9, alignment: .center)
        case .idle:
            Image(systemName: "checkmark")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(Self.doneColor)
                .frame(width: 9, height: 9, alignment: .center)
        }
    }
}

/// Crisp 1pt L/T tree connector with a rounded elbow into the row's vertical midpoint.
/// Consecutive non-last rows form an unbroken vertical spine with zero gaps.
private struct TreeBranchConnector: Shape {
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0, rect.height > 0 else { return path }

        let spineX: CGFloat = 5.5
        let midY = rect.midY
        let endX = rect.maxX - 1.5
        let radius = min(4.5, max(0, midY), max(0, endX - spineX))

        // Upper spine curving smoothly into the horizontal branch
        path.move(to: CGPoint(x: spineX, y: rect.minY))
        path.addLine(to: CGPoint(x: spineX, y: midY - radius))
        path.addQuadCurve(
            to: CGPoint(x: spineX + radius, y: midY),
            control: CGPoint(x: spineX, y: midY)
        )
        path.addLine(to: CGPoint(x: endX, y: midY))

        // Continue vertical spine straight down for non-last siblings (T-junction)
        if !isLast {
            path.move(to: CGPoint(x: spineX, y: midY - radius))
            path.addLine(to: CGPoint(x: spineX, y: rect.maxY))
        }

        return path
    }
}
