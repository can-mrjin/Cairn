import Foundation

/// Filter tab for the expanded Today's Session Hub list.
public enum SessionHubFilter: String, CaseIterable, Sendable, Codable, Identifiable {
    case all
    case unread
    case active
    case pinned

    public var id: String { rawValue }
}

/// Immutable projection of a session used by `SessionHubEngine` for filtering and sorting.
public struct SessionHubEntry: Sendable, Equatable {
    public let sessionId: String
    public let source: String
    public let title: String
    public let projectName: String
    public let prompt: String
    public let gitBranch: String
    public let status: AgentStatus
    public let lastUpdated: Date

    public init(
        sessionId: String,
        source: String,
        title: String,
        projectName: String,
        prompt: String,
        gitBranch: String,
        status: AgentStatus,
        lastUpdated: Date
    ) {
        self.sessionId = sessionId
        self.source = source
        self.title = title
        self.projectName = projectName
        self.prompt = prompt
        self.gitBranch = gitBranch
        self.status = status
        self.lastUpdated = lastUpdated
    }
}

/// Persistent user-facing Hub state (unread markers, pin order, and daily archive set).
public struct SessionHubState: Sendable, Codable, Equatable {
    public var unreadSince: [String: Date]
    public var pinnedIds: [String]          // preserves pin order
    public var archivedIds: Set<String>
    public var archivedDayKey: String       // yyyy-MM-dd so archives optionally stay tidy

    public init(
        unreadSince: [String: Date] = [:],
        pinnedIds: [String] = [],
        archivedIds: Set<String> = [],
        archivedDayKey: String = ""
    ) {
        self.unreadSince = unreadSince
        self.pinnedIds = pinnedIds
        self.archivedIds = archivedIds
        self.archivedDayKey = archivedDayKey
    }

    private enum CodingKeys: String, CodingKey {
        case unreadSince
        case pinnedIds
        case archivedIds
        case archivedDayKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.unreadSince = try container.decodeIfPresent([String: Date].self, forKey: .unreadSince) ?? [:]
        self.pinnedIds = try container.decodeIfPresent([String].self, forKey: .pinnedIds) ?? []
        self.archivedIds = try container.decodeIfPresent(Set<String>.self, forKey: .archivedIds) ?? []
        self.archivedDayKey = try container.decodeIfPresent(String.self, forKey: .archivedDayKey) ?? ""
    }
}

/// Pure, deterministic state engine for FlowIsland's Unread Indicator & Today's Session Hub.
public enum SessionHubEngine {
    /// Returns a canonical `yyyy-MM-dd` day key using the given calendar.
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Returns whether two timestamps fall on the same calendar day.
    public static func isSameDay(_ lhs: Date, _ rhs: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    /// Updates unread state on a session status transition.
    /// Marks unread when transitioning from `.running`/`.processing` to `.idle`, OR when entering `.waitingApproval`/`.waitingQuestion`, OR when `hadError == true`, UNLESS `isFocused == true`.
    /// Clears unread if `isFocused == true`.
    public static func recordTransition(
        sessionId: String,
        from previous: AgentStatus?,
        to current: AgentStatus,
        hadError: Bool = false,
        isFocused: Bool = false,
        now: Date = Date(),
        state: inout SessionHubState
    ) {
        if isFocused {
            state.unreadSince.removeValue(forKey: sessionId)
            return
        }

        let completedTurn = (previous == .running || previous == .processing) && current == .idle
        let enteredWait = previous != current && (current == .waitingApproval || current == .waitingQuestion)

        if completedTurn || enteredWait || hadError {
            if state.unreadSince[sessionId] == nil {
                state.unreadSince[sessionId] = now
            }
        }
    }

    /// Marks a single session as read.
    public static func markRead(sessionId: String, state: inout SessionHubState) {
        state.unreadSince.removeValue(forKey: sessionId)
    }

    /// Marks a single session as unread at `now`.
    public static func markUnread(sessionId: String, now: Date = Date(), state: inout SessionHubState) {
        state.unreadSince[sessionId] = now
    }

    /// Clears all unread markers.
    public static func markAllRead(state: inout SessionHubState) {
        state.unreadSince.removeAll()
    }

    /// Toggles pin membership for `sessionId`, preserving pin insertion order.
    public static func togglePin(sessionId: String, state: inout SessionHubState) {
        if state.pinnedIds.contains(sessionId) {
            state.pinnedIds.removeAll { $0 == sessionId }
        } else {
            state.pinnedIds.append(sessionId)
        }
    }

    /// Returns whether `sessionId` is currently pinned.
    public static func isPinned(sessionId: String, state: SessionHubState) -> Bool {
        state.pinnedIds.contains(sessionId)
    }

    /// Clears stale `archivedIds` when `archivedDayKey` belongs to an earlier calendar day.
    /// Returns `true` when `state` was updated for a day rollover.
    @discardableResult
    public static func pruneStaleArchivesIfNeeded(
        now: Date = Date(),
        state: inout SessionHubState,
        calendar: Calendar = .current
    ) -> Bool {
        guard !state.archivedDayKey.isEmpty else { return false }
        let todayKey = dayKey(for: now, calendar: calendar)
        guard state.archivedDayKey != todayKey else { return false }
        state.archivedIds.removeAll()
        state.archivedDayKey = todayKey
        return true
    }

    /// Archives `sessionId` for the day of `now`, resetting stale archived IDs on day rollover
    /// and clearing any unread marker on the archived session.
    public static func archive(
        sessionId: String,
        now: Date = Date(),
        state: inout SessionHubState,
        calendar: Calendar = .current
    ) {
        _ = pruneStaleArchivesIfNeeded(now: now, state: &state, calendar: calendar)
        state.archivedDayKey = dayKey(for: now, calendar: calendar)
        state.archivedIds.insert(sessionId)
        state.unreadSince.removeValue(forKey: sessionId)
    }

    /// Removes `sessionId` from the archived set.
    public static func unarchive(sessionId: String, state: inout SessionHubState) {
        state.archivedIds.remove(sessionId)
    }

    /// Returns whether `sessionId` is currently marked unread.
    public static func isUnread(sessionId: String, state: SessionHubState) -> Bool {
        state.unreadSince[sessionId] != nil
    }

    /// Returns the number of distinct non-archived unread sessions among `sessionIds`.
    public static func unreadCount(among sessionIds: [String], state: SessionHubState) -> Int {
        var seen = Set<String>()
        seen.reserveCapacity(sessionIds.count)
        var count = 0
        for id in sessionIds {
            guard seen.insert(id).inserted else { continue }
            if !state.archivedIds.contains(id), state.unreadSince[id] != nil {
                count += 1
            }
        }
        return count
    }

    /// Should `lastUpdated` be kept alive (exempt from idle `sessionTimeout` cleanup) under Today's Hub retention?
    /// Returns true if pinned, unread, active, or (keepTodaySessions && isSameDay(lastUpdated, now) && !archived).
    public static func shouldRetainSession(
        sessionId: String,
        status: AgentStatus,
        lastUpdated: Date,
        keepTodaySessions: Bool,
        now: Date = Date(),
        state: SessionHubState,
        calendar: Calendar = .current
    ) -> Bool {
        if isPinned(sessionId: sessionId, state: state) {
            return true
        }
        if isUnread(sessionId: sessionId, state: state) {
            return true
        }
        if status != .idle {
            return true
        }
        if keepTodaySessions
            && isSameDay(lastUpdated, now, calendar: calendar)
            && !state.archivedIds.contains(sessionId) {
            return true
        }
        return false
    }

    /// Filters and sorts entries for the expanded Hub list:
    /// - Excludes archived unless `includeArchived == true`
    /// - Applies `filter` (.all / .unread / .active / .pinned)
    /// - Applies case-insensitive `searchQuery` across title, projectName, prompt, source, gitBranch
    /// - Sorts: waitingApproval/waitingQuestion first, then pinned (by pin order), then running/processing, then unread, then most recently updated.
    public static func visibleEntries(
        _ entries: [SessionHubEntry],
        filter: SessionHubFilter,
        searchQuery: String,
        includeArchived: Bool = false,
        state: SessionHubState
    ) -> [SessionHubEntry] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        var pinRank: [String: Int] = [:]
        pinRank.reserveCapacity(state.pinnedIds.count)
        for (index, id) in state.pinnedIds.enumerated() where pinRank[id] == nil {
            pinRank[id] = index
        }

        let filtered = entries.filter { entry in
            if !includeArchived, state.archivedIds.contains(entry.sessionId) {
                return false
            }

            switch filter {
            case .all:
                break
            case .unread:
                guard isUnread(sessionId: entry.sessionId, state: state) else { return false }
            case .active:
                guard entry.status != .idle else { return false }
            case .pinned:
                guard pinRank[entry.sessionId] != nil else { return false }
            }

            if !trimmedQuery.isEmpty {
                let matches = entry.title.localizedCaseInsensitiveContains(trimmedQuery)
                    || entry.projectName.localizedCaseInsensitiveContains(trimmedQuery)
                    || entry.prompt.localizedCaseInsensitiveContains(trimmedQuery)
                    || entry.source.localizedCaseInsensitiveContains(trimmedQuery)
                    || entry.gitBranch.localizedCaseInsensitiveContains(trimmedQuery)
                if !matches {
                    return false
                }
            }

            return true
        }

        return filtered.sorted { lhs, rhs in
            let lhsWaiting = isWaitingStatus(lhs.status)
            let rhsWaiting = isWaitingStatus(rhs.status)
            if lhsWaiting != rhsWaiting {
                return lhsWaiting
            }

            let lhsPin = pinRank[lhs.sessionId] ?? Int.max
            let rhsPin = pinRank[rhs.sessionId] ?? Int.max
            if lhsPin != rhsPin {
                return lhsPin < rhsPin
            }

            let lhsWorking = isWorkingStatus(lhs.status)
            let rhsWorking = isWorkingStatus(rhs.status)
            if lhsWorking != rhsWorking {
                return lhsWorking
            }

            let lhsUnread = state.unreadSince[lhs.sessionId] != nil
            let rhsUnread = state.unreadSince[rhs.sessionId] != nil
            if lhsUnread != rhsUnread {
                return lhsUnread
            }

            if lhs.lastUpdated != rhs.lastUpdated {
                return lhs.lastUpdated > rhs.lastUpdated
            }

            return lhs.sessionId < rhs.sessionId
        }
    }

    /// Encodes `SessionHubState` into a deterministic JSON string for persistence.
    public static func encode(_ state: SessionHubState) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(state),
              let raw = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return raw
    }

    /// Decodes a persisted JSON string back into `SessionHubState`, falling back to empty state on corruption.
    public static func decode(_ raw: String) -> SessionHubState {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return SessionHubState()
        }

        let secondsDecoder = JSONDecoder()
        secondsDecoder.dateDecodingStrategy = .secondsSince1970
        if let decoded = try? secondsDecoder.decode(SessionHubState.self, from: data) {
            return decoded
        }

        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        if let decoded = try? isoDecoder.decode(SessionHubState.self, from: data) {
            return decoded
        }

        return SessionHubState()
    }

    private static func isWaitingStatus(_ status: AgentStatus) -> Bool {
        status == .waitingApproval || status == .waitingQuestion
    }

    private static func isWorkingStatus(_ status: AgentStatus) -> Bool {
        status == .running || status == .processing
    }
}
