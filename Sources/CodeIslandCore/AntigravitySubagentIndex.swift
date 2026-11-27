import Foundation

public struct AntigravitySubagentLink: Sendable, Equatable {
    public let childSessionId: String
    public let parentSessionId: String
    public let roleName: String
    public let swarmTitle: String?

    public init(
        childSessionId: String,
        parentSessionId: String,
        roleName: String,
        swarmTitle: String? = nil
    ) {
        self.childSessionId = childSessionId
        self.parentSessionId = parentSessionId
        self.roleName = roleName
        self.swarmTitle = swarmTitle
    }
}

public enum ChildAgentNotificationTiming: String, CaseIterable, Sendable, Codable {
    case rootOnly
    case allFinished
    case everyCompletion
}

public enum ChildAgentNotificationPolicy {
    /// Returns true if a completion sound / notification / unread badge should fire for this event.
    /// - `.rootOnly`: only when `!isChildSession`
    /// - `.allFinished`: when `!isChildSession` OR `remainingRunningSiblings == 0`
    /// - `.everyCompletion`: always true
    public static func shouldNotifyCompletion(
        isChildSession: Bool,
        remainingRunningSiblings: Int = 0,
        timing: ChildAgentNotificationTiming = .rootOnly
    ) -> Bool {
        switch timing {
        case .rootOnly:
            return !isChildSession
        case .allFinished:
            return !isChildSession || remainingRunningSiblings <= 0
        case .everyCompletion:
            return true
        }
    }
}

public enum AntigravitySubagentIndex {
    /// Default root: `~/.gemini/antigravity/brain`
    public static var defaultBrainRoot: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity/brain", isDirectory: true)
            .path
    }

    private struct SwarmMembersFile: Decodable {
        let title: String?
        let members: [String: SwarmMemberRecord]?
    }

    private struct SwarmMemberRecord: Decodable {
        let conversationId: String?
        let role: String?
        let killed: Bool?

        enum CodingKeys: String, CodingKey {
            case conversationId = "conversation_id"
            case role
            case killed
        }
    }

    private struct SubagentMessageRecord: Decodable {
        struct RenderDetails: Decodable {
            let messageTitle: String?
        }

        let recipient: String?
        let sender: String?
        let timestamp: String?
        let renderDetails: RenderDetails?
    }

    /// O(1) lookup for a non-Swarm `invoke_subagent` child conversation.
    /// Antigravity writes `<brainRoot>/<childId>/.system_generated/messages/<uuid>.json`
    /// with `"renderDetails": {"messageTitle": "Message from Parent Agent"}` and
    /// `"sender": "<parentConversationId>"`.
    public static func loadInvokeSubagentLink(
        forSessionId sessionId: String,
        brainRoot: String? = nil
    ) -> AntigravitySubagentLink? {
        let trimmedId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !trimmedId.contains("/"), !trimmedId.hasPrefix(".") else {
            return nil
        }
        let root = brainRoot ?? defaultBrainRoot
        let messagesDir = "\(root)/\(trimmedId)/.system_generated/messages"
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: messagesDir) else {
            return nil
        }

        var earliestMatch: (timestamp: String, parentId: String)?
        for entry in entries.sorted() where entry.hasSuffix(".json") && entry != "read.json" {
            let path = "\(messagesDir)/\(entry)"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let record = try? JSONDecoder().decode(SubagentMessageRecord.self, from: data) else {
                continue
            }
            guard record.renderDetails?.messageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) == "Message from Parent Agent" else {
                continue
            }
            guard let parentId = nonEmptyTrimmed(record.sender),
                  parentId != trimmedId,
                  !parentId.contains("/") else {
                continue
            }
            if let recipient = nonEmptyTrimmed(record.recipient), recipient != trimmedId {
                continue
            }
            let ts = record.timestamp ?? ""
            if let current = earliestMatch {
                if !ts.isEmpty && (current.timestamp.isEmpty || ts < current.timestamp) {
                    earliestMatch = (ts, parentId)
                }
            } else {
                earliestMatch = (ts, parentId)
            }
        }

        guard let match = earliestMatch else { return nil }
        return AntigravitySubagentLink(
            childSessionId: trimmedId,
            parentSessionId: match.parentId,
            roleName: "subagent-\(String(trimmedId.suffix(4)))",
            swarmTitle: nil
        )
    }

    /// Scans `<brainRoot>/*/.system_generated/swarm/members.json` and, for any
    /// active `candidateSessionIds` not present in Swarm rosters, checks O(1)
    /// `invoke_subagent` parent-agent message records.
    ///
    /// Pass `maxRecentDirectories` to bound synchronous main-thread lookups to
    /// the N most recently modified conversation directories via a single
    /// `getattrlistbulk` directory enumeration.
    public static func loadLinks(
        brainRoot: String? = nil,
        candidateSessionIds: [String] = [],
        maxRecentDirectories: Int? = nil
    ) -> [String: AntigravitySubagentLink] {
        let root = brainRoot ?? defaultBrainRoot
        let fm = FileManager.default
        var links: [String: AntigravitySubagentLink] = [:]
        let orderedEntries: [String]
        if let limit = maxRecentDirectories, limit > 0 {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            if let urls = try? fm.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) {
                orderedEntries = urls
                    .map { url -> (name: String, mtime: Date) in
                        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        return (url.lastPathComponent, mtime)
                    }
                    .sorted { lhs, rhs in
                        if lhs.mtime != rhs.mtime { return lhs.mtime > rhs.mtime }
                        return lhs.name < rhs.name
                    }
                    .prefix(limit)
                    .map(\.name)
            } else {
                orderedEntries = []
            }
        } else {
            orderedEntries = ((try? fm.contentsOfDirectory(atPath: root)) ?? []).sorted()
        }

        for entry in orderedEntries {
            guard !entry.isEmpty, !entry.hasPrefix(".") else { continue }
            let membersPath = "\(root)/\(entry)/.system_generated/swarm/members.json"
            guard fm.fileExists(atPath: membersPath),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: membersPath)) else {
                continue
            }
            for link in parseSwarmMembers(data: data, fallbackParentId: entry) {
                links[link.childSessionId] = link
            }
        }
        for candidateId in candidateSessionIds where links[candidateId] == nil {
            if let direct = loadInvokeSubagentLink(forSessionId: candidateId, brainRoot: root) {
                links[candidateId] = direct
            }
        }
        return links
    }

    public static func parseSwarmMembers(data: Data, fallbackParentId: String) -> [AntigravitySubagentLink] {
        guard let file = try? JSONDecoder().decode(SwarmMembersFile.self, from: data),
              let members = file.members,
              !members.isEmpty else {
            return []
        }

        let trimmedTitle = file.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let swarmTitle = (trimmedTitle?.isEmpty == false) ? trimmedTitle : nil

        let coordinatorConversationId = resolveCoordinatorConversationId(in: members)
        let fallback = fallbackParentId.trimmingCharacters(in: .whitespacesAndNewlines)
        let parentSessionId = coordinatorConversationId ?? fallback
        guard !parentSessionId.isEmpty else { return [] }

        var links: [AntigravitySubagentLink] = []
        links.reserveCapacity(members.count)

        for (rawRoleName, record) in members {
            let roleName = rawRoleName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !roleName.isEmpty, !isCoordinator(key: roleName, record: record) else {
                continue
            }
            guard let childSessionId = nonEmptyTrimmed(record.conversationId),
                  childSessionId != parentSessionId else {
                continue
            }
            // Keep killed workers linked so previously spawned cards stay folded under their coordinator.
            links.append(AntigravitySubagentLink(
                childSessionId: childSessionId,
                parentSessionId: parentSessionId,
                roleName: roleName,
                swarmTitle: swarmTitle
            ))
        }

        links.sort {
            if $0.roleName != $1.roleName {
                return $0.roleName < $1.roleName
            }
            return $0.childSessionId < $1.childSessionId
        }
        return links
    }

    private static func resolveCoordinatorConversationId(in members: [String: SwarmMemberRecord]) -> String? {
        if let explicit = members.first(where: { $0.value.role?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "coordinator" }),
           let id = nonEmptyTrimmed(explicit.value.conversationId) {
            return id
        }
        if let named = members.first(where: { $0.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "coordinator" }),
           let id = nonEmptyTrimmed(named.value.conversationId) {
            return id
        }
        return nil
    }

    private static func isCoordinator(key: String, record: SwarmMemberRecord) -> Bool {
        if let role = record.role?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           role == "coordinator" {
            return true
        }
        return key.lowercased() == "coordinator"
    }

    private static func nonEmptyTrimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
