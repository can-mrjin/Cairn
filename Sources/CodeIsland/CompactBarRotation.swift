import Foundation
import CodeIslandCore

/// The compact bar's mascot rotation: while more than one session is active,
/// the collapsed island cycles through them on the user's interval, the most
/// urgent first. AppState hands it the sessions after every change
/// (`update(sessions:)`); views read the session on show through
/// `AppState.rotatingSessionId`.
@MainActor
@Observable
final class CompactBarRotation {
    /// The session the compact bar shows while the rotation runs; nil while
    /// one session or none is active.
    private(set) var rotatingSessionId: String?

    /// Cached sorted active session IDs — refreshed by `update(sessions:)`.
    @ObservationIgnored
    private var activeIds: [String] = []
    /// Torn down from `AppState.deinit`, which may run off the main actor
    /// (e.g. async XCTest ARC). Only mutated on the main actor while alive.
    @ObservationIgnored
    nonisolated(unsafe) private var timer: Timer?

    /// Higher = more urgent, shown first in rotation
    nonisolated static func statusPriority(_ status: AgentStatus) -> Int {
        switch status {
        case .waitingApproval: return 5
        case .waitingQuestion: return 4
        case .running:         return 3
        case .processing:      return 2
        case .idle:            return 0
        }
    }

    /// Re-rank the active sessions and focus the single highest-priority,
    /// most recently active conversation (no jarring timer rotation). Once
    /// that conversation finishes, the compact bar automatically advances to
    /// the next active session in priority order.
    func update(sessions: [String: SessionSnapshot]) -> String? {
        refreshActiveIds(sessions)
        timer?.invalidate()
        timer = nil
        guard let top = activeIds.first else {
            rotatingSessionId = nil
            return nil
        }
        if activeIds.count == 1 {
            rotatingSessionId = nil
            return top
        }
        rotatingSessionId = top
        return nil
    }

    /// Stop the timer; the session on show stays (discovery shutdown).
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Timer teardown for `AppState.deinit`; caller must already be on the
    /// main queue (the run loop the timer was scheduled on).
    nonisolated func tearDownAssumingMain() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshActiveIds(_ sessions: [String: SessionSnapshot]) {
        activeIds = sessions
            .filter { $0.value.status != .idle }
            .sorted { a, b in
                let pa = Self.statusPriority(a.value.status)
                let pb = Self.statusPriority(b.value.status)
                if pa != pb { return pa > pb }
                // Same priority — most recently active first
                return a.value.lastActivity > b.value.lastActivity
            }
            .map(\.key)
    }

    private func rotateToNextSession() {
        guard activeIds.count > 1 else {
            rotatingSessionId = nil
            return
        }
        if let current = rotatingSessionId, let idx = activeIds.firstIndex(of: current) {
            rotatingSessionId = activeIds[(idx + 1) % activeIds.count]
        } else {
            rotatingSessionId = activeIds.first
        }
        ESP32StatePublisher.shared.notifyDirty()
        AppleCompanionPublisher.shared.notifyDirty()
    }
}
