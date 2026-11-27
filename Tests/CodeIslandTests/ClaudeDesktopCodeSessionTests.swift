import XCTest
@testable import CodeIsland
import CodeIslandCore

/// A Claude Code session run from Claude Desktop's Code tab jumps to that exact
/// session through `claude://code/continue?session=<local_…>`. The hook's
/// session_id is the CLI's id, which that link refuses; Claude Desktop's own id
/// arrives from CLAUDE_CODE_HOST_SESSION_ID via the bridge.
final class ClaudeDesktopCodeSessionTests: XCTestCase {
    private let hostId = "local_835c10bc-3a81-46b9-80c3-b5356e034bd6"

    func testAcceptsOnlyTheShapeClaudeDesktopsLinkAccepts() {
        XCTAssertTrue(ClaudeDesktopCodeSession.isValidHostSessionId(hostId))
        XCTAssertTrue(ClaudeDesktopCodeSession.isValidHostSessionId("local_a"))
        XCTAssertTrue(ClaudeDesktopCodeSession.isValidHostSessionId("local_" + String(repeating: "a", count: 64)))

        for bad in [
            "c171108a-2861-4f57-bc58-d75009ec9c19",    // the CLI's id: refused by the link
            "last",                                    // the link's own keyword, not a session
            "local_",
            "local_" + String(repeating: "a", count: 65),
            "local_abc&session=other",                  // must not smuggle query parameters
            "local_../../settings",
            "local_ab cd",
            "local_ábc",
            "LOCAL_abc",
        ] {
            XCTAssertFalse(ClaudeDesktopCodeSession.isValidHostSessionId(bad), bad)
            XCTAssertNil(ClaudeDesktopCodeSession.deepLinkURL(hostSessionId: bad), bad)
        }
    }

    func testDeepLinkOpensThatSession() {
        XCTAssertEqual(
            ClaudeDesktopCodeSession.deepLinkURL(hostSessionId: hostId)?.absoluteString,
            "claude://code/continue?session=\(hostId)"
        )
        XCTAssertEqual(
            ClaudeDesktopCodeSession.epitaxyDeepLinkURL(hostSessionId: hostId)?.absoluteString,
            "claude://claude.ai/epitaxy/\(hostId)"
        )
    }

    func testResolvesHostSessionIdFromClaude3PCodeSessionStore() throws {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-code-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let orgDir = tempHome.appendingPathComponent(
            "Library/Application Support/Claude-3p/claude-code-sessions/acct/org",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: orgDir, withIntermediateDirectories: true)

        let cliId = "da5021d8-f140-460b-8457-d1bdddce6a68"
        let priorId = "8b0d3c50-84e4-47da-8b7e-408e10318982"
        let json = """
        {"sessionId":"\(hostId)","cliSessionId":"\(cliId)","priorCliSessionIds":["\(priorId)"],"title":"修改处换行"}
        """
        try Data(json.utf8).write(to: orgDir.appendingPathComponent("\(hostId).json"))

        XCTAssertEqual(
            ClaudeDesktopCodeSession.resolveHostSessionId(forCliSessionId: cliId, home: tempHome),
            hostId
        )
        XCTAssertEqual(
            ClaudeDesktopCodeSession.resolveHostSessionId(forCliSessionId: priorId, home: tempHome),
            hostId
        )
        XCTAssertNil(
            ClaudeDesktopCodeSession.resolveHostSessionId(forCliSessionId: "00000000-0000-0000-0000-000000000000", home: tempHome)
        )
    }

    func testRecentSessionMetadataIndexCapturesForkedFromSessionId() throws {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-code-fork-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let orgDir = tempHome.appendingPathComponent(
            "Library/Application Support/Claude-3p/claude-code-sessions/acct/org",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: orgDir, withIntermediateDirectories: true)

        let parentHost = "local_69a92321-31d0-4fc4-9a5a-fdd090c3fc64"
        let parentCli = "ee4fffe0-25df-4130-b1da-82d294c7c5a6"
        let forkHost = "local_c62147ff-cf30-458b-b1c0-2672fbcca556"
        let forkCli = "4e9cb8c1-9b8f-4a21-8b13-fef81ac70c3a"
        let forkPrior = "c62147ff-cf30-458b-b1c0-2672fbcca556"

        try Data("""
        {"sessionId":"\(parentHost)","cliSessionId":"\(parentCli)","title":"Main chat"}
        """.utf8).write(to: orgDir.appendingPathComponent("\(parentHost).json"))
        try Data("""
        {"sessionId":"\(forkHost)","cliSessionId":"\(forkCli)","priorCliSessionIds":["\(forkPrior)"],"forkedFromSessionId":"\(parentHost)","title":"Main chat (fork)"}
        """.utf8).write(to: orgDir.appendingPathComponent("\(forkHost).json"))

        let index = ClaudeDesktopCodeSession.recentSessionMetadataIndex(home: tempHome)
        XCTAssertEqual(index[parentCli], .init(hostSessionId: parentHost, forkedFromHostSessionId: nil))
        XCTAssertEqual(index[forkCli], .init(hostSessionId: forkHost, forkedFromHostSessionId: parentHost))
        XCTAssertEqual(index[forkPrior], .init(hostSessionId: forkHost, forkedFromHostSessionId: parentHost))
    }

    func testHostIdIsCapturedFromTheHookPayload() throws {
        var sessions: [String: SessionSnapshot] = ["s": SessionSnapshot()]
        extractMetadata(into: &sessions, sessionId: "s", event: try makeEvent(["_claude_desktop_session": hostId]))
        XCTAssertEqual(sessions["s"]?.claudeDesktopSessionId, hostId)
    }

    func testMalformedHostIdIsDropped() throws {
        var sessions: [String: SessionSnapshot] = ["s": SessionSnapshot()]
        extractMetadata(into: &sessions, sessionId: "s", event: try makeEvent(["_claude_desktop_session": "local_x&y=1"]))
        XCTAssertNil(sessions["s"]?.claudeDesktopSessionId, "it ends up in a URL on click")
    }

    func testHostIdIsCapturedFromAPluginsEnvBlock() throws {
        var sessions: [String: SessionSnapshot] = ["s": SessionSnapshot()]
        extractMetadata(
            into: &sessions, sessionId: "s",
            event: try makeEvent(["_env": [ClaudeDesktopCodeSession.hostSessionEnvKey: hostId]])
        )
        XCTAssertEqual(sessions["s"]?.claudeDesktopSessionId, hostId)
    }

    func testHostIdSurvivesSessionStart() throws {
        // SessionStart rebuilds the card after the common extraction ran, and
        // it is the first hook every Code-tab session sends (and again after
        // /clear or a compaction).
        var sessions: [String: SessionSnapshot] = [:]
        _ = reduceEvent(sessions: &sessions, event: try makeEvent(["_claude_desktop_session": hostId]), maxHistory: 10)
        XCTAssertEqual(sessions["s"]?.claudeDesktopSessionId, hostId)
    }

    func testASubagentHookFillsAParentThatHasNoHostIdYet() throws {
        // Subagents run inside the same CLI, so they carry the same host id.
        var sessions: [String: SessionSnapshot] = ["s": SessionSnapshot()]
        let event = try makeEvent([
            "hook_event_name": "PreToolUse", "agent_id": "a1", "_claude_desktop_session": hostId,
        ])
        XCTAssertNotNil(event.agentId)
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)
        XCTAssertEqual(sessions["s"]?.claudeDesktopSessionId, hostId)
    }

    func testSessionsFileWithoutTheFieldStillDecodes() throws {
        // sessions.json written before the field existed.
        let json = #"[{"sessionId":"s","source":"claude","startTime":"2026-09-28T00:00:00Z","lastActivity":"2026-09-28T00:00:00Z"}]"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode([PersistedSession].self, from: Data(json.utf8))
        XCTAssertNil(restored.first?.claudeDesktopSessionId)
    }

    private func makeEvent(_ extra: [String: Any]) throws -> HookEvent {
        var payload: [String: Any] = ["hook_event_name": "SessionStart", "session_id": "s"]
        for (key, value) in extra { payload[key] = value }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try XCTUnwrap(HookEvent(from: data))
    }
}
