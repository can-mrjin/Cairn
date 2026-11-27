import SwiftUI
import CodeIslandCore

/// Non-interactive session-card checklist display (TaskCreate / TodoWrite /
/// Codex & Claude Desktop update_plan / Antigravity update_steps).
///
/// The visual style (compact bar, expanded list, or checklist card) is chosen
/// in Appearance settings rather than toggled by clicking the card, so every
/// tap on the card passes straight through to jump to the session.
///
/// A finished list lingers for ``AgentTaskList/completedLinger`` and then fades
/// via a single one-shot sleep tied to its `completedAt` — no polling timer, so
/// an idle panel stays idle.
struct AgentTaskProgressView: View, Equatable {
    let tasks: AgentTaskList
    let fontSize: CGFloat
    /// The session's turn is over. An unfinished plan still shows its
    /// progress, but not "▶ Running tests" — nothing is running.
    let agentIsIdle: Bool
    let style: TaskProgressStyle
    let accentColor: Color

    /// `completedAt` of a finished list that has already faded out.
    @State private var fadedCompletion: Date?

    init(
        tasks: AgentTaskList,
        fontSize: CGFloat,
        agentIsIdle: Bool = false,
        style: TaskProgressStyle = .compact,
        accentColor: Color = Color(red: 0.3, green: 0.85, blue: 0.4)
    ) {
        self.tasks = tasks
        self.fontSize = fontSize
        self.agentIsIdle = agentIsIdle
        self.style = style
        self.accentColor = accentColor
    }

    static let doneColor = Color(red: 0.3, green: 0.85, blue: 0.4)
    static let activeColor = Color(red: 1.0, green: 0.78, blue: 0.3)
    static let pendingColor = Color.white.opacity(0.18)
    /// Rows the expanded list shows before capping to keep cards bounded
    /// inside the panel window.
    static let visibleListedItems = 6
    /// Maximum rows considered by viewport calculations.
    static let maxListedItems = 50
    private static let listRowSpacing: CGFloat = 2

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tasks == rhs.tasks
            && lhs.fontSize == rhs.fontSize
            && lhs.agentIsIdle == rhs.agentIsIdle
            && lhs.style == rhs.style
    }

    private var smallSize: CGFloat { max(9, fontSize - 1) }

    /// Text beside the bar in the compact row.
    enum Caption: Equatable {
        case allDone
        /// The in-progress item's "Running tests".
        case working(String)
        /// Nothing claimed yet: the next pending item, dimmed.
        case next(String)
    }

    /// An idle session gets no "doing X" / "next: Y": its turn ended mid-plan,
    /// and the bar and count already say where it stopped.
    static func caption(tasks: AgentTaskList, agentIsIdle: Bool) -> Caption? {
        if tasks.isAllCompleted { return .allDone }
        guard !agentIsIdle else { return nil }
        if let current = tasks.current { return .working(current.progressLabel) }
        if let next = tasks.items.first(where: { $0.status == .pending }) { return .next(next.title) }
        return nil
    }

    var body: some View {
        if isShown {
            Group {
                switch style {
                case .compact:
                    compactRow
                        .padding(.leading, 4)

                case .expanded:
                    VStack(alignment: .leading, spacing: 4) {
                        compactRow
                        listRows
                    }
                    .padding(.leading, 4)

                case .card:
                    checklistCard
                }
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(
                format: L10n.shared["task_progress_a11y"],
                tasks.completedCount,
                tasks.items.count
            ))
            .task(id: tasks.completedAt) { await fadeOutWhenFinished() }
            .transition(.opacity)
        }
    }

    private var isShown: Bool {
        guard !tasks.isEmpty else { return false }
        if let completedAt = tasks.completedAt, fadedCompletion == completedAt { return false }
        return tasks.isVisible(now: Date())
    }

    /// Sleep once until the finished list's deadline, then fade it. Cancelled
    /// automatically when the list changes (new `completedAt`) or the card
    /// leaves the screen; a card rendered after the deadline never shows it.
    private func fadeOutWhenFinished() async {
        guard let completedAt = tasks.completedAt,
              let deadline = tasks.hideDeadline() else { return }
        let delay = deadline.timeIntervalSinceNow
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.35)) { fadedCompletion = completedAt }
    }

    private var compactRow: some View {
        HStack(spacing: 6) {
            AgentTaskBar(items: tasks.items)
                .frame(width: 46, height: 5)

            Text("\(tasks.completedCount)/\(tasks.items.count)")
                .font(.system(size: smallSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(tasks.isAllCompleted ? Self.doneColor : .white.opacity(0.6))
                .fixedSize()

            switch Self.caption(tasks: tasks, agentIsIdle: agentIsIdle) {
            case .allDone:
                Text(L10n.shared["task_progress_all_done"])
                    .font(.system(size: smallSize, design: .monospaced))
                    .foregroundStyle(Self.doneColor.opacity(0.85))
                    .lineLimit(1)
            case .working(let label):
                Text(label)
                    .font(.system(size: smallSize, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
            case .next(let title):
                // Nothing claimed yet — show what is next, dimmed.
                Text(title)
                    .font(.system(size: smallSize, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
            case nil:
                EmptyView()
            }

            Spacer(minLength: 0)
        }
    }

    /// Height of the expanded list's scroll area, or nil when every row fits
    /// without one. Shows half of the next row so the list reads as
    /// scrollable. A row is a point taller than the monospaced line: the
    /// ✓ ▶ ○ glyphs come from a fallback font.
    static func listViewportHeight(itemCount: Int, lineHeight: CGFloat) -> CGFloat? {
        let rendered = min(itemCount, maxListedItems) + (itemCount > maxListedItems ? 1 : 0)
        guard rendered > visibleListedItems else { return nil }
        return ((CGFloat(visibleListedItems) + 0.5) * (lineHeight + 1 + listRowSpacing)).rounded()
    }

    private var listRows: some View {
        VStack(alignment: .leading, spacing: Self.listRowSpacing) {
            ForEach(tasks.items.prefix(Self.visibleListedItems)) { item in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(Self.symbol(item.status))
                        // The bar's pending grey is too faint for a glyph.
                        .foregroundStyle(item.status == .pending ? .white.opacity(0.5) : Self.color(item.status))
                    Text(item.title)
                        .foregroundStyle(Self.titleColor(item.status))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(size: smallSize, design: .monospaced))
            }
            if tasks.items.count > Self.visibleListedItems {
                Text(String(format: L10n.shared["task_progress_more"], tasks.items.count - Self.visibleListedItems))
                    .font(.system(size: smallSize, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.leading, 2)
    }

    private var checklistCard: some View {
        let doneCount = tasks.completedCount
        let activeCount = tasks.items.lazy.filter { $0.status == .inProgress }.count
        let pendingCount = max(0, tasks.items.count - doneCount - activeCount)
        let headerText: String = tasks.isAllCompleted
            ? L10n.shared["task_progress_all_done"]
            : String(format: L10n.shared["task_card_header"], doneCount, activeCount, pendingCount)

        return VStack(alignment: .leading, spacing: 4) {
            Text(headerText)
                .font(.system(size: max(9.5, fontSize - 0.5), weight: .medium))
                .foregroundStyle(tasks.isAllCompleted ? Self.doneColor.opacity(0.85) : .white.opacity(0.45))
                .lineLimit(1)

            ForEach(tasks.items.prefix(Self.visibleListedItems)) { item in
                HStack(spacing: 6) {
                    switch item.status {
                    case .inProgress:
                        Circle()
                            .fill(accentColor)
                            .frame(width: 6, height: 6)
                    case .pending:
                        Image(systemName: "square")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.35))
                    case .completed:
                        Image(systemName: "checkmark.square.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.42))
                    }

                    Text(item.status == .inProgress ? item.progressLabel : item.title)
                        .font(.system(size: fontSize, weight: item.status == .inProgress ? .medium : .regular))
                        .foregroundStyle(
                            item.status == .inProgress
                                ? .white.opacity(0.90)
                                : (item.status == .completed ? .white.opacity(0.40) : .white.opacity(0.55))
                        )
                        .strikethrough(item.status == .completed)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            if tasks.items.count > Self.visibleListedItems {
                Text(String(format: L10n.shared["task_progress_more"], tasks.items.count - Self.visibleListedItems))
                    .font(.system(size: smallSize))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.04))
        )
    }

    /// U+FE0E keeps ▶ in text presentation instead of the emoji glyph.
    static func symbol(_ status: AgentTaskStatus) -> String {
        switch status {
        case .completed: return "✓"
        case .inProgress: return "▶\u{FE0E}"
        case .pending: return "○"
        }
    }

    static func color(_ status: AgentTaskStatus) -> Color {
        switch status {
        case .completed: return doneColor
        case .inProgress: return activeColor
        case .pending: return pendingColor
        }
    }

    private static func titleColor(_ status: AgentTaskStatus) -> Color {
        switch status {
        case .completed: return .white.opacity(0.5)
        case .inProgress: return .white.opacity(0.9)
        case .pending: return .white.opacity(0.6)
        }
    }
}

/// One segment per task while they stay readable; a proportional
/// done/in-progress fill beyond that. A static Canvas — redrawn only when the
/// list changes.
private struct AgentTaskBar: View {
    let items: [AgentTaskItem]

    static let maxSegments = 12

    var body: some View {
        Canvas { context, size in
            guard !items.isEmpty else { return }
            if items.count <= Self.maxSegments {
                let gap: CGFloat = 1.5
                let width = (size.width - gap * CGFloat(items.count - 1)) / CGFloat(items.count)
                for (index, item) in items.enumerated() {
                    let rect = CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: size.height)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: size.height / 2),
                        with: .color(AgentTaskProgressView.color(item.status))
                    )
                }
            } else {
                let total = CGFloat(items.count)
                let done = CGFloat(items.filter { $0.status == .completed }.count)
                let active = CGFloat(items.filter { $0.status == .inProgress }.count)
                let track = CGRect(origin: .zero, size: size)
                context.clip(to: Path(roundedRect: track, cornerRadius: size.height / 2))
                context.fill(Path(track), with: .color(AgentTaskProgressView.pendingColor))
                let doneWidth = size.width * done / total
                context.fill(
                    Path(CGRect(x: 0, y: 0, width: doneWidth, height: size.height)),
                    with: .color(AgentTaskProgressView.doneColor)
                )
                context.fill(
                    Path(CGRect(x: doneWidth, y: 0, width: size.width * active / total, height: size.height)),
                    with: .color(AgentTaskProgressView.activeColor)
                )
            }
        }
    }
}
