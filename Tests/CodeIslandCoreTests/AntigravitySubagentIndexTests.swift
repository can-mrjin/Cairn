import XCTest
@testable import CodeIslandCore

final class AntigravitySubagentIndexTests: XCTestCase {
    private func makeBrainRoot() throws -> String {
        let root = NSTemporaryDirectory() + "antigravity-subagent-index-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: root) }
        return root
    }

    private func writeMembersJSON(_ json: String, under root: String, sessionDir: String) throws {
        let dir = "\(root)/\(sessionDir)/.system_generated/swarm"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try json.write(toFile: "\(dir)/members.json", atomically: true, encoding: .utf8)
    }

    // MARK: - parseSwarmMembers

    func testParseSwarmMembersMultiWorkerAndExcludesCoordinator() {
        let json = """
        {
          "title": "FlowIsland Hub & Vibe Alignment",
          "members": {
            "coordinator": {
              "conversation_id": "parent-coord-1",
              "role": "coordinator",
              "killed": false
            },
            "hub-core": {
              "conversation_id": "child-worker-a",
              "role": "worker",
              "killed": false
            },
            "subagent-tree": {
              "conversation_id": "child-worker-b",
              "role": "worker",
              "killed": false
            }
          }
        }
        """

        let links = AntigravitySubagentIndex.parseSwarmMembers(
            data: Data(json.utf8),
            fallbackParentId: "fallback-dir-id"
        )

        XCTAssertEqual(links, [
            AntigravitySubagentLink(
                childSessionId: "child-worker-a",
                parentSessionId: "parent-coord-1",
                roleName: "hub-core",
                swarmTitle: "FlowIsland Hub & Vibe Alignment"
            ),
            AntigravitySubagentLink(
                childSessionId: "child-worker-b",
                parentSessionId: "parent-coord-1",
                roleName: "subagent-tree",
                swarmTitle: "FlowIsland Hub & Vibe Alignment"
            ),
        ])
    }

    func testParseSwarmMembersKeepsKilledWorkersLinked() {
        let json = """
        {
          "title": "Refactor Swarm",
          "members": {
            "coordinator": {
              "conversation_id": "coord-1",
              "role": "coordinator"
            },
            "finished-helper": {
              "conversation_id": "worker-killed-1",
              "role": "worker",
              "killed": true
            }
          }
        }
        """

        let links = AntigravitySubagentIndex.parseSwarmMembers(
            data: Data(json.utf8),
            fallbackParentId: "dir-fallback"
        )

        XCTAssertEqual(links, [
            AntigravitySubagentLink(
                childSessionId: "worker-killed-1",
                parentSessionId: "coord-1",
                roleName: "finished-helper",
                swarmTitle: "Refactor Swarm"
            )
        ])
    }

    func testParseSwarmMembersFallsBackToParentDirectoryWhenCoordinatorMissing() {
        let json = """
        {
          "title": "   ",
          "members": {
            "verifier": {
              "conversation_id": "worker-v1",
              "role": "worker"
            }
          }
        }
        """

        let links = AntigravitySubagentIndex.parseSwarmMembers(
            data: Data(json.utf8),
            fallbackParentId: "dir-parent-uuid"
        )

        XCTAssertEqual(links, [
            AntigravitySubagentLink(
                childSessionId: "worker-v1",
                parentSessionId: "dir-parent-uuid",
                roleName: "verifier",
                swarmTitle: nil
            )
        ])
    }

    func testParseSwarmMembersIgnoresInvalidJSONAndEmptyMembers() {
        XCTAssertEqual(
            AntigravitySubagentIndex.parseSwarmMembers(
                data: Data("not-json{".utf8),
                fallbackParentId: "dir-1"
            ),
            []
        )

        XCTAssertEqual(
            AntigravitySubagentIndex.parseSwarmMembers(
                data: Data("{\"title\":\"Empty\"}".utf8),
                fallbackParentId: "dir-1"
            ),
            []
        )

        let selfLinkedJSON = """
        {
          "members": {
            "coordinator": { "conversation_id": "same-id", "role": "coordinator" },
            "bad-worker": { "conversation_id": "same-id", "role": "worker" },
            "blank-worker": { "conversation_id": "  ", "role": "worker" }
          }
        }
        """
        XCTAssertEqual(
            AntigravitySubagentIndex.parseSwarmMembers(
                data: Data(selfLinkedJSON.utf8),
                fallbackParentId: "dir-1"
            ),
            []
        )
    }

    // MARK: - loadLinks

    func testLoadLinksScansBrainDirectoryAndIgnoresMalformedSwarms() throws {
        let root = try makeBrainRoot()

        try writeMembersJSON(
            """
            {
              "title": "Swarm Alpha",
              "members": {
                "coordinator": { "conversation_id": "alpha-parent", "role": "coordinator" },
                "worker-1": { "conversation_id": "alpha-child-1", "role": "worker", "killed": false },
                "worker-2": { "conversation_id": "alpha-child-2", "role": "worker", "killed": true }
              }
            }
            """,
            under: root,
            sessionDir: "alpha-parent"
        )

        try writeMembersJSON(
            """
            {
              "members": {
                "helper": { "conversation_id": "beta-child-1", "role": "worker" }
              }
            }
            """,
            under: root,
            sessionDir: "beta-dir-parent"
        )

        // Malformed swarm file should be safely skipped without aborting the scan
        try writeMembersJSON("{corrupted", under: root, sessionDir: "corrupt-dir")

        // Regular session directory without swarm/members.json
        try FileManager.default.createDirectory(
            atPath: "\(root)/regular-session",
            withIntermediateDirectories: true
        )

        let links = AntigravitySubagentIndex.loadLinks(brainRoot: root)

        XCTAssertEqual(links.count, 3)
        XCTAssertEqual(
            links["alpha-child-1"],
            AntigravitySubagentLink(
                childSessionId: "alpha-child-1",
                parentSessionId: "alpha-parent",
                roleName: "worker-1",
                swarmTitle: "Swarm Alpha"
            )
        )
        XCTAssertEqual(
            links["alpha-child-2"],
            AntigravitySubagentLink(
                childSessionId: "alpha-child-2",
                parentSessionId: "alpha-parent",
                roleName: "worker-2",
                swarmTitle: "Swarm Alpha"
            )
        )
        XCTAssertEqual(
            links["beta-child-1"],
            AntigravitySubagentLink(
                childSessionId: "beta-child-1",
                parentSessionId: "beta-dir-parent",
                roleName: "helper",
                swarmTitle: nil
            )
        )
        XCTAssertNil(links["alpha-parent"])
    }

    func testLoadLinksMissingRootReturnsEmpty() {
        let missing = NSTemporaryDirectory() + "nonexistent-brain-" + UUID().uuidString
        XCTAssertTrue(AntigravitySubagentIndex.loadLinks(brainRoot: missing).isEmpty)
        XCTAssertTrue(AntigravitySubagentIndex.defaultBrainRoot.hasSuffix("/.gemini/antigravity/brain"))
    }

    func testLoadLinksMaxRecentDirectoriesLimitsScanToNewestEntries() throws {
        let fm = FileManager.default
        let root = NSTemporaryDirectory() + "ag-brain-recent-" + UUID().uuidString
        defer { try? fm.removeItem(atPath: root) }

        let olderDir = "\(root)/older-swarm"
        let newerDir = "\(root)/newer-swarm"
        try fm.createDirectory(atPath: "\(olderDir)/.system_generated/swarm", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: "\(newerDir)/.system_generated/swarm", withIntermediateDirectories: true)

        try Data("""
        {"title":"Old","members":{"coordinator":{"conversation_id":"older-parent"},"w":{"conversation_id":"older-child"}}}
        """.utf8).write(to: URL(fileURLWithPath: "\(olderDir)/.system_generated/swarm/members.json"))
        try Data("""
        {"title":"New","members":{"coordinator":{"conversation_id":"newer-parent"},"w":{"conversation_id":"newer-child"}}}
        """.utf8).write(to: URL(fileURLWithPath: "\(newerDir)/.system_generated/swarm/members.json"))

        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: olderDir)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: newerDir)

        let bounded = AntigravitySubagentIndex.loadLinks(brainRoot: root, maxRecentDirectories: 1)
        XCTAssertEqual(bounded["newer-child"]?.parentSessionId, "newer-parent")
        XCTAssertNil(bounded["older-child"])

        let full = AntigravitySubagentIndex.loadLinks(brainRoot: root)
        XCTAssertEqual(full["newer-child"]?.parentSessionId, "newer-parent")
        XCTAssertEqual(full["older-child"]?.parentSessionId, "older-parent")
    }

    // MARK: - ChildAgentNotificationPolicy

    func testChildAgentNotificationPolicyRootOnly() {
        XCTAssertTrue(
            ChildAgentNotificationPolicy.shouldNotifyCompletion(
                isChildSession: false,
                remainingRunningSiblings: 2,
                timing: .rootOnly
            )
        )
        XCTAssertFalse(
            ChildAgentNotificationPolicy.shouldNotifyCompletion(
                isChildSession: true,
                remainingRunningSiblings: 2,
                timing: .rootOnly
            )
        )
        XCTAssertFalse(
            ChildAgentNotificationPolicy.shouldNotifyCompletion(
                isChildSession: true,
                remainingRunningSiblings: 0,
                timing: .rootOnly
            )
        )
        // Default timing is .rootOnly
        XCTAssertFalse(ChildAgentNotificationPolicy.shouldNotifyCompletion(isChildSession: true))
        XCTAssertTrue(ChildAgentNotificationPolicy.shouldNotifyCompletion(isChildSession: false))
    }

    func testChildAgentNotificationPolicyAllFinished() {
        XCTAssertTrue(
            ChildAgentNotificationPolicy.shouldNotifyCompletion(
                isChildSession: false,
                remainingRunningSiblings: 3,
                timing: .allFinished
            )
        )
        XCTAssertFalse(
            ChildAgentNotificationPolicy.shouldNotifyCompletion(
                isChildSession: true,
                remainingRunningSiblings: 1,
                timing: .allFinished
            )
        )
        XCTAssertTrue(
            ChildAgentNotificationPolicy.shouldNotifyCompletion(
                isChildSession: true,
                remainingRunningSiblings: 0,
                timing: .allFinished
            )
        )
    }

    func testChildAgentNotificationPolicyEveryCompletion() {
        XCTAssertTrue(
            ChildAgentNotificationPolicy.shouldNotifyCompletion(
                isChildSession: false,
                remainingRunningSiblings: 5,
                timing: .everyCompletion
            )
        )
        XCTAssertTrue(
            ChildAgentNotificationPolicy.shouldNotifyCompletion(
                isChildSession: true,
                remainingRunningSiblings: 5,
                timing: .everyCompletion
            )
        )
        XCTAssertTrue(
            ChildAgentNotificationPolicy.shouldNotifyCompletion(
                isChildSession: true,
                remainingRunningSiblings: 0,
                timing: .everyCompletion
            )
        )
    }

    func testChildAgentNotificationTimingCodableAndCaseIterable() throws {
        XCTAssertEqual(ChildAgentNotificationTiming.allCases, [.rootOnly, .allFinished, .everyCompletion])
        let encoded = try JSONEncoder().encode(ChildAgentNotificationTiming.allFinished)
        let decoded = try JSONDecoder().decode(ChildAgentNotificationTiming.self, from: encoded)
        XCTAssertEqual(decoded, .allFinished)
    }
}
