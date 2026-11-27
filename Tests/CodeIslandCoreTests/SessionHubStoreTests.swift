import XCTest
@testable import CodeIslandCore

final class SessionHubStoreTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        let components = DateComponents(
            calendar: utcCalendar,
            timeZone: utcCalendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
        return utcCalendar.date(from: components)!
    }

    private func makeEntry(
        id: String,
        source: String = "claude",
        title: String = "Session",
        projectName: String = "FlowIsland",
        prompt: String = "Fix bug",
        gitBranch: String = "main",
        status: AgentStatus = .idle,
        createdAt: Date? = nil,
        lastUpdated: Date
    ) -> SessionHubEntry {
        SessionHubEntry(
            sessionId: id,
            source: source,
            title: title,
            projectName: projectName,
            prompt: prompt,
            gitBranch: gitBranch,
            status: status,
            createdAt: createdAt,
            lastUpdated: lastUpdated
        )
    }

    // MARK: - Day Key & Same Day

    func testDayKeyAndIsSameDayRespectCalendar() {
        let morning = makeDate(year: 2026, month: 5, day: 9, hour: 0, minute: 5)
        let night = makeDate(year: 2026, month: 5, day: 9, hour: 23, minute: 55)
        let nextDay = makeDate(year: 2026, month: 5, day: 10, hour: 0, minute: 5)

        XCTAssertEqual(SessionHubEngine.dayKey(for: morning, calendar: utcCalendar), "2026-05-09")
        XCTAssertEqual(SessionHubEngine.dayKey(for: night, calendar: utcCalendar), "2026-05-09")
        XCTAssertEqual(SessionHubEngine.dayKey(for: nextDay, calendar: utcCalendar), "2026-05-10")

        XCTAssertTrue(SessionHubEngine.isSameDay(morning, night, calendar: utcCalendar))
        XCTAssertFalse(SessionHubEngine.isSameDay(night, nextDay, calendar: utcCalendar))
    }

    // MARK: - Unread Transitions

    func testRecordTransitionRunningAndProcessingToIdleMarksUnread() {
        var state = SessionHubState()
        let t1 = makeDate(year: 2026, month: 11, day: 26, hour: 10, minute: 0)
        let t2 = makeDate(year: 2026, month: 11, day: 26, hour: 10, minute: 5)

        SessionHubEngine.recordTransition(
            sessionId: "s-run",
            from: .running,
            to: .idle,
            now: t1,
            state: &state
        )
        SessionHubEngine.recordTransition(
            sessionId: "s-proc",
            from: .processing,
            to: .idle,
            now: t2,
            state: &state
        )
        SessionHubEngine.recordTransition(
            sessionId: "s-initial-idle",
            from: nil,
            to: .idle,
            now: t2,
            state: &state
        )
        SessionHubEngine.recordTransition(
            sessionId: "s-start",
            from: .idle,
            to: .running,
            now: t2,
            state: &state
        )

        XCTAssertEqual(state.unreadSince["s-run"], t1)
        XCTAssertEqual(state.unreadSince["s-proc"], t2)
        XCTAssertFalse(SessionHubEngine.isUnread(sessionId: "s-initial-idle", state: state))
        XCTAssertFalse(SessionHubEngine.isUnread(sessionId: "s-start", state: state))
    }

    func testRecordTransitionEnteringWaitingApprovalAndQuestionMarksUnread() {
        var state = SessionHubState()
        let t1 = makeDate(year: 2026, month: 11, day: 26, hour: 10, minute: 0)
        let t2 = makeDate(year: 2026, month: 11, day: 26, hour: 10, minute: 1)

        SessionHubEngine.recordTransition(
            sessionId: "s-approve",
            from: .running,
            to: .waitingApproval,
            now: t1,
            state: &state
        )
        SessionHubEngine.recordTransition(
            sessionId: "s-question",
            from: nil,
            to: .waitingQuestion,
            now: t2,
            state: &state
        )

        XCTAssertEqual(state.unreadSince["s-approve"], t1)
        XCTAssertEqual(state.unreadSince["s-question"], t2)

        // Marking read and receiving a duplicate same-status event should not re-mark unread.
        SessionHubEngine.markRead(sessionId: "s-approve", state: &state)
        SessionHubEngine.recordTransition(
            sessionId: "s-approve",
            from: .waitingApproval,
            to: .waitingApproval,
            now: t2,
            state: &state
        )
        XCTAssertFalse(SessionHubEngine.isUnread(sessionId: "s-approve", state: state))
    }

    func testRecordTransitionErrorMarksUnreadAndPreservesEarliestTimestamp() {
        var state = SessionHubState()
        let t1 = makeDate(year: 2026, month: 11, day: 26, hour: 10, minute: 0)
        let t2 = makeDate(year: 2026, month: 11, day: 26, hour: 10, minute: 10)

        SessionHubEngine.recordTransition(
            sessionId: "s-err",
            from: .idle,
            to: .idle,
            hadError: true,
            now: t1,
            state: &state
        )
        XCTAssertEqual(state.unreadSince["s-err"], t1)

        // Subsequent unread-worthy transition preserves the original unreadSince timestamp.
        SessionHubEngine.recordTransition(
            sessionId: "s-err",
            from: .running,
            to: .idle,
            now: t2,
            state: &state
        )
        XCTAssertEqual(state.unreadSince["s-err"], t1)
    }

    func testRecordTransitionFocusedSuppressesAndClearsUnread() {
        var state = SessionHubState()
        let t1 = makeDate(year: 2026, month: 11, day: 26, hour: 10, minute: 0)
        let t2 = makeDate(year: 2026, month: 11, day: 26, hour: 10, minute: 2)

        // Pre-existing unread gets cleared when focused.
        SessionHubEngine.markUnread(sessionId: "s-focused", now: t1, state: &state)
        XCTAssertTrue(SessionHubEngine.isUnread(sessionId: "s-focused", state: state))

        SessionHubEngine.recordTransition(
            sessionId: "s-focused",
            from: .running,
            to: .idle,
            hadError: true,
            isFocused: true,
            now: t2,
            state: &state
        )
        XCTAssertFalse(SessionHubEngine.isUnread(sessionId: "s-focused", state: state))

        // Entering waitingApproval while focused also stays read.
        SessionHubEngine.recordTransition(
            sessionId: "s-focused",
            from: .running,
            to: .waitingApproval,
            isFocused: true,
            now: t2,
            state: &state
        )
        XCTAssertFalse(SessionHubEngine.isUnread(sessionId: "s-focused", state: state))
    }

    // MARK: - Mark Read / Unread / All Read & Unread Count

    func testMarkReadUnreadMarkAllReadAndUnreadCount() {
        var state = SessionHubState()
        let now = makeDate(year: 2026, month: 11, day: 26, hour: 11, minute: 0)

        SessionHubEngine.markUnread(sessionId: "a", now: now, state: &state)
        SessionHubEngine.markUnread(sessionId: "b", now: now, state: &state)
        SessionHubEngine.markUnread(sessionId: "stale", now: now, state: &state)

        XCTAssertTrue(SessionHubEngine.isUnread(sessionId: "a", state: state))
        XCTAssertEqual(SessionHubEngine.unreadCount(among: ["a", "b", "c"], state: state), 2)
        // Duplicate IDs in input should not double-count.
        XCTAssertEqual(SessionHubEngine.unreadCount(among: ["a", "a", "b"], state: state), 2)

        SessionHubEngine.markRead(sessionId: "a", state: &state)
        XCTAssertFalse(SessionHubEngine.isUnread(sessionId: "a", state: state))
        XCTAssertEqual(SessionHubEngine.unreadCount(among: ["a", "b", "c"], state: state), 1)

        SessionHubEngine.markAllRead(state: &state)
        XCTAssertTrue(state.unreadSince.isEmpty)
        XCTAssertEqual(SessionHubEngine.unreadCount(among: ["a", "b", "c"], state: state), 0)
    }

    // MARK: - Pin Order & Unpin

    func testTogglePinPreservesOrderAndUnpins() {
        var state = SessionHubState()

        SessionHubEngine.togglePin(sessionId: "p1", state: &state)
        SessionHubEngine.togglePin(sessionId: "p2", state: &state)
        SessionHubEngine.togglePin(sessionId: "p3", state: &state)

        XCTAssertEqual(state.pinnedIds, ["p1", "p2", "p3"])
        XCTAssertTrue(SessionHubEngine.isPinned(sessionId: "p2", state: state))
        XCTAssertFalse(SessionHubEngine.isPinned(sessionId: "p4", state: state))

        SessionHubEngine.togglePin(sessionId: "p2", state: &state)
        XCTAssertEqual(state.pinnedIds, ["p1", "p3"])
        XCTAssertFalse(SessionHubEngine.isPinned(sessionId: "p2", state: state))

        // Re-pinning appends at the end of pin order.
        SessionHubEngine.togglePin(sessionId: "p2", state: &state)
        XCTAssertEqual(state.pinnedIds, ["p1", "p3", "p2"])
    }

    // MARK: - Archive & Unarchive

    func testArchiveClearsUnreadResetsOnNewDayAndUnarchiveRestores() {
        var state = SessionHubState()
        let day1 = makeDate(year: 2026, month: 11, day: 26, hour: 15, minute: 0)
        let day2 = makeDate(year: 2026, month: 11, day: 28, hour: 15, minute: 0)

        SessionHubEngine.markUnread(sessionId: "s1", now: day1, state: &state)
        SessionHubEngine.archive(sessionId: "s1", now: day1, state: &state)

        XCTAssertTrue(state.archivedIds.contains("s1"))
        XCTAssertFalse(SessionHubEngine.isUnread(sessionId: "s1", state: state))
        XCTAssertEqual(state.archivedDayKey, SessionHubEngine.dayKey(for: day1))

        SessionHubEngine.unarchive(sessionId: "s1", state: &state)
        XCTAssertFalse(state.archivedIds.contains("s1"))

        SessionHubEngine.archive(sessionId: "s1", now: day1, state: &state)
        SessionHubEngine.archive(sessionId: "s2", now: day2, state: &state)
        XCTAssertFalse(state.archivedIds.contains("s1"))
        XCTAssertTrue(state.archivedIds.contains("s2"))
        XCTAssertEqual(state.archivedDayKey, SessionHubEngine.dayKey(for: day2))
    }

    func testPruneStaleArchivesClearsPreviousDayWithoutNewArchiveCall() {
        var state = SessionHubState()
        let day1 = makeDate(year: 2026, month: 11, day: 26, hour: 15, minute: 0)
        let day1Later = makeDate(year: 2026, month: 11, day: 26, hour: 23, minute: 59)
        let day2 = makeDate(year: 2026, month: 11, day: 27, hour: 0, minute: 1)

        SessionHubEngine.archive(sessionId: "s1", now: day1, state: &state, calendar: utcCalendar)
        XCTAssertEqual(state.archivedIds, ["s1"])
        XCTAssertEqual(state.archivedDayKey, "2026-11-26")

        // Same day: no rollover
        XCTAssertFalse(SessionHubEngine.pruneStaleArchivesIfNeeded(
            now: day1Later,
            state: &state,
            calendar: utcCalendar
        ))
        XCTAssertEqual(state.archivedIds, ["s1"])

        // Next day: stale archivedIds cleared and day key advanced
        XCTAssertTrue(SessionHubEngine.pruneStaleArchivesIfNeeded(
            now: day2,
            state: &state,
            calendar: utcCalendar
        ))
        XCTAssertTrue(state.archivedIds.isEmpty)
        XCTAssertEqual(state.archivedDayKey, "2026-11-27")

        // Repeated check on day2 is a no-op
        XCTAssertFalse(SessionHubEngine.pruneStaleArchivesIfNeeded(
            now: day2,
            state: &state,
            calendar: utcCalendar
        ))
    }

    // MARK: - Today Retention vs Timeout

    func testShouldRetainSessionRules() {
        var state = SessionHubState()
        let todayMorning = makeDate(year: 2026, month: 11, day: 26, hour: 9, minute: 0)
        let todayAfternoon = makeDate(year: 2026, month: 11, day: 26, hour: 16, minute: 0)
        let yesterday = makeDate(year: 2026, month: 11, day: 25, hour: 23, minute: 0)

        SessionHubEngine.togglePin(sessionId: "pinned-old", state: &state)
        SessionHubEngine.markUnread(sessionId: "unread-old", now: yesterday, state: &state)
        SessionHubEngine.archive(sessionId: "archived-today", now: todayAfternoon, state: &state)

        // Pinned old idle session is retained even when keepTodaySessions is false.
        XCTAssertTrue(SessionHubEngine.shouldRetainSession(
            sessionId: "pinned-old",
            status: .idle,
            lastUpdated: yesterday,
            keepTodaySessions: false,
            now: todayAfternoon,
            state: state,
            calendar: utcCalendar
        ))

        // Unread old idle session is retained even when keepTodaySessions is false.
        XCTAssertTrue(SessionHubEngine.shouldRetainSession(
            sessionId: "unread-old",
            status: .idle,
            lastUpdated: yesterday,
            keepTodaySessions: false,
            now: todayAfternoon,
            state: state,
            calendar: utcCalendar
        ))

        // Active (running/processing/waiting) session is always retained.
        XCTAssertTrue(SessionHubEngine.shouldRetainSession(
            sessionId: "active-old",
            status: .running,
            lastUpdated: yesterday,
            keepTodaySessions: false,
            now: todayAfternoon,
            state: state,
            calendar: utcCalendar
        ))
        XCTAssertTrue(SessionHubEngine.shouldRetainSession(
            sessionId: "waiting-old",
            status: .waitingApproval,
            lastUpdated: yesterday,
            keepTodaySessions: false,
            now: todayAfternoon,
            state: state,
            calendar: utcCalendar
        ))

        // Same-day idle session is retained only when keepTodaySessions is true and not archived.
        XCTAssertTrue(SessionHubEngine.shouldRetainSession(
            sessionId: "today-idle",
            status: .idle,
            lastUpdated: todayMorning,
            keepTodaySessions: true,
            now: todayAfternoon,
            state: state,
            calendar: utcCalendar
        ))
        XCTAssertFalse(SessionHubEngine.shouldRetainSession(
            sessionId: "today-idle",
            status: .idle,
            lastUpdated: todayMorning,
            keepTodaySessions: false,
            now: todayAfternoon,
            state: state,
            calendar: utcCalendar
        ))
        XCTAssertFalse(SessionHubEngine.shouldRetainSession(
            sessionId: "archived-today",
            status: .idle,
            lastUpdated: todayMorning,
            keepTodaySessions: true,
            now: todayAfternoon,
            state: state,
            calendar: utcCalendar
        ))

        // Yesterday's plain idle session is eligible for cleanup.
        XCTAssertFalse(SessionHubEngine.shouldRetainSession(
            sessionId: "yesterday-idle",
            status: .idle,
            lastUpdated: yesterday,
            keepTodaySessions: true,
            now: todayAfternoon,
            state: state,
            calendar: utcCalendar
        ))
    }

    // MARK: - Filtering, Searching & Deterministic Priority Sorting

    func testVisibleEntriesPrioritySortingAndArchiveExclusion() {
        var state = SessionHubState()
        let base = makeDate(year: 2026, month: 11, day: 26, hour: 12, minute: 0)

        SessionHubEngine.togglePin(sessionId: "pin-first", state: &state)
        SessionHubEngine.togglePin(sessionId: "pin-second", state: &state)
        SessionHubEngine.markUnread(sessionId: "unread-idle", now: base, state: &state)
        SessionHubEngine.archive(sessionId: "archived-idle", now: base, state: &state)

        // Deliberately give older sessions higher statuses (waitingApproval/running/unread)
        // and newer `lastUpdated` timestamps so we prove order stays locked to:
        // pinned (in pin order) -> `createdAt` descending -> `sessionId` ascending.
        let entries = [
            makeEntry(id: "idle-newest", status: .idle, createdAt: base.addingTimeInterval(90), lastUpdated: base.addingTimeInterval(90)),
            makeEntry(id: "processing-task", status: .processing, createdAt: base.addingTimeInterval(70), lastUpdated: base.addingTimeInterval(300)),
            makeEntry(id: "tie-b", status: .running, createdAt: base.addingTimeInterval(50), lastUpdated: base.addingTimeInterval(400)),
            makeEntry(id: "tie-a", status: .idle, createdAt: base.addingTimeInterval(50), lastUpdated: base.addingTimeInterval(50)),
            makeEntry(id: "waiting-question", status: .waitingQuestion, createdAt: base.addingTimeInterval(40), lastUpdated: base.addingTimeInterval(500)),
            makeEntry(id: "waiting-approval", status: .waitingApproval, createdAt: base.addingTimeInterval(30), lastUpdated: base.addingTimeInterval(600)),
            makeEntry(id: "unread-idle", status: .idle, createdAt: base.addingTimeInterval(20), lastUpdated: base.addingTimeInterval(700)),
            makeEntry(id: "idle-oldest", status: .idle, createdAt: base.addingTimeInterval(10), lastUpdated: base.addingTimeInterval(800)),
            makeEntry(id: "pin-second", status: .idle, createdAt: base.addingTimeInterval(100), lastUpdated: base.addingTimeInterval(100)),
            makeEntry(id: "pin-first", status: .idle, createdAt: base.addingTimeInterval(1), lastUpdated: base.addingTimeInterval(1)),
            makeEntry(id: "archived-idle", status: .idle, createdAt: base.addingTimeInterval(200), lastUpdated: base.addingTimeInterval(900)),
        ]

        let visible = SessionHubEngine.visibleEntries(
            entries,
            filter: .all,
            searchQuery: "",
            includeArchived: false,
            state: state
        )

        XCTAssertEqual(
            visible.map(\.sessionId),
            [
                "pin-first",
                "pin-second",
                "idle-newest",
                "processing-task",
                "tie-a",
                "tie-b",
                "waiting-question",
                "waiting-approval",
                "unread-idle",
                "idle-oldest",
            ]
        )

        let withArchived = SessionHubEngine.visibleEntries(
            entries,
            filter: .all,
            searchQuery: "",
            includeArchived: true,
            state: state
        )
        XCTAssertTrue(withArchived.contains { $0.sessionId == "archived-idle" })
        XCTAssertEqual(withArchived.map(\.sessionId).prefix(3), ["pin-first", "pin-second", "archived-idle"])
    }

    func testVisibleEntriesFiltersAndCaseInsensitiveSearchAcrossAllFields() {
        var state = SessionHubState()
        let base = makeDate(year: 2026, month: 11, day: 26, hour: 14, minute: 0)

        SessionHubEngine.togglePin(sessionId: "s-pin", state: &state)
        SessionHubEngine.markUnread(sessionId: "s-unread", now: base, state: &state)

        let entries = [
            makeEntry(
                id: "s-pin",
                source: "codex",
                title: "Refactor Parser",
                projectName: "AlphaCore",
                prompt: "Clean up AST nodes",
                gitBranch: "feat/parser",
                status: .idle,
                lastUpdated: base
            ),
            makeEntry(
                id: "s-unread",
                source: "claude",
                title: "UI Polish",
                projectName: "FlowIsland",
                prompt: "Add unread badge glow",
                gitBranch: "fix/hub-ui",
                status: .idle,
                lastUpdated: base.addingTimeInterval(10)
            ),
            makeEntry(
                id: "s-active",
                source: "gemini",
                title: "Run Benchmarks",
                projectName: "MetricsKit",
                prompt: "Measure latency spikes",
                gitBranch: "perf/latency",
                status: .running,
                lastUpdated: base.addingTimeInterval(20)
            ),
        ]

        XCTAssertEqual(
            SessionHubEngine.visibleEntries(entries, filter: .unread, searchQuery: "", state: state).map(\.sessionId),
            ["s-unread"]
        )
        XCTAssertEqual(
            SessionHubEngine.visibleEntries(entries, filter: .active, searchQuery: "", state: state).map(\.sessionId),
            ["s-active"]
        )
        XCTAssertEqual(
            SessionHubEngine.visibleEntries(entries, filter: .pinned, searchQuery: "", state: state).map(\.sessionId),
            ["s-pin"]
        )

        // Search across title, projectName, prompt, source, gitBranch (case-insensitive & trimmed;
        // avoid `i`/`I` case changes in assertions so tests remain independent of Turkish locale).
        XCTAssertEqual(
            SessionHubEngine.visibleEntries(entries, filter: .all, searchQuery: "  PARSER ", state: state).map(\.sessionId),
            ["s-pin"]
        )
        XCTAssertEqual(
            SessionHubEngine.visibleEntries(entries, filter: .all, searchQuery: "flow", state: state).map(\.sessionId),
            ["s-unread"]
        )
        XCTAssertEqual(
            SessionHubEngine.visibleEntries(entries, filter: .all, searchQuery: "LATENCY", state: state).map(\.sessionId),
            ["s-active"]
        )
        XCTAssertEqual(
            SessionHubEngine.visibleEntries(entries, filter: .all, searchQuery: "GeM", state: state).map(\.sessionId),
            ["s-active"]
        )
        XCTAssertEqual(
            SessionHubEngine.visibleEntries(entries, filter: .all, searchQuery: "HUB-U", state: state).map(\.sessionId),
            ["s-unread"]
        )
        XCTAssertTrue(
            SessionHubEngine.visibleEntries(entries, filter: .all, searchQuery: "nonexistent-xyz", state: state).isEmpty
        )
    }

    // MARK: - Persistence Encode / Decode

    func testEncodeDecodeRoundTripAndCorruptFallback() {
        let t1 = Date(timeIntervalSince1970: 1_764_150_000.25)
        let t2 = Date(timeIntervalSince1970: 1_764_150_360.75)

        let original = SessionHubState(
            unreadSince: ["s1": t1, "s2": t2],
            pinnedIds: ["s2", "s1"],
            archivedIds: ["s3", "s4"],
            archivedDayKey: "2026-11-26"
        )

        let encoded = SessionHubEngine.encode(original)
        let decoded = SessionHubEngine.decode(encoded)
        XCTAssertEqual(decoded, original)

        // Empty, whitespace, and corrupt inputs safely return default empty state.
        XCTAssertEqual(SessionHubEngine.decode(""), SessionHubState())
        XCTAssertEqual(SessionHubEngine.decode("   \n  "), SessionHubState())
        XCTAssertEqual(SessionHubEngine.decode("{not valid json"), SessionHubState())
        XCTAssertEqual(SessionHubEngine.decode("[1, 2, 3]"), SessionHubState())

        // Partial JSON decodes present fields and fills defaults for missing keys.
        let partial = SessionHubEngine.decode(#"{"pinnedIds":["x1","x2"]}"#)
        XCTAssertEqual(partial.pinnedIds, ["x1", "x2"])
        XCTAssertTrue(partial.unreadSince.isEmpty)
        XCTAssertTrue(partial.archivedIds.isEmpty)
        XCTAssertEqual(partial.archivedDayKey, "")
    }
}
