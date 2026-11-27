import AppKit
import Foundation
import CodeIslandCore

// MARK: - Session Hub, Unread Indicator, Silence Filter, Bypass & Antigravity Subagent Tree

extension AppState {
    // MARK: - Hub State Persistence

    func loadHubStateIfNeeded() {
        let raw = SettingsManager.shared.sessionHubStateJSON
        if !raw.isEmpty {
            hubState = SessionHubEngine.decode(raw)
        }
        _ = pruneStaleHubArchivesIfNeeded()
    }

    @discardableResult
    func pruneStaleHubArchivesIfNeeded(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard SessionHubEngine.pruneStaleArchivesIfNeeded(
            now: now,
            state: &hubState,
            calendar: calendar
        ) else {
            return false
        }
        persistHubState()
        return true
    }

    func persistHubState() {
        SettingsManager.shared.sessionHubStateJSON = SessionHubEngine.encode(hubState)
    }

    // MARK: - Unread Indicator

    func isSessionUnread(_ sessionId: String) -> Bool {
        SessionHubEngine.isUnread(sessionId: sessionId, state: hubState)
    }

    var unreadSessionCount: Int {
        let visibleIds = sessions.keys.filter { !SessionHubEngine.isArchived($0, state: hubState) }
        return SessionHubEngine.unreadCount(among: visibleIds, state: hubState)
    }

    var pinnedSessionCount: Int {
        sessions.keys.filter {
            SessionHubEngine.isPinned(sessionId: $0, state: hubState)
                && !SessionHubEngine.isArchived($0, state: hubState)
        }.count
    }

    var hubActiveSessionCount: Int {
        sessions.filter { id, snap in
            !SessionHubEngine.isArchived(id, state: hubState) && snap.effectiveDisplayStatus != .idle
        }.count
    }

    var archivedSessionCount: Int {
        sessions.keys.filter { SessionHubEngine.isArchived($0, state: hubState) }.count
    }

    func markSessionRead(_ sessionId: String) {
        guard isSessionUnread(sessionId) else { return }
        SessionHubEngine.markRead(sessionId: sessionId, state: &hubState)
        persistHubState()
        refreshDerivedState()
    }

    func toggleSessionRead(_ sessionId: String) {
        if isSessionUnread(sessionId) {
            SessionHubEngine.markRead(sessionId: sessionId, state: &hubState)
        } else {
            SessionHubEngine.markUnread(sessionId: sessionId, now: Date(), state: &hubState)
        }
        persistHubState()
        refreshDerivedState()
    }

    func markAllSessionsRead() {
        guard !hubState.unreadSince.isEmpty else { return }
        SessionHubEngine.markAllRead(state: &hubState)
        glanceCompletionActive = false
        persistHubState()
        refreshDerivedState()
    }

    func recordHubStatusTransition(
        sessionId: String,
        from previous: AgentStatus?,
        to current: AgentStatus,
        hadError: Bool = false,
        isChild: Bool = false
    ) {
        guard !isChild else { return }
        let isFocused = surface.isExpanded && activeSessionId == sessionId && surface == .sessionList
        let before = hubState.unreadSince[sessionId]
        SessionHubEngine.recordTransition(
            sessionId: sessionId,
            from: previous,
            to: current,
            hadError: hadError,
            isFocused: isFocused,
            now: Date(),
            state: &hubState
        )
        if hubState.unreadSince[sessionId] != before {
            persistHubState()
        }
    }

    // MARK: - Pin & Archive

    func isSessionPinned(_ sessionId: String) -> Bool {
        SessionHubEngine.isPinned(sessionId: sessionId, state: hubState)
    }

    func toggleSessionPin(_ sessionId: String) {
        SessionHubEngine.togglePin(sessionId: sessionId, state: &hubState)
        persistHubState()
        refreshDerivedState()
    }

    func isSessionArchived(_ sessionId: String) -> Bool {
        SessionHubEngine.isArchived(sessionId, state: hubState)
    }

    func toggleSessionArchive(_ sessionId: String) {
        if isSessionArchived(sessionId) {
            SessionHubEngine.unarchive(sessionId: sessionId, state: &hubState)
        } else {
            SessionHubEngine.archive(sessionId: sessionId, now: Date(), state: &hubState)
        }
        persistHubState()
        refreshDerivedState()
    }

    // MARK: - Today's Hub Filtering & Ordering

    /// Stable creation-time ordering shared by the expanded Hub list and the
    /// collapsed bar: pinned sessions first (preserving pin order), then newest
    /// main conversation creation time (`startTime` descending), then
    /// `sessionId` ascending.
    func stableSortedSessionIds(excludingArchived: Bool) -> [String] {
        var pinRank: [String: Int] = [:]
        pinRank.reserveCapacity(hubState.pinnedIds.count)
        for (index, id) in hubState.pinnedIds.enumerated() where pinRank[id] == nil {
            pinRank[id] = index
        }
        let candidates = excludingArchived
            ? sessions.keys.filter { !SessionHubEngine.isArchived($0, state: hubState) }
            : Array(sessions.keys)
        return candidates.sorted { lhs, rhs in
            let lhsPin = pinRank[lhs] ?? Int.max
            let rhsPin = pinRank[rhs] ?? Int.max
            if lhsPin != rhsPin {
                return lhsPin < rhsPin
            }
            let lhsStart = sessions[lhs]?.startTime ?? .distantPast
            let rhsStart = sessions[rhs]?.startTime ?? .distantPast
            if lhsStart != rhsStart {
                return lhsStart > rhsStart
            }
            return lhs < rhs
        }
    }

    /// The primary conversation bound to the collapsed notch bar's mascot,
    /// live activity status, and tooltip. Scans non-archived sessions in the
    /// exact same stable order as the expanded list (pinned -> newest
    /// `startTime` -> `sessionId` ascending):
    /// 1. Prefers the topmost active (`status != .idle`) non-archived session so
    ///    live work is shown instead of sleeping `zzz` while staying locked to
    ///    stable order without rotation/bouncing.
    /// 2. Falls back to the #1 topmost non-archived session when all are idle
    ///    (or #1 overall if every session is archived).
    var primaryDisplaySessionId: String? {
        let nonArchived = stableSortedSessionIds(excludingArchived: true)
        if let topActive = nonArchived.first(where: { (sessions[$0]?.effectiveDisplayStatus ?? .idle) != .idle }) {
            return topActive
        }
        return nonArchived.first ?? stableSortedSessionIds(excludingArchived: false).first
    }

    func hubVisibleSessionIds(
        filter: SessionHubFilter,
        searchQuery: String,
        showArchived: Bool,
        baseOrder: [String]
    ) -> [String] {
        let entries: [SessionHubEntry] = baseOrder.compactMap { id -> SessionHubEntry? in
            guard let s = sessions[id] else { return nil }
            let projectName = s.cwd.map { ($0 as NSString).lastPathComponent } ?? ""
            let showProjectName = UserDefaults.standard.object(forKey: SettingsKey.showProjectName) as? Bool
                ?? SettingsDefaults.showProjectName
            let title = s.headline(showProjectName: showProjectName).text
            return SessionHubEntry(
                sessionId: id,
                source: s.source,
                title: title,
                projectName: projectName,
                prompt: s.lastUserPrompt ?? s.lastAssistantMessage ?? "",
                gitBranch: s.gitBranch ?? "",
                status: s.effectiveDisplayStatus,
                createdAt: s.startTime,
                lastUpdated: s.lastActivity
            )
        }
        return SessionHubEngine.visibleEntries(
            entries,
            filter: filter,
            searchQuery: searchQuery,
            includeArchived: showArchived,
            state: hubState
        ).map(\.sessionId)
    }

    func shouldRetainIdleSessionInHub(_ sessionId: String, session: SessionSnapshot, now: Date = Date()) -> Bool {
        SessionHubEngine.shouldRetainSession(
            sessionId: sessionId,
            status: session.status,
            lastUpdated: session.lastActivity,
            keepTodaySessions: SettingsManager.shared.keepTodaySessions,
            now: now,
            state: hubState
        )
    }

    // MARK: - Silence Noise Rules

    var silenceRuleConfig: SilenceRuleConfig {
        SessionSilenceFilter.decode(SettingsManager.shared.silenceRulesJSON)
    }

    func shouldSilenceSession(
        source: String,
        cwd: String?,
        firstPrompt: String?,
        launcherBundleId: String? = nil
    ) -> Bool {
        SessionSilenceFilter.silenceReason(
            source: source,
            cwd: cwd,
            firstPrompt: firstPrompt,
            launcherBundleId: launcherBundleId,
            config: silenceRuleConfig
        ) != nil
    }

    func shouldSilenceHookEvent(_ event: HookEvent, existingSession: SessionSnapshot? = nil) -> Bool {
        let rawSource = event.rawJSON["_source"] as? String
        let source = SessionSnapshot.normalizedSupportedSource(rawSource)
            ?? existingSession?.source
            ?? rawSource
            ?? ""
        let cwd = (event.rawJSON["cwd"] as? String) ?? existingSession?.cwd
        let prompt = Self.extractHookPromptText(from: event) ?? existingSession?.lastUserPrompt
        let bundleId = (event.rawJSON["_term_bundle"] as? String) ?? existingSession?.termBundleId
        return shouldSilenceSession(
            source: source,
            cwd: cwd,
            firstPrompt: prompt,
            launcherBundleId: bundleId
        )
    }

    private static func extractHookPromptText(from event: HookEvent) -> String? {
        let keys = ["prompt", "user_prompt", "userPrompt", "user_message", "message"]
        for key in keys {
            if let value = event.rawJSON[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        let containers = ["input", "data", "payload", "params", "extra"]
        for containerKey in containers {
            guard let dict = event.rawJSON[containerKey] as? [String: Any] else { continue }
            for key in keys {
                if let value = dict[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }
        return nil
    }

    func silenceDirectory(forSession sessionId: String) {
        guard let cwd = sessions[sessionId]?.cwd, !cwd.isEmpty else { return }
        var config = silenceRuleConfig
        if SessionSilenceFilter.addBlockedDirectory(cwd, to: &config) {
            SettingsManager.shared.silenceRulesJSON = SessionSilenceFilter.encode(config)
        }
        let matchingIds = sessions.compactMap { id, snap -> String? in
            guard let snapCwd = snap.cwd else { return nil }
            return SessionSilenceFilter.silenceReason(
                source: snap.source,
                cwd: snapCwd,
                firstPrompt: snap.lastUserPrompt,
                config: config
            ) != nil ? id : nil
        }
        for id in matchingIds {
            removeSession(id)
        }
        refreshDerivedState()
    }

    func silencePromptPrefix(forSession sessionId: String) {
        guard let rawPrompt = sessions[sessionId]?.lastUserPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPrompt.isEmpty else { return }
        let prefix = String(rawPrompt.prefix(48))
        var config = silenceRuleConfig
        if SessionSilenceFilter.addBlockedPromptPrefix(prefix, to: &config) {
            SettingsManager.shared.silenceRulesJSON = SessionSilenceFilter.encode(config)
        }
        removeSession(sessionId)
        refreshDerivedState()
    }

    // MARK: - Batch Approval, Bypass & Compaction State

    func bypassMode(forSession sessionId: String) -> SessionBypassMode {
        bypassStore.mode(for: sessionId)
    }

    func toggleSessionBypass(_ sessionId: String) {
        let next: SessionBypassMode = bypassStore.mode(for: sessionId) == .session ? .off : .session
        bypassStore.setMode(next, for: sessionId)
        if next != .off {
            drainPendingPermissionsForBypassedSession(sessionId)
        }
        refreshDerivedState()
    }

    func toggleTurnBypass(_ sessionId: String) {
        let next: SessionBypassMode = bypassStore.mode(for: sessionId) == .off ? .thisTurn : .off
        bypassStore.setMode(next, for: sessionId)
        if next != .off {
            drainPendingPermissionsForBypassedSession(sessionId)
        }
        refreshDerivedState()
    }

    private func drainPendingPermissionsForBypassedSession(_ sessionId: String) {
        while permissionQueue.contains(where: { ($0.event.sessionId ?? "default") == sessionId }) {
            approvePermission(always: false, expectedSessionId: sessionId)
        }
    }

    func approveAllPendingPermissions() {
        while let first = permissionQueue.first {
            approvePermission(always: false, expectedSessionId: first.event.sessionId ?? "default")
        }
    }

    func denyAllPendingPermissions() {
        while let first = permissionQueue.first {
            denyPermission(expectedSessionId: first.event.sessionId ?? "default")
        }
    }

    func compactionElapsedText(forSession sessionId: String, now: Date = Date()) -> String? {
        bypassStore.compaction(for: sessionId)?.formattedElapsed(at: now)
    }

    func updateCompactionState(forSession sessionId: String, eventName: String) {
        if SessionBypassStore.isCompactionStartEvent(eventName) {
            bypassStore.startCompaction(sessionId: sessionId, at: Date())
        } else if SessionBypassStore.isCompactionEndEvent(eventName) {
            bypassStore.finishCompaction(sessionId: sessionId)
        }
    }

    // MARK: - Antigravity Subagent / Swarm Tree Folding & Child Notification Gating

    nonisolated static func isAntigravitySource(_ source: String?) -> Bool {
        guard let normalized = SessionSnapshot.normalizedSupportedSource(source)
            ?? source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return normalized == "google-antigravity" || normalized == "antigravity" || normalized == "gemini"
    }

    nonisolated static func synthesizedAntigravityParentStatus(from subagents: [String: SubagentState]) -> AgentStatus {
        if subagents.values.contains(where: { $0.status == .running }) {
            return .running
        }
        if subagents.values.contains(where: { $0.status == .processing }) {
            return .processing
        }
        return .idle
    }

    nonisolated static let antigravityLinkScanCooldown: TimeInterval = 5.0

    func refreshAntigravitySubagentLinks(
        force: Bool = false,
        triggerSessionId: String? = nil,
        now: Date = Date()
    ) {
        if let triggerSessionId {
            guard Self.isAntigravitySource(sessions[triggerSessionId]?.source) else { return }
        }
        let hasAntigravity = sessions.values.contains { Self.isAntigravitySource($0.source) }
        guard hasAntigravity else { return }
        guard !antigravityLinkScanInFlight else { return }

        // Enforce cooldown even on misses: only a brand-new Antigravity trigger
        // session that has never been scanned before may bypass the 5s window once;
        // repeated misses (e.g., coordinators or standalone Antigravity chats) obey
        // the full cooldown so disk scans never fire on every hook event.
        let isFirstAttemptForTrigger: Bool = {
            guard force, let triggerSessionId else { return false }
            return antigravityLinkAttemptedAt[triggerSessionId] == nil
        }()
        if !isFirstAttemptForTrigger {
            guard now.timeIntervalSince(lastAntigravityLinkScan) >= Self.antigravityLinkScanCooldown else {
                return
            }
        }
        if let triggerSessionId {
            antigravityLinkAttemptedAt[triggerSessionId] = now
        }
        lastAntigravityLinkScan = now
        antigravityLinkScanInFlight = true
        let loader = antigravityLinkLoader
        let directLoader = antigravityDirectSubagentLinkLoader
        let candidateIds: [String] = sessions.compactMap { id, snap in
            guard Self.isAntigravitySource(snap.source) else { return nil }
            return id
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var links = loader()
            for id in candidateIds where links[id] == nil {
                if let direct = directLoader(id) {
                    links[id] = direct
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.antigravityLinkScanInFlight = false
                var merged = self.antigravitySubagentLinks
                for (childId, link) in links {
                    merged[childId] = link
                }
                if merged != self.antigravitySubagentLinks {
                    self.antigravitySubagentLinks = merged
                    _ = self.applyAntigravitySubagentFolding(skipRefresh: true)
                    self.refreshDerivedState()
                }
            }
        }
    }

    /// Folds any Antigravity Swarm worker session into its coordinator parent's
    /// `subagents` dictionary so workers render as a crisp tree branch inside the
    /// parent card instead of flat top-level cards. Returns true if `sessionId`
    /// is a child session (folded or linked).
    ///
    /// Pass `syncForAttention: true` on sound-producing lifecycle events so a
    /// brand-new Swarm worker resolves its parent link synchronously (<1ms)
    /// before `decideAttention` runs, preventing spurious child chimes under
    /// `.rootOnly` / `.allFinished`.
    @discardableResult
    func applyAntigravitySubagentFolding(
        forTriggerSessionId triggerId: String? = nil,
        skipRefresh: Bool = false,
        syncForAttention: Bool = false
    ) -> Bool {
        if !skipRefresh {
            if let triggerId {
                if Self.isAntigravitySource(sessions[triggerId]?.source) {
                    let isUnknownLink = antigravitySubagentLinks[triggerId] == nil
                        && (sessions[triggerId]?.providerSessionId.flatMap { antigravitySubagentLinks[$0] } == nil)
                    let isKnownParent = !(sessions[triggerId]?.subagents.isEmpty ?? true)
                        || antigravitySubagentLinks.values.contains(where: { $0.parentSessionId == triggerId })
                    if syncForAttention && isUnknownLink && !isKnownParent {
                        let now = Date()
                        let shouldSyncScan = antigravityLinkAttemptedAt[triggerId] == nil
                            || antigravityLinkScanInFlight
                            || now.timeIntervalSince(lastAntigravityLinkScan) >= Self.antigravityLinkScanCooldown
                        if shouldSyncScan {
                            var links = antigravityLinkLoader()
                            if links[triggerId] == nil,
                               let direct = antigravityDirectSubagentLinkLoader(triggerId) {
                                links[triggerId] = direct
                            }
                            lastAntigravityLinkScan = now
                            antigravityLinkAttemptedAt[triggerId] = now
                            for (childId, link) in links where antigravitySubagentLinks[childId] != link {
                                antigravitySubagentLinks[childId] = link
                            }
                        }
                    } else {
                        refreshAntigravitySubagentLinks(force: isUnknownLink && !isKnownParent, triggerSessionId: triggerId)
                    }
                }
            } else {
                refreshAntigravitySubagentLinks(force: false)
            }
        }
        guard !antigravitySubagentLinks.isEmpty else { return false }

        var triggerIsChild = false
        for (childId, child) in Array(sessions) {
            let link = antigravitySubagentLinks[childId]
                ?? child.providerSessionId.flatMap { antigravitySubagentLinks[$0] }
            guard let link else { continue }
            if childId == triggerId {
                triggerIsChild = true
            }
            // Locate parent card by exact conversation id or providerSessionId
            var parentKey: String? = {
                if sessions[link.parentSessionId] != nil { return link.parentSessionId }
                return sessions.first(where: { $0.value.providerSessionId == link.parentSessionId })?.key
            }()
            if parentKey == nil {
                // Coordinator hasn't fired a hook yet (e.g. FlowIsland restarted mid-swarm):
                // synthesize a parent card at `link.parentSessionId` so workers still fold into a tree.
                guard !link.parentSessionId.isEmpty, link.parentSessionId != childId else {
                    sessions[childId]?.parentSessionId = link.parentSessionId
                    continue
                }
                var parent = SessionSnapshot(startTime: child.startTime)
                parent.source = child.source
                parent.cwd = child.cwd
                parent.gitBranch = child.gitBranch
                parent.gitIsWorktree = child.gitIsWorktree
                parent.model = child.model
                parent.reasoningEffort = child.reasoningEffort
                parent.termApp = child.termApp
                parent.termBundleId = child.termBundleId
                parent.lastActivity = child.lastActivity
                if let swarmTitle = link.swarmTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !swarmTitle.isEmpty {
                    parent.lastUserPrompt = swarmTitle
                }
                parent.status = (child.status == .running || child.status == .processing) ? child.status : .idle
                sessions[link.parentSessionId] = parent
                synthesizedAntigravityParentIds.insert(link.parentSessionId)
                parentKey = link.parentSessionId
            }
            guard let parentKey, parentKey != childId, var parent = sessions[parentKey] else {
                sessions[childId]?.parentSessionId = link.parentSessionId
                continue
            }

            if synthesizedAntigravityParentIds.contains(parentKey) {
                if parent.cwd == nil { parent.cwd = child.cwd }
                if parent.gitBranch == nil {
                    parent.gitBranch = child.gitBranch
                    parent.gitIsWorktree = child.gitIsWorktree
                }
                if parent.model == nil { parent.model = child.model }
                if parent.reasoningEffort == nil { parent.reasoningEffort = child.reasoningEffort }
                if parent.termApp == nil { parent.termApp = child.termApp }
                if parent.termBundleId == nil { parent.termBundleId = child.termBundleId }
                if (parent.lastUserPrompt?.isEmpty ?? true),
                   let swarmTitle = link.swarmTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !swarmTitle.isEmpty {
                    parent.lastUserPrompt = swarmTitle
                }
                parent.startTime = min(parent.startTime, child.startTime)
            }

            var sub = parent.subagents[childId]
                ?? SubagentState(agentId: childId, agentType: link.roleName)
            sub.status = child.status
            sub.currentTool = child.currentTool
            sub.toolDescription = child.toolDescription ?? child.lastAssistantMessage
            sub.startTime = min(sub.startTime, child.startTime)
            sub.lastActivity = max(sub.lastActivity, child.lastActivity)
            if let model = child.model { sub.model = model }
            if let effort = child.reasoningEffort { sub.reasoningEffort = effort }
            parent.subagents[childId] = sub
            parent.lastActivity = max(parent.lastActivity, child.lastActivity)
            if synthesizedAntigravityParentIds.contains(parentKey) {
                parent.status = Self.synthesizedAntigravityParentStatus(from: parent.subagents)
            }
            sessions[parentKey] = parent

            // Guard: never fold & remove a worker that still has a pending permission or
            // question waiting on user input (matching Codex/Cursor folding safety).
            let hasPendingRequest = permissionQueue.contains(where: { ($0.event.sessionId ?? "default") == childId })
                || questionQueue.contains(where: { ($0.event.sessionId ?? "default") == childId })
            if hasPendingRequest {
                sessions[childId]?.parentSessionId = link.parentSessionId
                continue
            }

            // Remove duplicate top-level worker card so it renders ONLY in the parent's tree
            if sessions[childId] != nil {
                removeSession(childId)
            }
        }
        return triggerIsChild
    }

    /// Resolves the live parent card key in `sessions` for a child session across
    /// declared/Codex/Cursor `parentSessionId`, Antigravity swarm links, and
    /// `providerSessionId`-keyed parents.
    func resolvedParentSessionKey(forChildSessionId sessionId: String, knownParentId: String? = nil) -> String? {
        let childProviderId = sessions[sessionId]?.providerSessionId
        let rawParentId = knownParentId
            ?? sessions[sessionId]?.parentSessionId
            ?? antigravitySubagentLinks[sessionId]?.parentSessionId
            ?? childProviderId.flatMap { antigravitySubagentLinks[$0]?.parentSessionId }
        if let rawParentId {
            if sessions[rawParentId] != nil {
                return rawParentId
            }
            if let matchedKey = sessions.first(where: { $0.value.providerSessionId == rawParentId })?.key {
                return matchedKey
            }
        }
        return sessions.first(where: { $0.value.subagents[sessionId] != nil })?.key
    }

    func remainingRunningSiblingsCount(forChildSessionId sessionId: String, knownParentId: String? = nil) -> Int {
        let childProviderId = sessions[sessionId]?.providerSessionId
        let rawParentId = knownParentId
            ?? sessions[sessionId]?.parentSessionId
            ?? antigravitySubagentLinks[sessionId]?.parentSessionId
            ?? childProviderId.flatMap { antigravitySubagentLinks[$0]?.parentSessionId }
        let parentKey = resolvedParentSessionKey(forChildSessionId: sessionId, knownParentId: rawParentId)

        var parentIdentifiers = Set<String>()
        if let rawParentId { parentIdentifiers.insert(rawParentId) }
        if let parentKey {
            parentIdentifiers.insert(parentKey)
            if let parentProviderId = sessions[parentKey]?.providerSessionId, !parentProviderId.isEmpty {
                parentIdentifiers.insert(parentProviderId)
            }
        }
        guard !parentIdentifiers.isEmpty else { return 0 }

        var selfIds: Set<String> = [sessionId]
        if let childProviderId, !childProviderId.isEmpty {
            selfIds.insert(childProviderId)
        }

        var runningSiblingIds = Set<String>()
        if let parentKey, let parent = sessions[parentKey] {
            for sub in parent.subagents.values where sub.status != .idle && !selfIds.contains(sub.agentId) {
                runningSiblingIds.insert(sub.agentId)
            }
        }
        for (otherId, otherSnap) in sessions {
            guard otherId != sessionId, otherSnap.status != .idle else { continue }
            if let otherProviderId = otherSnap.providerSessionId, selfIds.contains(otherProviderId) {
                continue
            }
            let otherParentId = otherSnap.parentSessionId
                ?? antigravitySubagentLinks[otherId]?.parentSessionId
                ?? otherSnap.providerSessionId.flatMap { antigravitySubagentLinks[$0]?.parentSessionId }
            guard let otherParentId, parentIdentifiers.contains(otherParentId) else { continue }
            // Avoid double-counting a child that appears both in `parent.subagents` and as a card
            // (e.g., when kept un-folded due to a pending approval/question).
            if let otherProviderId = otherSnap.providerSessionId, runningSiblingIds.contains(otherProviderId) {
                continue
            }
            runningSiblingIds.insert(otherId)
        }
        return runningSiblingIds.count
    }

    func shouldNotifyCompletionForSession(_ sessionId: String, isChild: Bool, knownParentId: String? = nil) -> Bool {
        let timing = SettingsManager.shared.childAgentNotificationTiming
        let remainingRunning = isChild
            ? remainingRunningSiblingsCount(forChildSessionId: sessionId, knownParentId: knownParentId)
            : 0
        return ChildAgentNotificationPolicy.shouldNotifyCompletion(
            isChildSession: isChild,
            remainingRunningSiblings: remainingRunning,
            timing: timing
        )
    }
}

private extension SessionHubEngine {
    static func isArchived(_ sessionId: String, state: SessionHubState) -> Bool {
        state.archivedIds.contains(sessionId)
    }
}
