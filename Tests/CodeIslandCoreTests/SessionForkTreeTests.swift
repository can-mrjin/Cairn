import XCTest
@testable import CodeIslandCore

final class SessionForkTreeTests: XCTestCase {
    func testNestsForkedChildUnderParentAndHoistsFamilyToActiveChildRank() {
        // Fork is actively running (rank 0), unrelated session is rank 1,
        // parent conversation is idle (rank 2). The family should stay together
        // at the top with the parent first and its fork indented right below.
        let ids = ["fork1", "other", "parent"]
        let host: [String: String] = [
            "parent": "local_parent",
            "fork1": "local_fork1",
        ]
        let forkedFrom: [String: String] = [
            "fork1": "local_parent",
        ]

        let rows = SessionForkTree.flatten(
            ids: ids,
            hostId: { host[$0] },
            forkedFromHostId: { forkedFrom[$0] },
            isActive: { $0 == "fork1" }
        )

        XCTAssertEqual(rows.map(\.id), ["parent", "fork1", "other"])
        XCTAssertEqual(rows[0].depth, 0)
        XCTAssertEqual(rows[0].descendantBranchCount, 1)
        XCTAssertTrue(rows[0].hasActiveBranch)
        XCTAssertEqual(rows[1].depth, 1)
        XCTAssertTrue(rows[1].isLastSibling)
        XCTAssertEqual(rows[2].depth, 0)
        XCTAssertEqual(rows[2].descendantBranchCount, 0)
    }

    func testMultiLevelForksAndSiblingsTrackConnectorState() {
        let ids = ["root", "forkA", "forkA1", "forkB"]
        let host: [String: String] = [
            "root": "local_root",
            "forkA": "local_a",
            "forkA1": "local_a1",
            "forkB": "local_b",
        ]
        let forkedFrom: [String: String] = [
            "forkA": "local_root",
            "forkA1": "local_a",
            "forkB": "local_root",
        ]

        let rows = SessionForkTree.flatten(
            ids: ids,
            hostId: { host[$0] },
            forkedFromHostId: { forkedFrom[$0] }
        )

        XCTAssertEqual(rows.map(\.id), ["root", "forkA", "forkA1", "forkB"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2, 1])
        XCTAssertEqual(rows[0].descendantBranchCount, 3)
        XCTAssertFalse(rows[1].isLastSibling)
        XCTAssertTrue(rows[2].isLastSibling)
        XCTAssertEqual(rows[2].ancestorHasMoreSiblings, [true])
        XCTAssertTrue(rows[3].isLastSibling)
    }

    func testCollapsedParentHidesDescendantsAndRetainsActiveUnreadSummary() {
        let ids = ["root", "fork1", "other"]
        let host = ["root": "local_root", "fork1": "local_f1"]
        let forkedFrom = ["fork1": "local_root"]

        let rows = SessionForkTree.flatten(
            ids: ids,
            hostId: { host[$0] },
            forkedFromHostId: { forkedFrom[$0] },
            collapsedParentIds: ["root"],
            isActive: { $0 == "fork1" },
            isUnread: { $0 == "fork1" }
        )

        XCTAssertEqual(rows.map(\.id), ["root", "other"])
        XCTAssertTrue(rows[0].isCollapsed)
        XCTAssertEqual(rows[0].descendantBranchCount, 1)
        XCTAssertTrue(rows[0].hasActiveBranch)
        XCTAssertTrue(rows[0].hasUnreadBranch)
    }

    func testOrphanForkAndCyclesRemainTopLevelWithoutDroppingSessions() {
        let ids = ["orphan", "cycA", "cycB"]
        let host = ["orphan": "local_o", "cycA": "local_a", "cycB": "local_b"]
        let forkedFrom = [
            "orphan": "local_missing_parent",
            "cycA": "local_b",
            "cycB": "local_a",
        ]

        let rows = SessionForkTree.flatten(
            ids: ids,
            hostId: { host[$0] },
            forkedFromHostId: { forkedFrom[$0] }
        )

        XCTAssertEqual(Set(rows.map(\.id)), Set(ids))
        XCTAssertEqual(rows.first(where: { $0.id == "orphan" })?.depth, 0)
    }
}
