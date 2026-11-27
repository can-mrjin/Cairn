import Foundation
import Darwin
import CodeIslandCore

extension AppState {
    /// Recover metadata for a locally discovered Claude process whose hooks have
    /// not supplied terminal information yet. Use its own environment, never the
    /// CodeIsland process environment or a different process with the same CWD.
    @discardableResult
    func backfillClaudeTerminalMetadata(
        sessionId: String,
        process: ProcessIdentity,
        readEnvironment: (pid_t) -> [String: String]? = AppState.claudeTerminalEnvironment
    ) -> Bool {
        guard var session = sessions[sessionId], session.source == "claude",
              !session.isRemote, !session.isNativeAppMode, session.hostHarness == nil,
              session.claudeDesktopSessionId == nil,
              session.cliPid == process.pid, session.cliStartTime == process.startTime,
              session.termApp == nil || session.termBundleId == nil
                || session.tmuxPane == nil || session.tmuxEnv == nil,
              // Fixed at exec: a second read can't find what the first didn't.
              claudeTerminalProbes[sessionId] != process,
              ProcessTable.isLiveProcess(process) else { return false }
        let environment = readEnvironment(process.pid)
        claudeTerminalProbes[sessionId] = process
        guard let env = environment,
              let tmux = env["TMUX"], !tmux.isEmpty,
              let pane = env["TMUX_PANE"], !pane.isEmpty,
              ProcessTable.isLiveProcess(process) else { return false }
        var changed = false
        func fill(_ field: WritableKeyPath<SessionSnapshot, String?>, _ value: String?) {
            guard session[keyPath: field] == nil, let value, !value.isEmpty else { return }
            session[keyPath: field] = value
            changed = true
        }
        fill(\.termApp, env["TERM_PROGRAM"])
        fill(\.termBundleId, env["__CFBundleIdentifier"])
        // Do not combine a pane from one tmux server with a socket from another.
        if (session.tmuxEnv == nil && session.tmuxPane == nil)
            || session.tmuxEnv == tmux || session.tmuxPane == pane {
            fill(\.tmuxEnv, tmux)
            fill(\.tmuxPane, pane)
        }
        if changed { sessions[sessionId] = session }
        return changed
    }

    nonisolated static func claudeTerminalEnvironment(for pid: pid_t) -> [String: String]? {
        // A detached service may retain an old terminal environment. Only
        // recover from a process that still has a controlling terminal.
        var info = proc_bsdinfo()
        let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize) == infoSize,
              info.e_tdev != UInt32.max else { return nil }
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return ProcArgsParser.completeEnvironment(Array(buffer.prefix(size)),
            keys: ["TERM_PROGRAM", "__CFBundleIdentifier", "TMUX", "TMUX_PANE"])
    }

    /// Backfill `claudeDesktopSessionId` and `forkedFromHostSessionId` for local
    /// Claude sessions from Claude Desktop's `claude-code-sessions` metadata off
    /// the main actor so forked `(fork)` and `btw:` conversations nest cleanly
    /// under their parent conversation in the session list.
    func refreshClaudeDesktopForkMetadataIfNeeded(force: Bool = false) {
        guard !RuntimeEnvironment.isRunningTests, !RuntimeEnvironment.isIsolated else { return }
        guard !claudeDesktopForkScanInFlight else { return }

        let candidates: [String] = sessions.compactMap { id, session in
            guard !session.isRemote,
                  SessionSnapshot.normalizedSupportedSource(session.source) == "claude" else { return nil }
            if force { return id }
            if session.claudeDesktopSessionId == nil || !claudeDesktopForkProbedSessionIds.contains(id) {
                return id
            }
            return nil
        }
        guard !candidates.isEmpty else { return }

        let now = Date()
        guard force || now.timeIntervalSince(lastClaudeDesktopForkScanAt) >= 3.0 else { return }
        lastClaudeDesktopForkScanAt = now
        claudeDesktopForkScanInFlight = true

        Task.detached(priority: .utility) { [weak self] in
            let index = ClaudeDesktopCodeSession.recentSessionMetadataIndex()
            await self?.applyClaudeDesktopForkMetadataIndex(index, probedIds: candidates)
        }
    }

    private func applyClaudeDesktopForkMetadataIndex(
        _ index: [String: ClaudeDesktopCodeSession.HostSessionMetadata],
        probedIds: [String]
    ) {
        claudeDesktopForkScanInFlight = false
        var changed = false
        for id in probedIds {
            guard var session = sessions[id], !session.isRemote else { continue }
            claudeDesktopForkProbedSessionIds.insert(id)

            var lookupKeys: [String] = []
            if let hostId = session.claudeDesktopSessionId, !hostId.isEmpty {
                lookupKeys.append(hostId)
            }
            if let providerId = session.providerSessionId, !providerId.isEmpty {
                lookupKeys.append(providerId)
            }
            lookupKeys.append(id)
            if let transcriptPath = session.transcriptPath, !transcriptPath.isEmpty {
                let stem = URL(fileURLWithPath: transcriptPath).deletingPathExtension().lastPathComponent
                if !stem.isEmpty {
                    lookupKeys.append(stem)
                }
            }

            guard let meta = lookupKeys.lazy.compactMap({ index[$0] }).first else { continue }
            var sessionChanged = false
            if session.claudeDesktopSessionId != meta.hostSessionId {
                session.claudeDesktopSessionId = meta.hostSessionId
                sessionChanged = true
            }
            if let parentHost = meta.forkedFromHostSessionId,
               session.forkedFromHostSessionId != parentHost {
                session.forkedFromHostSessionId = parentHost
                sessionChanged = true
            }
            if sessionChanged {
                sessions[id] = session
                changed = true
            }
        }
        if changed {
            scheduleSave()
        }
    }
}
