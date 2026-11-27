import Foundation

/// Claude Code sessions run from Claude Desktop's Code tab.
///
/// Claude Desktop starts each Code-tab session's CLI with its own id for that
/// session in `CLAUDE_CODE_HOST_SESSION_ID` (`local_<uuid>`). The hook's
/// `session_id` is the CLI's id, which Claude Desktop's links do not accept, so
/// this host id is the only handle that reaches one specific session.
public enum ClaudeDesktopCodeSession {
    /// Environment variable Claude Desktop sets on a Code-tab session's CLI.
    public static let hostSessionEnvKey = "CLAUDE_CODE_HOST_SESSION_ID"

    /// Host-level identity and optional fork parent resolved from Claude
    /// Desktop's on-disk `claude-code-sessions` store.
    public struct HostSessionMetadata: Equatable, Sendable {
        public let hostSessionId: String
        /// Parent conversation's `local_<uuid>` when this session was forked
        /// (including `(fork)` / `(fork N)` / `btw:` side-chats).
        public let forkedFromHostSessionId: String?

        public init(hostSessionId: String, forkedFromHostSessionId: String? = nil) {
            self.hostSessionId = hostSessionId
            self.forkedFromHostSessionId = forkedFromHostSessionId
        }
    }

    /// Whether `id` has the shape Claude Desktop's URL handler accepts for
    /// `?session=` — `^local_[A-Za-z0-9-]{1,64}$` (verified in the shipped app
    /// bundle, v2.9939). Anything else is refused there, so it is dropped here.
    public static func isValidHostSessionId(_ id: String) -> Bool {
        let prefix = "local_"
        guard id.hasPrefix(prefix) else { return false }
        let body = id.dropFirst(prefix.count)
        guard (1...64).contains(body.count) else { return false }
        return body.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-")
        }
    }

    /// `claude://code/continue?session=<id>` — Claude Desktop routes this to
    /// that session's screen; its own Dock menu and Spotlight entries use the
    /// same link. Nil for anything that is not a well-formed host id, so a
    /// click never opens a guessed URL.
    public static func deepLinkURL(hostSessionId: String) -> URL? {
        guard isValidHostSessionId(hostSessionId) else { return nil }
        return URL(string: "claude://code/continue?session=\(hostSessionId)")
    }

    /// `claude://claude.ai/epitaxy/<id>` — Direct Code-tab session route verified
    /// in Claude Desktop v6+ (`case Fu.ClaudeAI -> case Iu.Epitaxy`, matching
    /// `getSessionRoute(id) == "/epitaxy/\(id)"`). Works in both standard and
    /// 3P builds without requiring the OS entry-points flag that gates
    /// `claude://code/continue`.
    public static func epitaxyDeepLinkURL(hostSessionId: String) -> URL? {
        guard isValidHostSessionId(hostSessionId) else { return nil }
        return URL(string: "claude://claude.ai/epitaxy/\(hostSessionId)")
    }

    /// `claude://claude.ai/local_sessions/<id>` — Direct local session route
    /// handled by `Fu.ClaudeAI / Iu.LocalSessions` in Claude Desktop v6+.
    public static func localSessionDeepLinkURL(hostSessionId: String) -> URL? {
        guard isValidHostSessionId(hostSessionId) else { return nil }
        return URL(string: "claude://claude.ai/local_sessions/\(hostSessionId)")
    }

    /// Candidate `claude-code-sessions` directories across Claude Desktop 3P and
    /// standard installs.
    public static func sessionStoreRoots(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [URL] {
        let appSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let candidates = [
            appSupport.appendingPathComponent("Claude-3p/claude-code-sessions", isDirectory: true),
            appSupport.appendingPathComponent("Claude/claude-code-sessions", isDirectory: true),
        ]
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }

    private struct StoreSessionRecord: Decodable {
        let sessionId: String?
        let cliSessionId: String?
        let priorCliSessionIds: [String]?
        let forkedFromSessionId: String?
    }

    /// Builds a lookup table mapping every recent `cliSessionId`,
    /// `priorCliSessionIds` entry, and `local_<uuid>` host id to its
    /// `HostSessionMetadata` (including `forkedFromHostSessionId`) in one pass.
    ///
    /// Bounded to the most recently modified metadata files (`maxFilesToInspect`)
    /// so lookups stay fast (~1–2 ms) even with hundreds of historic files.
    public static func recentSessionMetadataIndex(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        maxFilesToInspect: Int = 120
    ) -> [String: HostSessionMetadata] {
        var candidates: [(url: URL, mtime: Date)] = []
        for root in sessionStoreRoots(home: home, fileManager: fileManager) {
            guard let accounts = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for account in accounts {
                guard let orgs = try? fileManager.contentsOfDirectory(
                    at: account,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for org in orgs {
                    guard let files = try? fileManager.contentsOfDirectory(
                        at: org,
                        includingPropertiesForKeys: [.contentModificationDateKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }
                    for file in files where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                        let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        candidates.append((file, mtime))
                    }
                }
            }
        }
        guard !candidates.isEmpty else { return [:] }
        candidates.sort { $0.mtime > $1.mtime }

        let decoder = JSONDecoder()
        var index: [String: HostSessionMetadata] = [:]
        for entry in candidates.prefix(maxFilesToInspect) {
            guard let data = try? Data(contentsOf: entry.url),
                  let record = try? decoder.decode(StoreSessionRecord.self, from: data),
                  let hostId = record.sessionId,
                  isValidHostSessionId(hostId) else { continue }
            let forkedFrom = record.forkedFromSessionId.flatMap { isValidHostSessionId($0) ? $0 : nil }
            let meta = HostSessionMetadata(hostSessionId: hostId, forkedFromHostSessionId: forkedFrom)
            if index[hostId] == nil {
                index[hostId] = meta
            }
            if let cliId = record.cliSessionId, !cliId.isEmpty, index[cliId] == nil {
                index[cliId] = meta
            }
            for priorId in record.priorCliSessionIds ?? [] where !priorId.isEmpty {
                if index[priorId] == nil {
                    index[priorId] = meta
                }
            }
        }
        return index
    }

    /// Resolves Claude Desktop's own `local_<uuid>` host session id from its
    /// on-disk `claude-code-sessions` metadata for a given CLI `sessionId`
    /// (`cliSessionId` or `priorCliSessionIds`). Needed on Claude Desktop v6 / 3P
    /// where `CLAUDE_CODE_HOST_SESSION_ID` is not exported into the CLI env.
    public static func resolveHostSessionId(
        forCliSessionId cliSessionId: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        maxFilesToInspect: Int = 80
    ) -> String? {
        let needle = cliSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        if isValidHostSessionId(needle) { return needle }
        return recentSessionMetadataIndex(
            home: home,
            fileManager: fileManager,
            maxFilesToInspect: maxFilesToInspect
        )[needle]?.hostSessionId
    }
}
