import XCTest
@testable import CodeIsland
import CodeIslandCore

final class CompactAgentBadgesTests: XCTestCase {
    func testShowsClaudeAndGoogleAntigravitySideBySide() {
        var claude = SessionSnapshot()
        claude.source = "claude"
        claude.status = .idle
        claude.lastActivity = Date(timeIntervalSince1970: 100)

        var agy = SessionSnapshot()
        agy.source = "google-antigravity"
        agy.status = .running
        agy.lastActivity = Date(timeIntervalSince1970: 200)

        let entries = CompactAgentBadges.entries(from: ["c1": claude, "a1": agy], maxCount: 3)
        XCTAssertEqual(entries.map(\.source), ["google-antigravity", "claude"])
        XCTAssertEqual(entries.map(\.status), [.running, .idle])
    }

    func testDeduplicatesSameSourceKeepingHighestPriorityStatus() {
        var idleClaude = SessionSnapshot()
        idleClaude.source = "claude"
        idleClaude.status = .idle
        idleClaude.lastActivity = Date(timeIntervalSince1970: 300)

        var waitingClaude = SessionSnapshot()
        waitingClaude.source = "claude"
        waitingClaude.status = .waitingApproval
        waitingClaude.lastActivity = Date(timeIntervalSince1970: 100)

        var runningAgy = SessionSnapshot()
        runningAgy.source = "google-antigravity"
        runningAgy.status = .running
        runningAgy.lastActivity = Date(timeIntervalSince1970: 200)

        let entries = CompactAgentBadges.entries(
            from: ["c1": idleClaude, "c2": waitingClaude, "a1": runningAgy],
            maxCount: 3
        )
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].source, "claude")
        XCTAssertEqual(entries[0].status, .waitingApproval)
        XCTAssertEqual(entries[1].source, "google-antigravity")
        XCTAssertEqual(entries[1].status, .running)
    }

    func testRespectsMaxCountCap() {
        var sessions: [String: SessionSnapshot] = [:]
        for (idx, src) in ["claude", "google-antigravity", "codex", "cursor"].enumerated() {
            var s = SessionSnapshot()
            s.source = src
            s.status = .running
            s.lastActivity = Date(timeIntervalSince1970: TimeInterval(100 + idx))
            sessions[src] = s
        }
        let entries = CompactAgentBadges.entries(from: sessions, maxCount: 3)
        XCTAssertEqual(entries.count, 3)
    }
}
