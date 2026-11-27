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
}
