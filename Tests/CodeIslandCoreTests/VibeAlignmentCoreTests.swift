import XCTest
@testable import CodeIslandCore

final class VibeAlignmentCoreTests: XCTestCase {

    // MARK: - Built-in Silence Presets

    func testCodexChroniclePresetMatchesAndAvoidsFalsePositives() {
        let config = SilenceRuleConfig()

        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "/Users/dev/project",
                firstPrompt: "Codex Chronicle: summarize recent workspace activity",
                config: config
            ),
            .preset(.codexChronicle)
        )

        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "/Users/dev/project",
                firstPrompt: "Create a chronicle memory summary for today's sessions",
                config: config
            ),
            .preset(.codexChronicle)
        )

        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "/Users/dev/.codex/chronicle/worker",
                firstPrompt: "Summarize",
                config: config
            ),
            .preset(.codexChronicle)
        )

        // Normal coding session mentioning "chronicle" or "memory" must not false-positive
        XCTAssertNil(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "/Users/dev/projects/chronicle",
                firstPrompt: "Fix the memory leak in ChronicleViewController.swift",
                config: config
            )
        )

        // Non-codex source should not match codexChronicle
        XCTAssertNil(
            SessionSilenceFilter.silenceReason(
                source: "claude",
                cwd: "/Users/dev/project",
                firstPrompt: "Codex Chronicle memory summary",
                config: config
            )
        )
    }

    func testCodexAppGitHelperPresetMatchesAndAvoidsFalsePositives() {
        let config = SilenceRuleConfig()

        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "/Users/dev/repo",
                firstPrompt: "Generate a concise commit message for the staged diff.",
                config: config
            ),
            .preset(.codexAppGitHelper)
        )

        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "/Users/dev/repo",
                firstPrompt: "Help decide whether to commit or push these workspace edits.",
                config: config
            ),
            .preset(.codexAppGitHelper)
        )

        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "/Users/dev/repo",
                firstPrompt: "Suggest a git commit message based on the diff",
                config: config
            ),
            .preset(.codexAppGitHelper)
        )

        // Normal git-related coding question must not false-positive
        XCTAssertNil(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "/Users/dev/repo",
                firstPrompt: "Explain how git commit message hooks validate trailers in CI.",
                config: config
            )
        )
        XCTAssertNil(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "/Users/dev/repo",
                firstPrompt: "Review this script and make sure it does not commit or push",
                config: config
            )
        )
    }

    func testCodexAppSuggestionsPresetMatchesAndAvoidsFalsePositives() {
        let config = SilenceRuleConfig()

        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "/Users/dev/repo",
                firstPrompt: "Suggest next prompt options for this coding thread.",
                config: config
            ),
            .preset(.codexAppSuggestions)
        )

        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "/Users/dev/repo",
                firstPrompt: "Return 3 follow-up suggestions based on the last assistant reply.",
                config: config
            ),
            .preset(.codexAppSuggestions)
        )

        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "/Users/dev/repo",
                firstPrompt: "Generate recommended prompts for the user.",
                config: config
            ),
            .preset(.codexAppSuggestions)
        )

        // Normal UI prompt discussing suggestions must not false-positive
        XCTAssertNil(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "/Users/dev/repo",
                firstPrompt: "Add autocomplete suggestions to the search bar component.",
                config: config
            )
        )
    }

    func testCodexMemoryWriterPresetMatchesAndAvoidsFalsePositives() {
        let config = SilenceRuleConfig()

        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "/Users/dev/repo",
                firstPrompt: "   \n## Memory Writing Agent\nPersist durable user preferences.",
                config: config
            ),
            .preset(.codexMemoryWriter)
        )

        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "/Users/dev/repo",
                firstPrompt: "memory writing agent: distill session notes",
                config: config
            ),
            .preset(.codexMemoryWriter)
        )

        // Normal coding prompt mentioning memory writing mid-sentence must not false-positive
        XCTAssertNil(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "/Users/dev/repo",
                firstPrompt: "Refactor the Memory Writing Agent unit tests in CoreTests.swift",
                config: config
            )
        )
    }

    func testClaudeMemPresetMatchesAndAvoidsFalsePositives() {
        let config = SilenceRuleConfig()

        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "claude",
                cwd: "/Users/dev/.claude-mem/sessions",
                firstPrompt: "Summarize tool output",
                config: config
            ),
            .preset(.claudeMem)
        )

        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "claude",
                cwd: "/Users/dev/app",
                firstPrompt: "claude-mem observer worker for this session",
                config: config
            ),
            .preset(.claudeMem)
        )

        // Ordinary repo checkout named claude-mem must NOT be silenced
        XCTAssertNil(
            SessionSilenceFilter.silenceReason(
                source: "claude",
                cwd: "/Users/dev/projects/claude-mem",
                firstPrompt: "Fix the unit tests.",
                config: config
            )
        )

        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "claude",
                cwd: "/Users/dev/app",
                firstPrompt: "Observer memory summary for recent file edits",
                config: config
            ),
            .preset(.claudeMem)
        )

        // Normal coding prompt mentioning observer and memory must not false-positive
        XCTAssertNil(
            SessionSilenceFilter.silenceReason(
                source: "claude",
                cwd: "/Users/dev/app",
                firstPrompt: "Fix observer retain cycle causing high memory usage in Store.swift",
                config: config
            )
        )
    }

    func testTogglePresetDisablesAndReenablesMatching() {
        var config = SilenceRuleConfig()
        XCTAssertEqual(config.enabledPresets, SilenceRuleConfig.defaultEnabledPresets)

        SessionSilenceFilter.togglePreset(.codexMemoryWriter, in: &config)
        XCTAssertFalse(config.enabledPresets.contains(.codexMemoryWriter))
        XCTAssertNil(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "/tmp/work",
                firstPrompt: "## Memory Writing Agent\nSave facts",
                config: config
            )
        )

        SessionSilenceFilter.togglePreset(.codexMemoryWriter, in: &config)
        XCTAssertTrue(config.enabledPresets.contains(.codexMemoryWriter))
        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "/tmp/work",
                firstPrompt: "## Memory Writing Agent\nSave facts",
                config: config
            ),
            .preset(.codexMemoryWriter)
        )
    }

    // MARK: - Custom Directory, Prompt Prefix & Bundle ID Rules

    func testCustomDirectoryNormalizationAndPrefixSafety() {
        var config = SilenceRuleConfig(enabledPresets: [])

        // Empty / whitespace rejected
        XCTAssertFalse(SessionSilenceFilter.addBlockedDirectory("   ", to: &config))

        // Trailing slashes normalized & duplicates rejected
        XCTAssertTrue(SessionSilenceFilter.addBlockedDirectory("/tmp/noise///", to: &config))
        XCTAssertFalse(SessionSilenceFilter.addBlockedDirectory("/tmp/noise", to: &config))
        XCTAssertEqual(config.blockedDirectories, ["/tmp/noise"])

        // Exact match & nested subdirectory match
        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "claude",
                cwd: "/tmp/noise/",
                firstPrompt: "hello",
                config: config
            ),
            .directory("/tmp/noise")
        )
        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "claude",
                cwd: "/tmp/noise/nested/dir",
                firstPrompt: "hello",
                config: config
            ),
            .directory("/tmp/noise")
        )

        // Sibling directory with shared string prefix must NOT match
        XCTAssertNil(
            SessionSilenceFilter.silenceReason(
                source: "claude",
                cwd: "/tmp/noise-other",
                firstPrompt: "hello",
                config: config
            )
        )

        // Tilde expansion & deduplication
        let home = (NSHomeDirectory() as NSString).standardizingPath
        XCTAssertTrue(SessionSilenceFilter.addBlockedDirectory("~/bg-jobs/", to: &config))
        XCTAssertFalse(SessionSilenceFilter.addBlockedDirectory("\(home)/bg-jobs", to: &config))

        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "codex",
                cwd: "\(home)/bg-jobs/run1",
                firstPrompt: "hello",
                config: config
            ),
            .directory("\(home)/bg-jobs")
        )

        // Removal normalizes as well
        SessionSilenceFilter.removeBlockedDirectory("/tmp/noise/", from: &config)
        XCTAssertNil(
            SessionSilenceFilter.silenceReason(
                source: "claude",
                cwd: "/tmp/noise/nested",
                firstPrompt: "hello",
                config: config
            )
        )
        SessionSilenceFilter.removeBlockedDirectory("~/bg-jobs", from: &config)
        XCTAssertTrue(config.blockedDirectories.isEmpty)
    }

    func testCustomPromptPrefixAndBundleIdRules() {
        var config = SilenceRuleConfig(
            enabledPresets: [],
            blockedBundleIds: ["com.example.BackgroundHelper"]
        )

        // Empty prefix rejected, deduplication case-insensitive
        XCTAssertFalse(SessionSilenceFilter.addBlockedPromptPrefix("   \n", to: &config))
        XCTAssertTrue(SessionSilenceFilter.addBlockedPromptPrefix("  [AUTO-BOT] ", to: &config))
        XCTAssertFalse(SessionSilenceFilter.addBlockedPromptPrefix("[auto-bot]", to: &config))
        XCTAssertEqual(config.blockedPromptPrefixes, ["[AUTO-BOT]"])

        // Prefix match (case-insensitive & trimmed)
        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "claude",
                cwd: "/Users/dev/app",
                firstPrompt: "  [auto-bot] triage open PRs",
                config: config
            ),
            .promptPrefix("[AUTO-BOT]")
        )

        // Mid-prompt occurrence does NOT match prefix rule
        XCTAssertNil(
            SessionSilenceFilter.silenceReason(
                source: "claude",
                cwd: "/Users/dev/app",
                firstPrompt: "Fix handling of [AUTO-BOT] tags in parser",
                config: config
            )
        )

        // Bundle ID match (case-insensitive)
        XCTAssertEqual(
            SessionSilenceFilter.silenceReason(
                source: "claude",
                cwd: "/Users/dev/app",
                firstPrompt: "normal prompt",
                launcherBundleId: "com.example.backgroundhelper",
                config: config
            ),
            .bundleId("com.example.BackgroundHelper")
        )

        // Remove prompt prefix case-insensitively
        SessionSilenceFilter.removeBlockedPromptPrefix("[auto-bot]", from: &config)
        XCTAssertTrue(config.blockedPromptPrefixes.isEmpty)
    }

    // MARK: - SilenceRuleConfig JSON Serialization

    func testSilenceRuleConfigEncodeDecodeRoundTripAndFallback() {
        let original = SilenceRuleConfig(
            enabledPresets: [.codexChronicle, .claudeMem],
            blockedDirectories: ["/tmp/quiet"],
            blockedPromptPrefixes: ["[silent]"],
            blockedBundleIds: ["com.noise.helper"]
        )

        let encoded = SessionSilenceFilter.encode(original)
        let decoded = SessionSilenceFilter.decode(encoded)
        XCTAssertEqual(decoded, original)

        // Explicitly empty presets round-trip properly
        let emptyPresets = SilenceRuleConfig(enabledPresets: [])
        XCTAssertEqual(
            SessionSilenceFilter.decode(SessionSilenceFilter.encode(emptyPresets)),
            emptyPresets
        )

        // Corrupted or empty JSON falls back to default config
        XCTAssertEqual(SessionSilenceFilter.decode(""), SilenceRuleConfig())
        XCTAssertEqual(SessionSilenceFilter.decode("not valid json"), SilenceRuleConfig())
        XCTAssertEqual(SessionSilenceFilter.decode("{}"), SilenceRuleConfig())
    }

    // MARK: - SessionBypassStore Lifecycle

    func testBypassModeThisTurnVsSessionLifecycle() {
        var store = SessionBypassStore()
        XCTAssertEqual(store.mode(for: "s1"), .off)
        XCTAssertFalse(store.shouldAutoApprove(sessionId: "s1"))

        // .thisTurn auto-approves until turn ends
        store.setMode(.thisTurn, for: "s1")
        XCTAssertEqual(store.mode(for: "s1"), .thisTurn)
        XCTAssertTrue(store.shouldAutoApprove(sessionId: "s1"))

        store.handleTurnEnded(sessionId: "s1")
        XCTAssertEqual(store.mode(for: "s1"), .off)
        XCTAssertFalse(store.shouldAutoApprove(sessionId: "s1"))
        XCTAssertNil(store.modes["s1"])

        // .session persists across turn boundaries
        store.setMode(.session, for: "s2")
        XCTAssertTrue(store.shouldAutoApprove(sessionId: "s2"))
        store.handleTurnEnded(sessionId: "s2")
        XCTAssertEqual(store.mode(for: "s2"), .session)
        XCTAssertTrue(store.shouldAutoApprove(sessionId: "s2"))

        // Setting .off explicitly clears mode
        store.setMode(.off, for: "s2")
        XCTAssertEqual(store.mode(for: "s2"), .off)
        XCTAssertFalse(store.shouldAutoApprove(sessionId: "s2"))
        XCTAssertNil(store.modes["s2"])

        // BatchApprovalAction raw values
        XCTAssertEqual(BatchApprovalAction.allowAll.rawValue, "allowAll")
        XCTAssertEqual(BatchApprovalAction.denyAll.rawValue, "denyAll")
    }

    func testRemoveSessionClearsBothBypassAndCompaction() {
        var store = SessionBypassStore()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        store.setMode(.session, for: "s1")
        store.startCompaction(sessionId: "s1", at: t0)
        XCTAssertEqual(store.mode(for: "s1"), .session)
        XCTAssertNotNil(store.compaction(for: "s1"))

        store.removeSession("s1")
        XCTAssertEqual(store.mode(for: "s1"), .off)
        XCTAssertNil(store.compaction(for: "s1"))
    }

    // MARK: - CompactionProgress & Event Matching

    func testCompactionProgressElapsedAndFormatting() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let progress = CompactionProgress(startedAt: start)

        // Clock skew / past timestamp clamps to 0s
        XCTAssertEqual(progress.elapsedSeconds(at: start.addingTimeInterval(-5)), 0)
        XCTAssertEqual(progress.formattedElapsed(at: start.addingTimeInterval(-5)), "0s")

        XCTAssertEqual(progress.elapsedSeconds(at: start.addingTimeInterval(12.8)), 12)
        XCTAssertEqual(progress.formattedElapsed(at: start.addingTimeInterval(12.8)), "12s")

        XCTAssertEqual(progress.elapsedSeconds(at: start.addingTimeInterval(60)), 60)
        XCTAssertEqual(progress.formattedElapsed(at: start.addingTimeInterval(60)), "1m 00s")

        XCTAssertEqual(progress.elapsedSeconds(at: start.addingTimeInterval(65)), 65)
        XCTAssertEqual(progress.formattedElapsed(at: start.addingTimeInterval(65)), "1m 05s")

        XCTAssertEqual(progress.formattedElapsed(at: start.addingTimeInterval(135)), "2m 15s")
    }

    func testCompactionStartFinishTracking() {
        var store = SessionBypassStore()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = t0.addingTimeInterval(10)

        XCTAssertNil(store.compaction(for: "s1"))

        store.startCompaction(sessionId: "s1", at: t0)
        XCTAssertEqual(store.compaction(for: "s1"), CompactionProgress(startedAt: t0))

        // Duplicate start while active preserves original start timestamp
        store.startCompaction(sessionId: "s1", at: t1)
        XCTAssertEqual(store.compaction(for: "s1"), CompactionProgress(startedAt: t0))

        store.finishCompaction(sessionId: "s1")
        XCTAssertNil(store.compaction(for: "s1"))

        // Starting again after finish records the new timestamp
        store.startCompaction(sessionId: "s1", at: t1)
        XCTAssertEqual(store.compaction(for: "s1"), CompactionProgress(startedAt: t1))
    }

    func testCompactionEventNameMatching() {
        let startEvents = [
            "PreCompact",
            "pre_compact",
            "CompactStart",
            "compact_start",
            "ContextCompacting",
            "context_compacting",
            "CompactionStart",
        ]
        for event in startEvents {
            XCTAssertTrue(
                SessionBypassStore.isCompactionStartEvent(event),
                "Expected start event match for \(event)"
            )
            XCTAssertFalse(
                SessionBypassStore.isCompactionEndEvent(event),
                "Did not expect end event match for \(event)"
            )
        }

        let endEvents = [
            "PostCompact",
            "post_compact",
            "CompactComplete",
            "compact_complete",
            "CompactionEnd",
            "Stop",
            "stop",
            "StopFailure",
            "PreToolUse",
            "pre_tool_use",
            "beforeShellExecution",
            "UserPromptSubmit",
            "SessionStart",
            "session_start",
            "Interrupt",
            "interrupt",
        ]
        for event in endEvents {
            XCTAssertTrue(
                SessionBypassStore.isCompactionEndEvent(event),
                "Expected end event match for \(event)"
            )
            XCTAssertFalse(
                SessionBypassStore.isCompactionStartEvent(event),
                "Did not expect start event match for \(event)"
            )
        }

        // Unrelated / intermediate events match neither
        for neutral in ["", "Notification", "SubagentStart", "SubagentStop", "UnknownEvent"] {
            XCTAssertFalse(SessionBypassStore.isCompactionStartEvent(neutral))
            XCTAssertFalse(SessionBypassStore.isCompactionEndEvent(neutral))
        }
    }
}
