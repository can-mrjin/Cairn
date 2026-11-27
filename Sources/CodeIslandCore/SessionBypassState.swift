import Foundation

public enum SessionBypassMode: String, Sendable, Codable, Equatable {
    case off
    case thisTurn
    case session
}

public enum BatchApprovalAction: String, Sendable, Equatable {
    case allowAll
    case denyAll
}

public struct CompactionProgress: Sendable, Equatable {
    public let startedAt: Date

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }

    public func elapsedSeconds(at now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(startedAt)))
    }

    public func formattedElapsed(at now: Date = Date()) -> String {
        let total = elapsedSeconds(at: now)
        if total < 60 {
            return "\(total)s"
        }
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%dm %02ds", minutes, seconds)
    }
}

public struct SessionBypassStore: Sendable, Equatable {
    public private(set) var modes: [String: SessionBypassMode]
    public private(set) var compacting: [String: CompactionProgress]

    public init(
        modes: [String: SessionBypassMode] = [:],
        compacting: [String: CompactionProgress] = [:]
    ) {
        self.modes = modes.filter { $0.value != .off }
        self.compacting = compacting
    }

    public func mode(for sessionId: String) -> SessionBypassMode {
        modes[sessionId] ?? .off
    }

    public func shouldAutoApprove(sessionId: String) -> Bool {
        mode(for: sessionId) != .off
    }

    public mutating func setMode(_ mode: SessionBypassMode, for sessionId: String) {
        if mode == .off {
            modes.removeValue(forKey: sessionId)
        } else {
            modes[sessionId] = mode
        }
    }

    /// Clears `.thisTurn` bypass when a turn finishes (`Stop` / `idle`), preserving `.session`.
    public mutating func handleTurnEnded(sessionId: String) {
        if modes[sessionId] == .thisTurn {
            modes.removeValue(forKey: sessionId)
        }
    }

    public mutating func removeSession(_ sessionId: String) {
        modes.removeValue(forKey: sessionId)
        compacting.removeValue(forKey: sessionId)
    }

    // MARK: - Compaction tracking

    public func compaction(for sessionId: String) -> CompactionProgress? {
        compacting[sessionId]
    }

    public mutating func startCompaction(sessionId: String, at now: Date = Date()) {
        if compacting[sessionId] == nil {
            compacting[sessionId] = CompactionProgress(startedAt: now)
        }
    }

    public mutating func finishCompaction(sessionId: String) {
        compacting.removeValue(forKey: sessionId)
    }

    public static func isCompactionStartEvent(_ eventName: String) -> Bool {
        let canonical = canonicalEventKey(eventName)
        return compactionStartKeys.contains(canonical)
    }

    public static func isCompactionEndEvent(_ eventName: String) -> Bool {
        let canonical = canonicalEventKey(eventName)
        return compactionEndKeys.contains(canonical)
    }

    // MARK: - Event Matching Helpers

    private static let compactionStartKeys: Set<String> = [
        "precompact",
        "compactstart",
        "compactionstart",
        "contextcompacting",
        "contextcompactstart",
        "autocompactstart",
        "compacting",
    ]

    private static let compactionEndKeys: Set<String> = [
        "postcompact",
        "compactcomplete",
        "compactend",
        "compactioncomplete",
        "compactionend",
        "contextcompacted",
        "contextcompactcomplete",
        "autocompactcomplete",
        "autocompactend",
        "stop",
        "pretooluse",
        "posttooluse",
        "permissionrequest",
        "userpromptsubmit",
        "sessionstart",
        "sessionend",
        "interrupt",
        "afteragentresponse",
        "agentturnsettled",
        "taskroundcomplete",
    ]

    private static func canonicalEventKey(_ eventName: String) -> String {
        let trimmed = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let normalized = EventNormalizer.normalize(trimmed)
        return normalized
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }
}
