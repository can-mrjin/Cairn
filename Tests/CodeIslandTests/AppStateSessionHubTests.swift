import XCTest
@testable import CodeIsland
@testable import CodeIslandCore

@MainActor
final class AppStateSessionHubTests: XCTestCase {
    private var savedHubStateJSON: String = ""
    private var savedSilenceRulesJSON: String = ""
    private var savedChildTiming: ChildAgentNotificationTiming = .rootOnly

    override func setUp() {
        super.setUp()
        savedHubStateJSON = SettingsManager.shared.sessionHubStateJSON
        savedSilenceRulesJSON = SettingsManager.shared.silenceRulesJSON
        savedChildTiming = SettingsManager.shared.childAgentNotificationTiming
        SettingsManager.shared.sessionHubStateJSON = ""
        SettingsManager.shared.silenceRulesJSON = ""
        SettingsManager.shared.childAgentNotificationTiming = .rootOnly
    }

    override func tearDown() {
        SettingsManager.shared.sessionHubStateJSON = savedHubStateJSON
        SettingsManager.shared.silenceRulesJSON = savedSilenceRulesJSON
        SettingsManager.shared.childAgentNotificationTiming = savedChildTiming
        super.tearDown()
    }

    private func makeEvent(_ dict: [String: Any]) throws -> HookEvent {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try XCTUnwrap(HookEvent(from: data))
    }

    // MARK: - P1-1: Antigravity Swarm Disk Scan Throttle

    func testAntigravityLinkScanSkipsNonAntigravityHooksAndEnforcesCooldownOnMisses() throws {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func increment() { lock.lock(); value += 1; lock.unlock() }
            var count: Int { lock.lock(); defer { lock.unlock() }; return value }
        }

        let appState = AppState()
        let counter = Counter()
        appState.antigravityLinkLoader = {
            counter.increment()
            return [:]
        }

        // Non-Antigravity hooks must trigger zero disk scans.
        for source in ["claude", "codex", "cursor"] {
            let sid = "session-\(source)"
            let start = try makeEvent([
                "hook_event_name": "SessionStart",
                "session_id": sid,
                "_source": source,
                "cwd": "/tmp/proj",
            ])
            let tool = try makeEvent([
                "hook_event_name": "PreToolUse",
                "session_id": sid,
                "_source": source,
                "tool_name": "Read",
            ])
            appState.handleEvent(start)
            appState.handleEvent(tool)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(counter.count, 0, "Claude/Codex/Cursor hooks must never scan Antigravity swarm disk")

        // Even with an Antigravity coordinator present, repeated misses obey cooldown.
        var coordinator = SessionSnapshot()
        coordinator.source = "google-antigravity"
        appState.sessions["ag-coord"] = coordinator

        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        appState.refreshAntigravitySubagentLinks(force: true, triggerSessionId: "ag-coord", now: t0)
        // Wait for async scan to finish and clear in-flight flag.
        let exp1 = expectation(description: "first antigravity scan completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp1.fulfill() }
        wait(for: [exp1], timeout: 2.0)
        XCTAssertEqual(counter.count, 1)

        // Repeated force trigger for the same coordinator (miss) within 5s must NOT rescan.
        appState.refreshAntigravitySubagentLinks(force: true, triggerSessionId: "ag-coord", now: t0.addingTimeInterval(1.0))
        appState.refreshAntigravitySubagentLinks(force: true, triggerSessionId: "ag-coord", now: t0.addingTimeInterval(4.9))
        let exp2 = expectation(description: "miss cooldown held")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp2.fulfill() }
        wait(for: [exp2], timeout: 2.0)
        XCTAssertEqual(counter.count, 1, "Repeated misses within cooldown must not trigger disk scans")

        // Claude hook while Antigravity session exists still triggers zero scans.
        let claudeTool = try makeEvent([
            "hook_event_name": "PreToolUse",
            "session_id": "session-claude",
            "_source": "claude",
            "tool_name": "Bash",
        ])
        appState.handleEvent(claudeTool)
        let exp3 = expectation(description: "non-antigravity hook does not scan")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp3.fulfill() }
        wait(for: [exp3], timeout: 2.0)
        XCTAssertEqual(counter.count, 1)

        // Once cooldown elapses, next refresh is allowed.
        appState.refreshAntigravitySubagentLinks(force: true, triggerSessionId: "ag-coord", now: t0.addingTimeInterval(5.1))
        let exp4 = expectation(description: "post-cooldown scan runs")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp4.fulfill() }
        wait(for: [exp4], timeout: 2.0)
        XCTAssertEqual(counter.count, 2)
    }

    // MARK: - P1-2: Compaction Cleared on SessionStart / Interrupt / Permission / Question

    func testCompactionClearsOnSessionStartInterruptAndBlockingRequests() async throws {
        let appState = AppState()
        let sid = "compact-session"

        // Start an active turn so PreCompact is not absorbed as idle background compaction (#385).
        appState.handleEvent(try makeEvent([
            "hook_event_name": "UserPromptSubmit",
            "session_id": sid,
            "_source": "claude",
            "cwd": "/tmp/repo",
            "prompt": "Refactor module",
        ]))
        appState.handleEvent(try makeEvent([
            "hook_event_name": "PreCompact",
            "session_id": sid,
            "_source": "claude",
            "cwd": "/tmp/repo",
        ]))
        XCTAssertNotNil(appState.bypassStore.compaction(for: sid))

        // Claude Code ends `/compact` with SessionStart(source:"compact")
        appState.handleEvent(try makeEvent([
            "hook_event_name": "SessionStart",
            "session_id": sid,
            "source": "compact",
            "_source": "claude",
            "cwd": "/tmp/repo",
        ]))
        XCTAssertNil(appState.bypassStore.compaction(for: sid))

        // Interrupt clears compaction
        let codexSid = "compact-codex"
        appState.handleEvent(try makeEvent([
            "hook_event_name": "UserPromptSubmit",
            "session_id": codexSid,
            "_source": "codex",
            "cwd": "/tmp/repo",
            "prompt": "Run checks",
        ]))
        appState.handleEvent(try makeEvent([
            "hook_event_name": "PreCompact",
            "session_id": codexSid,
            "_source": "codex",
            "cwd": "/tmp/repo",
        ]))
        XCTAssertNotNil(appState.bypassStore.compaction(for: codexSid))
        appState.handleEvent(try makeEvent([
            "hook_event_name": "Interrupt",
            "session_id": codexSid,
            "_source": "codex",
            "cwd": "/tmp/repo",
        ]))
        XCTAssertNil(appState.bypassStore.compaction(for: codexSid))

        // Blocking permission request clears compaction and marks unread
        appState.bypassStore.startCompaction(sessionId: sid)
        let permEvent = try makeEvent([
            "hook_event_name": "PermissionRequest",
            "session_id": sid,
            "_source": "claude",
            "tool_name": "Bash",
            "tool_input": ["command": "echo hi"],
        ])
        let permTask = Task { @MainActor in
            await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
                appState.handlePermissionRequest(permEvent, continuation: continuation)
            }
        }
        await Task.yield()
        XCTAssertNil(appState.bypassStore.compaction(for: sid))
        XCTAssertTrue(appState.isSessionUnread(sid))
        appState.denyPermission(expectedSessionId: sid)
        _ = await permTask.value
    }

    // MARK: - P1-3: Prompt-Prefix Silence Re-Check & Non-Hook Intake Filtering

    func testUserPromptSubmitRechecksSilenceRulesAndRemovesSession() throws {
        let appState = AppState()
        let sid = "codex-mem-writer"

        // SessionStart has no prompt yet, so the card is created.
        appState.handleEvent(try makeEvent([
            "hook_event_name": "SessionStart",
            "session_id": sid,
            "_source": "codex",
            "cwd": "/Users/dev/project",
        ]))
        XCTAssertNotNil(appState.sessions[sid])

        // UserPromptSubmit reveals built-in preset prompt — session must be silenced and removed.
        appState.handleEvent(try makeEvent([
            "hook_event_name": "UserPromptSubmit",
            "session_id": sid,
            "_source": "codex",
            "cwd": "/Users/dev/project",
            "prompt": "## Memory Writing Agent\nPersist durable facts",
        ]))
        XCTAssertNil(appState.sessions[sid])
    }

    func testIntegrateDiscoveredAndCoworkUpdateRespectSilenceRules() {
        let appState = AppState()
        var config = SilenceRuleConfig()
        SessionSilenceFilter.addBlockedDirectory("/tmp/silenced-dir", to: &config)
        SettingsManager.shared.silenceRulesJSON = SessionSilenceFilter.encode(config)

        appState.integrateDiscovered([
            DiscoveredSession(
                sessionId: "disc-silenced-dir",
                cwd: "/tmp/silenced-dir/sub",
                tty: nil,
                model: nil,
                pid: nil,
                modifiedAt: Date(),
                recentMessages: [ChatMessage(isUser: true, text: "Hello")],
                source: "claude",
                transcriptPath: nil,
                status: .processing
            ),
            DiscoveredSession(
                sessionId: "disc-silenced-preset",
                cwd: "/Users/dev/app",
                tty: nil,
                model: nil,
                pid: nil,
                modifiedAt: Date(),
                recentMessages: [ChatMessage(isUser: true, text: "## Memory Writing Agent\nSave notes")],
                source: "codex",
                transcriptPath: nil,
                status: .processing
            ),
        ])
        XCTAssertNil(appState.sessions["disc-silenced-dir"])
        XCTAssertNil(appState.sessions["disc-silenced-preset"])

        let coworkMeta = CoworkSessionMetadata(
            sessionId: "local_12345678-0000-0000-0000-000000000001",
            cliSessionId: "cli-1",
            initialMessage: "Run task",
            userSelectedFolders: ["/tmp/silenced-dir"]
        )
        var audit = CoworkAuditState()
        audit.apply([CoworkAuditParser.event(fromLine: Data(CoworkAuditFixture.userPrompt.utf8))])
        appState.applyCoworkUpdate(CoworkSessionWatcher.SessionUpdate(
            sessionId: coworkMeta.sessionId,
            metadata: coworkMeta,
            audit: audit,
            transcriptPath: nil,
            lastActivity: Date(),
            isLive: true,
            promptsStarted: 1,
            turnsCompleted: 0,
            permissionsRequested: 0
        ))
        XCTAssertNil(appState.sessions[AppState.coworkSessionKey(coworkMeta.sessionId)])
    }

    // MARK: - P1-5: Unread Transitions Across Non-Hook & Blocking Paths

    func testUnreadTriggeredForCoworkAiWorkCodexAppServerAndTranscriptTransitions() throws {
        let appState = AppState()

        // 1. Cowork live completion
        let coworkId = "local_aaaaaaaa-0000-0000-0000-000000000001"
        let coworkKey = AppState.coworkSessionKey(coworkId)
        let coworkMeta = CoworkSessionMetadata(
            sessionId: coworkId,
            cliSessionId: "cli-cowork-unread",
            userSelectedFolders: ["/Users/dev/app"]
        )
        var coworkAudit = CoworkAuditState()
        coworkAudit.apply([
            CoworkAuditFixture.userPrompt,
            CoworkAuditFixture.assistantReply,
            CoworkAuditFixture.resultSuccess,
        ].map { CoworkAuditParser.event(fromLine: Data($0.utf8)) })
        appState.applyCoworkUpdate(CoworkSessionWatcher.SessionUpdate(
            sessionId: coworkId,
            metadata: coworkMeta,
            audit: coworkAudit,
            transcriptPath: nil,
            lastActivity: Date(),
            isLive: true,
            promptsStarted: 1,
            turnsCompleted: 1,
            permissionsRequested: 0
        ))
        XCTAssertTrue(appState.isSessionUnread(coworkKey))

        // 2. AiWork stream completion
        appState.aiworkStateDirOverride = "/nonexistent/codeisland-tests/agentix"
        let startFrame = try XCTUnwrap(AiWorkWatchClient.parseFrame(Data(
            #"{"kind":"event","category":"session","operation":"sessions.watch","event":{"name":"stream.started","phase":"start"},"data":{"session":{"session_id":"acp:coder:u1","cwd":"/tmp/proj","title":"T"}},"meta":{"session_id":"acp:coder:u1"}}"#.utf8
        )))
        let doneFrame = try XCTUnwrap(AiWorkWatchClient.parseFrame(Data(
            #"{"kind":"event","category":"session","operation":"sessions.watch","event":{"name":"stream.completed","phase":"end"},"data":{"final_text":"Done"},"meta":{"session_id":"acp:coder:u1"}}"#.utf8
        )))
        appState.handleAiWorkStreamEvent(name: "stream.started", frame: startFrame, agentId: "coder")
        XCTAssertFalse(appState.isSessionUnread("aiwork:acp:coder:u1"))
        appState.handleAiWorkStreamEvent(name: "stream.completed", frame: doneFrame, agentId: "coder")
        XCTAssertTrue(appState.isSessionUnread("aiwork:acp:coder:u1"))

        // 3. Codex AppServer thread/status/changed active -> idle
        let codexId = AppState.codexAppSessionPrefix + "thread-unread"
        let started = try XCTUnwrap(CodexAppServerClient.parseMessage(Data(
            #"{"jsonrpc":"2.0","method":"thread/started","params":{"thread":{"id":"thread-unread","cwd":"/repo","status":{"type":"active","activeFlags":[]}}}}"#.utf8
        )))
        let idled = try XCTUnwrap(CodexAppServerClient.parseMessage(Data(
            #"{"jsonrpc":"2.0","method":"thread/status/changed","params":{"threadId":"thread-unread","status":{"type":"idle"}}}"#.utf8
        )))
        appState.handleCodexAppServerMessage(started)
        XCTAssertFalse(appState.isSessionUnread(codexId))
        appState.handleCodexAppServerMessage(idled)
        XCTAssertTrue(appState.isSessionUnread(codexId))

        // 4. Transcript delta processing -> idle
        var codexCli = SessionSnapshot()
        codexCli.source = "codex"
        codexCli.status = .processing
        appState.sessions["codex-tail-unread"] = codexCli
        appState.applyTranscriptDelta(ConversationTailDelta(
            sessionId: "codex-tail-unread",
            lastUserPrompt: nil,
            lastAssistantMessage: "All done",
            turnStatus: .idle,
            hasActivity: true
        ))
        XCTAssertTrue(appState.isSessionUnread("codex-tail-unread"))
    }

    // MARK: - P1-7: Activation Generation Guard

    func testActivationGenerationInvalidatesSupersededRequest() {
        let genA = TerminalActivator.nextActivationGeneration()
        XCTAssertTrue(TerminalActivator.isCurrentActivationGeneration(genA))
        let genB = TerminalActivator.nextActivationGeneration()
        XCTAssertFalse(TerminalActivator.isCurrentActivationGeneration(genA))
        XCTAssertTrue(TerminalActivator.isCurrentActivationGeneration(genB))
    }

    // MARK: - P1-8: Stale Archive Rollover on Load

    func testLoadHubStateRollsOverStaleArchives() {
        let stale = SessionHubState(
            unreadSince: [:],
            pinnedIds: ["p1"],
            archivedIds: ["old-archived"],
            archivedDayKey: "2020-01-01"
        )
        SettingsManager.shared.sessionHubStateJSON = SessionHubEngine.encode(stale)

        let appState = AppState()
        XCTAssertTrue(appState.hubState.archivedIds.isEmpty, "Stale archives must clear on load")
        XCTAssertEqual(appState.hubState.pinnedIds, ["p1"])
    }

    // MARK: - P1-9: Child Completion Sibling Count

    func testShouldNotifyCompletionCountsSiblingsAcrossNonAntigravityCardsAndProviderMatchedParents() {
        SettingsManager.shared.childAgentNotificationTiming = .allFinished
        let appState = AppState()

        // Case A: Codex separate-mode child cards linked via `parentSessionId`
        var codexParent = SessionSnapshot()
        codexParent.source = "codex"
        codexParent.status = .running
        appState.sessions["codex-parent"] = codexParent

        var childA = SessionSnapshot()
        childA.source = "codex"
        childA.parentSessionId = "codex-parent"
        childA.status = .idle
        appState.sessions["codex-child-a"] = childA

        var childB = SessionSnapshot()
        childB.source = "codex"
        childB.parentSessionId = "codex-parent"
        childB.status = .running
        appState.sessions["codex-child-b"] = childB

        XCTAssertFalse(
            appState.shouldNotifyCompletionForSession("codex-child-a", isChild: true),
            "Must NOT notify while sibling codex-child-b is still running"
        )

        appState.sessions["codex-child-b"]?.status = .idle
        XCTAssertTrue(
            appState.shouldNotifyCompletionForSession("codex-child-a", isChild: true),
            "Should notify once all siblings have settled idle"
        )

        // Case B: Antigravity parent matched via `providerSessionId` with folded subagents
        var agParent = SessionSnapshot()
        agParent.source = "google-antigravity"
        agParent.providerSessionId = "conv-coord-1"
        agParent.status = .running
        var subRunning = SubagentState(agentId: "worker-2", agentType: "auditor")
        subRunning.status = .running
        agParent.subagents["worker-2"] = subRunning
        appState.sessions["card-coord-key"] = agParent
        appState.antigravitySubagentLinks["worker-1"] = AntigravitySubagentLink(
            childSessionId: "worker-1",
            parentSessionId: "conv-coord-1",
            roleName: "fixer"
        )

        XCTAssertFalse(
            appState.shouldNotifyCompletionForSession("worker-1", isChild: true),
            "Must resolve providerSessionId-keyed parent and see worker-2 still running"
        )

        appState.sessions["card-coord-key"]?.subagents["worker-2"]?.status = .idle
        XCTAssertTrue(
            appState.shouldNotifyCompletionForSession("worker-1", isChild: true),
            "Should notify once folded sibling worker-2 finishes"
        )
    }

    // MARK: - Antigravity Swarm Tree Folding & Synthesized Coordinator Parent

    func testAntigravitySwarmWorkersSynthesizeCoordinatorParentAndTrackStatus() throws {
        let appState = AppState()
        let parentId = "ag-coord-synth"
        let worker1Id = "ag-worker-5715"
        let worker2Id = "ag-worker-b8fb"

        // Confirm `gemini` source is also recognized as Antigravity-capable.
        XCTAssertTrue(AppState.isAntigravitySource("google-antigravity"))
        XCTAssertTrue(AppState.isAntigravitySource("antigravity"))
        XCTAssertTrue(AppState.isAntigravitySource("gemini"))

        appState.antigravityLinkLoader = {
            [
                worker1Id: AntigravitySubagentLink(
                    childSessionId: worker1Id,
                    parentSessionId: parentId,
                    roleName: "monitor",
                    swarmTitle: "Polish FlowIsland Notch"
                ),
                worker2Id: AntigravitySubagentLink(
                    childSessionId: worker2Id,
                    parentSessionId: parentId,
                    roleName: "slim-notch",
                    swarmTitle: "Polish FlowIsland Notch"
                ),
            ]
        }
        appState.antigravitySubagentLinks = appState.antigravityLinkLoader()

        // Two Swarm workers fire hooks before any coordinator hook arrives.
        appState.handleEvent(try makeEvent([
            "hook_event_name": "PreToolUse",
            "session_id": worker1Id,
            "_source": "google-antigravity",
            "cwd": "/tmp/flowisland",
            "tool_name": "Read",
            "model": "claude-sonnet-4-5",
        ]))
        appState.handleEvent(try makeEvent([
            "hook_event_name": "PreToolUse",
            "session_id": worker2Id,
            "_source": "gemini",
            "cwd": "/tmp/flowisland",
            "tool_name": "Edit",
            "model": "gemini-2.5-pro",
        ]))

        // Flat worker cards must be folded into a single synthesized coordinator card.
        XCTAssertNil(appState.sessions[worker1Id], "Worker 1 flat card must be removed after folding")
        XCTAssertNil(appState.sessions[worker2Id], "Worker 2 flat card must be removed after folding")

        let synthesized = try XCTUnwrap(appState.sessions[parentId], "Coordinator parent card must be synthesized")
        XCTAssertTrue(appState.synthesizedAntigravityParentIds.contains(parentId))
        XCTAssertEqual(synthesized.lastUserPrompt, "Polish FlowIsland Notch")
        XCTAssertEqual(synthesized.cwd, "/tmp/flowisland")
        XCTAssertEqual(synthesized.source, "google-antigravity")
        XCTAssertEqual(synthesized.status, .running)
        XCTAssertEqual(Set(synthesized.subagents.keys), [worker1Id, worker2Id])
        XCTAssertEqual(synthesized.subagents[worker1Id]?.agentType, "monitor")
        XCTAssertEqual(synthesized.subagents[worker2Id]?.agentType, "slim-notch")
        XCTAssertEqual(synthesized.subagents[worker1Id]?.status, .running)
        XCTAssertEqual(synthesized.subagents[worker2Id]?.status, .running)

        // Worker 1 finishes while Worker 2 is still running -> synthesized parent stays running.
        appState.handleEvent(try makeEvent([
            "hook_event_name": "Stop",
            "session_id": worker1Id,
            "_source": "google-antigravity",
            "cwd": "/tmp/flowisland",
        ]))
        XCTAssertNil(appState.sessions[worker1Id])
        XCTAssertEqual(appState.sessions[parentId]?.subagents[worker1Id]?.status, .idle)
        XCTAssertEqual(appState.sessions[parentId]?.subagents[worker2Id]?.status, .running)
        XCTAssertEqual(appState.sessions[parentId]?.status, .running)

        // Worker 2 finishes -> all subagents are idle, so synthesized parent transitions to idle.
        appState.handleEvent(try makeEvent([
            "hook_event_name": "Stop",
            "session_id": worker2Id,
            "_source": "gemini",
            "cwd": "/tmp/flowisland",
        ]))
        XCTAssertNil(appState.sessions[worker2Id])
        XCTAssertEqual(appState.sessions[parentId]?.subagents[worker2Id]?.status, .idle)
        XCTAssertEqual(appState.sessions[parentId]?.status, .idle)
    }

    func testRealCoordinatorHookPromotesSynthesizedParentAndPreservesSubagents() throws {
        let appState = AppState()
        let parentId = "ag-coord-promote"
        let workerId = "ag-worker-promote"

        let seededLinks = [
            workerId: AntigravitySubagentLink(
                childSessionId: workerId,
                parentSessionId: parentId,
                roleName: "verifier",
                swarmTitle: "Verify Build"
            ),
        ]
        appState.antigravityLinkLoader = { seededLinks }
        appState.antigravitySubagentLinks = seededLinks

        // Worker arrives first and synthesizes the coordinator card.
        appState.handleEvent(try makeEvent([
            "hook_event_name": "PreToolUse",
            "session_id": workerId,
            "_source": "google-antigravity",
            "cwd": "/tmp/repo",
            "tool_name": "Bash",
        ]))
        XCTAssertTrue(appState.synthesizedAntigravityParentIds.contains(parentId))
        XCTAssertEqual(appState.sessions[parentId]?.subagents.count, 1)
        XCTAssertEqual(appState.sessions[parentId]?.status, .running)

        // Real coordinator SessionStart arrives later: must promote the same card,
        // remove it from synthesized tracking, and preserve existing folded subagents.
        appState.handleEvent(try makeEvent([
            "hook_event_name": "SessionStart",
            "session_id": parentId,
            "_source": "google-antigravity",
            "cwd": "/tmp/repo",
        ]))
        XCTAssertFalse(appState.synthesizedAntigravityParentIds.contains(parentId))
        XCTAssertEqual(appState.sessions[parentId]?.subagents[workerId]?.agentType, "verifier")
        XCTAssertEqual(appState.sessions[parentId]?.lastUserPrompt, "Verify Build")

        // Real coordinator starts its own prompt -> takes ownership of prompt & status.
        appState.handleEvent(try makeEvent([
            "hook_event_name": "UserPromptSubmit",
            "session_id": parentId,
            "_source": "google-antigravity",
            "cwd": "/tmp/repo",
            "prompt": "Coordinate release verification",
        ]))
        XCTAssertEqual(appState.sessions[parentId]?.lastUserPrompt, "Coordinate release verification")
        XCTAssertEqual(appState.sessions[parentId]?.status, .processing)
        XCTAssertEqual(appState.sessions[parentId]?.subagents[workerId]?.agentType, "verifier")

        // When worker finishes now, real coordinator's own status must NOT be overridden to idle.
        appState.handleEvent(try makeEvent([
            "hook_event_name": "Stop",
            "session_id": workerId,
            "_source": "google-antigravity",
            "cwd": "/tmp/repo",
        ]))
        XCTAssertEqual(appState.sessions[parentId]?.subagents[workerId]?.status, .idle)
        XCTAssertEqual(appState.sessions[parentId]?.status, .processing)
    }

    // MARK: - Stable Creation-Time Ordering & Collapsed Bar Binding

    func testCardOrderNeverShiftsWhenNewerSessionIdlesAndOlderSessionRunsOrCompacts() throws {
        let appState = AppState()
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        var older = SessionSnapshot(startTime: base)
        older.source = "claude"
        older.status = .idle
        older.lastActivity = base.addingTimeInterval(10)

        var middle = SessionSnapshot(startTime: base.addingTimeInterval(60))
        middle.source = "codex"
        middle.status = .running
        middle.lastActivity = base.addingTimeInterval(70)

        var newest = SessionSnapshot(startTime: base.addingTimeInterval(120))
        newest.source = "google-antigravity"
        newest.status = .running
        newest.lastActivity = base.addingTimeInterval(125)

        appState.sessions = [
            "s-older": older,
            "s-middle": middle,
            "s-newest": newest,
        ]

        let expectedOrder = ["s-newest", "s-middle", "s-older"]
        XCTAssertEqual(appState.sessionListOrder(), expectedOrder)
        XCTAssertEqual(
            appState.hubVisibleSessionIds(filter: .all, searchQuery: "", showArchived: false, baseOrder: appState.sessionListOrder()),
            expectedOrder
        )

        // Newest session goes idle while older session starts running, gets fresh activity,
        // enters waitingApproval, and becomes unread — order must stay 100% unchanged.
        appState.sessions["s-newest"]?.status = .idle
        appState.sessions["s-older"]?.status = .running
        appState.sessions["s-older"]?.lastActivity = base.addingTimeInterval(999)
        appState.sessions["s-middle"]?.status = .waitingApproval
        appState.sessions["s-middle"]?.lastActivity = base.addingTimeInterval(1000)
        appState.toggleSessionRead("s-older")

        XCTAssertEqual(appState.sessionListOrder(), expectedOrder)
        XCTAssertEqual(
            appState.hubVisibleSessionIds(filter: .all, searchQuery: "", showArchived: false, baseOrder: appState.sessionListOrder()),
            expectedOrder
        )

        // Repeated SessionStart (e.g. Claude `/compact`) on the older session must preserve
        // its original creation time and never bump it to the top.
        appState.handleEvent(try makeEvent([
            "hook_event_name": "SessionStart",
            "session_id": "s-older",
            "source": "compact",
            "_source": "claude",
            "cwd": "/tmp/repo",
        ]))
        XCTAssertEqual(appState.sessions["s-older"]?.startTime, base)
        XCTAssertEqual(appState.sessionListOrder(), expectedOrder)
    }

    func testPrimaryDisplaySessionIdPrefersTopmostActiveInStableOrderAndFallsBackToTopIdle() {
        let appState = AppState()
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        var olderActive = SessionSnapshot(startTime: base)
        olderActive.source = "google-antigravity"
        olderActive.status = .processing
        olderActive.lastActivity = base.addingTimeInterval(500)

        var middleActive = SessionSnapshot(startTime: base.addingTimeInterval(60))
        middleActive.source = "codex"
        middleActive.status = .running
        middleActive.currentTool = "Bash"
        middleActive.lastActivity = base.addingTimeInterval(400)

        var newestActive = SessionSnapshot(startTime: base.addingTimeInterval(120))
        newestActive.source = "claude"
        newestActive.status = .running
        newestActive.lastActivity = base.addingTimeInterval(120)

        appState.sessions = [
            "s-older": olderActive,
            "s-middle": middleActive,
            "s-newest": newestActive,
        ]
        appState.activeSessionId = "s-older"
        appState.refreshDerivedState()

        // Case A: #1 newer session is .running and #2/#3 older sessions are active ->
        // stays locked to #1 in stable creation order (zero bouncing or rotation).
        XCTAssertEqual(appState.primaryDisplaySessionId, "s-newest")

        // Pinning an older active session makes it the explicit topmost active session.
        appState.toggleSessionPin("s-older")
        XCTAssertEqual(appState.primaryDisplaySessionId, "s-older")
        appState.toggleSessionPin("s-older")
        XCTAssertEqual(appState.primaryDisplaySessionId, "s-newest")

        // Case B: #1 newer session becomes .idle while #2/#3 are active ->
        // collapsed bar binds to the topmost active session (#2) so live work stays visible.
        appState.sessions["s-newest"]?.status = .idle
        XCTAssertEqual(appState.primaryDisplaySessionId, "s-middle")

        // When #2 also settles idle while #3 is still .processing, collapsed bar binds to #3.
        appState.sessions["s-middle"]?.status = .idle
        XCTAssertEqual(appState.primaryDisplaySessionId, "s-older")

        // Archiving the active session promotes #1 non-archived (idle) since no other active remains.
        appState.toggleSessionArchive("s-older")
        XCTAssertEqual(appState.primaryDisplaySessionId, "s-newest")
        appState.toggleSessionArchive("s-older")
        XCTAssertEqual(appState.primaryDisplaySessionId, "s-older")

        // Case C: All sessions .idle -> binds to #1 newest (or top pinned).
        appState.sessions["s-older"]?.status = .idle
        XCTAssertEqual(appState.primaryDisplaySessionId, "s-newest")

        appState.toggleSessionPin("s-middle")
        XCTAssertEqual(appState.primaryDisplaySessionId, "s-middle")
        appState.toggleSessionPin("s-middle")

        // Archiving all sessions falls back to #1 newest overall.
        appState.toggleSessionArchive("s-newest")
        XCTAssertEqual(appState.primaryDisplaySessionId, "s-middle")
        appState.toggleSessionArchive("s-middle")
        appState.toggleSessionArchive("s-older")
        XCTAssertEqual(appState.primaryDisplaySessionId, "s-newest")
    }

    // MARK: - Synchronous Swarm Link Check Before Attention Sound

    func testBrandNewSwarmWorkerStopResolvesParentSynchronouslyAndStaysSilentUnderRootOnly() throws {
        let watchedKeys = [
            SettingsKey.soundEnabled,
            SettingsKey.soundTaskComplete,
            SettingsKey.soundTaskError,
            SettingsKey.soundSessionStart,
            SettingsKey.quietHoursEnabled,
            SettingsKey.autoMuteWhenAway,
            SettingsKey.smartSuppress,
        ]
        var saved: [String: Any?] = [:]
        for key in watchedKeys {
            saved[key] = UserDefaults.standard.object(forKey: key)
        }
        var played: [String] = []
        SoundManager.shared.playSink = { name in played.append(name) }
        defer {
            SoundManager.shared.playSink = nil
            for key in watchedKeys {
                if let value = saved[key] ?? nil {
                    UserDefaults.standard.set(value, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }

        UserDefaults.standard.set(true, forKey: SettingsKey.soundEnabled)
        UserDefaults.standard.set(true, forKey: SettingsKey.soundTaskComplete)
        UserDefaults.standard.set(true, forKey: SettingsKey.soundTaskError)
        UserDefaults.standard.set(true, forKey: SettingsKey.soundSessionStart)
        UserDefaults.standard.set(false, forKey: SettingsKey.quietHoursEnabled)
        UserDefaults.standard.set(false, forKey: SettingsKey.autoMuteWhenAway)
        UserDefaults.standard.set(false, forKey: SettingsKey.smartSuppress)
        SettingsManager.shared.childAgentNotificationTiming = .rootOnly

        let appState = AppState()
        let parentId = "ag-coord-sync-sound"
        let workerId = "ag-worker-sync-sound"

        // Pre-populate zero links so the worker is brand-new to the in-memory cache;
        // the loader returns the parent link when consulted synchronously on Stop/SessionStart.
        XCTAssertTrue(appState.antigravitySubagentLinks.isEmpty)
        appState.antigravityLinkLoader = {
            [
                workerId: AntigravitySubagentLink(
                    childSessionId: workerId,
                    parentSessionId: parentId,
                    roleName: "worker",
                    swarmTitle: "Sync Sound Test"
                ),
            ]
        }

        // Brand-new worker fires SessionStart, then Stop without any prior async scan finishing.
        appState.handleEvent(try makeEvent([
            "hook_event_name": "SessionStart",
            "session_id": workerId,
            "_source": "google-antigravity",
            "cwd": "/tmp/flowisland",
        ]))
        appState.handleEvent(try makeEvent([
            "hook_event_name": "Stop",
            "session_id": workerId,
            "_source": "google-antigravity",
            "cwd": "/tmp/flowisland",
        ]))

        XCTAssertEqual(played, [], "Brand-new Swarm worker must resolve its parent synchronously and stay silent under .rootOnly")
        XCTAssertNil(appState.sessions[workerId], "Worker card must be folded into parent")
        XCTAssertNotNil(appState.sessions[parentId]?.subagents[workerId])

        // Meanwhile a standalone root Antigravity session (not a child) still chimes on Stop.
        let rootId = "ag-standalone-root"
        appState.handleEvent(try makeEvent([
            "hook_event_name": "UserPromptSubmit",
            "session_id": rootId,
            "_source": "google-antigravity",
            "cwd": "/tmp/flowisland",
            "prompt": "Finish task",
        ]))
        appState.handleEvent(try makeEvent([
            "hook_event_name": "Stop",
            "session_id": rootId,
            "_source": "google-antigravity",
            "cwd": "/tmp/flowisland",
        ]))
        XCTAssertEqual(played, ["8bit_complete"], "Root Antigravity session must still chime on Stop")
    }

    // MARK: - Effective Display Status With Active Subagents

    func testEffectiveDisplayStatusReflectsActiveSubagentsInCardStatusCountAndPrimaryDisplay() {
        let appState = AppState()
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        var newerIdle = SessionSnapshot(startTime: base.addingTimeInterval(120))
        newerIdle.source = "claude"
        newerIdle.status = .idle

        var parentWithRunningSub = SessionSnapshot(startTime: base)
        parentWithRunningSub.source = "google-antigravity"
        parentWithRunningSub.status = .idle
        var sub = SubagentState(agentId: "worker-1", agentType: "model-pill")
        sub.status = .running
        parentWithRunningSub.subagents["worker-1"] = sub

        XCTAssertTrue(parentWithRunningSub.hasActiveSubagents)
        XCTAssertEqual(parentWithRunningSub.effectiveDisplayStatus, .running)
        XCTAssertEqual(SessionCardStatus(parentWithRunningSub), .working)

        appState.sessions = [
            "s-newer-idle": newerIdle,
            "s-parent-delegating": parentWithRunningSub,
        ]
        appState.refreshDerivedState()

        XCTAssertEqual(appState.hubActiveSessionCount, 1)
        XCTAssertEqual(appState.primaryDisplaySessionId, "s-parent-delegating")
        XCTAssertEqual(
            appState.hubVisibleSessionIds(
                filter: .active,
                searchQuery: "",
                showArchived: false,
                baseOrder: appState.sessionListOrder()
            ),
            ["s-parent-delegating"]
        )

        // When the subagent waits for approval, effectiveDisplayStatus elevates to waitingApproval.
        appState.sessions["s-parent-delegating"]?.subagents["worker-1"]?.status = .waitingApproval
        XCTAssertEqual(appState.sessions["s-parent-delegating"]?.effectiveDisplayStatus, .waitingApproval)
        XCTAssertEqual(SessionCardStatus(appState.sessions["s-parent-delegating"]!), .needsYou)

        // Once all subagents settle idle, parent returns to idle and #1 newest takes over.
        appState.sessions["s-parent-delegating"]?.subagents["worker-1"]?.status = .idle
        XCTAssertEqual(appState.sessions["s-parent-delegating"]?.hasActiveSubagents, false)
        XCTAssertEqual(appState.sessions["s-parent-delegating"]?.effectiveDisplayStatus, .idle)
        XCTAssertEqual(appState.hubActiveSessionCount, 0)
        XCTAssertEqual(appState.primaryDisplaySessionId, "s-newer-idle")
    }
}
