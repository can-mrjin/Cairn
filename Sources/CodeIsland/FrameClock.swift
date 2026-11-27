import AppKit
import Observation
import QuartzCore
import SwiftUI

/// Redraws `content` on a shared display-synchronized clock (`FrameTicker`),
/// aligned to the host screen's VSync via `CADisplayLink` while capping
/// per-frame SwiftUI Canvas ticks to a power-efficient 30 Hz ceiling.
///
/// Panel expand/collapse springs run natively at 120 Hz ProMotion on the GPU
/// via Core Animation; pushing pixel mascots and shimmers through SwiftUI
/// `@Observable` at 120 Hz saturated CPU/GPU and thrashed `CABackingStore`
/// on every frame. Keeping the shared VSync clock at 20–30 Hz eliminates
/// layout/backing-store storms while remaining completely smooth and tearing-free.
struct FrameClock<Content: View>: View {
    let interval: TimeInterval
    let content: (TimeInterval) -> Content

    init(interval: TimeInterval, @ViewBuilder content: @escaping (TimeInterval) -> Content) {
        self.interval = FrameTicker.quantizedInterval(for: interval)
        self.content = content
    }

    var body: some View {
        FrameClockFace(beat: FrameTicker.shared.beat(every: interval), content: content)
    }
}

private struct FrameClockFace<Content: View>: View {
    let beat: FrameBeat
    let content: (TimeInterval) -> Content

    var body: some View {
        content(beat.now)
            // The ticker runs while some clock is on screen, and stops with the
            // last one: a still island schedules nothing.
            .task {
                beat.attach()
                defer { beat.detach() }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(86_400))
                }
            }
    }
}

/// The time of the latest tick, for the clocks of one interval.
@MainActor
@Observable
final class FrameBeat {
    let interval: TimeInterval
    fileprivate(set) var now = Date.timeIntervalSinceReferenceDate
    @ObservationIgnored fileprivate var clocks = 0
    @ObservationIgnored fileprivate var lastTick: TimeInterval = 0

    fileprivate init(interval: TimeInterval) {
        self.interval = interval
    }

    fileprivate func attach() {
        clocks += 1
        FrameTicker.shared.start()
        FrameTicker.shared.updateDisplayLinkCadence()
    }

    fileprivate func detach() {
        clocks = max(0, clocks - 1)
        FrameTicker.shared.stopIfIdle()
        FrameTicker.shared.updateDisplayLinkCadence()
    }
}

private final class DisplayLinkProxy: NSObject {
    var onTick: ((TimeInterval) -> Void)?

    @objc func handleTick(_ sender: CADisplayLink) {
        onTick?(sender.targetTimestamp)
    }
}

/// The single VSync-aligned clock behind every `FrameClock`.
/// Adapts `CADisplayLink` to the bound `NSScreen` (respecting 60–120 Hz
/// hardware VSync grids while pacing SwiftUI Canvas updates to 20–30 Hz for
/// minimal CPU/GPU cost), and stops completely once no clock is attached.
@MainActor
final class FrameTicker {
    static let shared = FrameTicker()

    /// Smooth VSync-aligned Canvas step (30 Hz ceiling — divides evenly into
    /// both 60 Hz external displays and 120 Hz ProMotion displays).
    nonisolated static let step: TimeInterval = 1.0 / 30.0

    private var beats: [Int: FrameBeat] = [:]
    private weak var boundScreen: NSScreen?
    private(set) var targetRefreshRate: Int = 60
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private var fallbackTask: Task<Void, Never>?

    nonisolated static func clampedRefreshRate(_ rawFPS: Int) -> Int {
        guard rawFPS > 0 else { return 60 }
        return min(120, max(60, rawFPS))
    }

    nonisolated static func quantizedInterval(for interval: TimeInterval) -> TimeInterval {
        if interval <= step + 1e-9 {
            return step
        }
        return max(step, (interval / 0.05).rounded() * 0.05)
    }

    nonisolated static func steps(for interval: TimeInterval) -> Double {
        max(1, (quantizedInterval(for: interval) / step).rounded())
    }

    /// Whether the ticker is running; it stops once no clock is attached.
    var isRunning: Bool { displayLink != nil || fallbackTask != nil }

    /// Bind the ticker to the screen currently hosting the notch panel so
    /// `CADisplayLink` tracks ProMotion (120 Hz) vs external (60 Hz) displays.
    func bind(to screen: NSScreen?) {
        let newFPS = Self.clampedRefreshRate(screen?.maximumFramesPerSecond ?? 60)
        let screenChanged = boundScreen !== screen || targetRefreshRate != newFPS
        boundScreen = screen
        targetRefreshRate = newFPS

        if screenChanged, isRunning {
            stopDrivers()
            start()
        }
    }

    func beat(every interval: TimeInterval) -> FrameBeat {
        let quantized = Self.quantizedInterval(for: interval)
        let key = Int((quantized * 1000).rounded())
        if let beat = beats[key] { return beat }
        let beat = FrameBeat(interval: quantized)
        beats[key] = beat
        return beat
    }

    fileprivate func start() {
        guard !isRunning else { return }
        guard hasActiveClocks else { return }

        if let screen = boundScreen {
            let proxy = DisplayLinkProxy()
            proxy.onTick = { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.tick()
                }
            }
            let link = screen.displayLink(target: proxy, selector: #selector(DisplayLinkProxy.handleTick(_:)))
            let preferredFPS = desiredDriverFPS()
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: min(8, preferredFPS),
                maximum: preferredFPS,
                preferred: preferredFPS
            )
            link.add(to: .main, forMode: .common)
            self.displayLinkProxy = proxy
            self.displayLink = link
            return
        }

        // Headless fallback (e.g. unit tests without an attached NSScreen).
        let frameInterval = Self.step
        fallbackTask = Task { [weak self] in
            while let self, self.hasActiveClocks, !Task.isCancelled {
                let wait = frameInterval - Date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: frameInterval)
                try? await Task.sleep(for: .seconds(max(0.005, wait)))
                guard !Task.isCancelled else { break }
                self.tick()
            }
            self?.fallbackTask = nil
        }
    }

    /// Dynamically adapts the CADisplayLink rate to the fastest currently-attached
    /// beat so 10–12 Hz mascots/shimmers don't wake the CPU & GPU at 30 Hz.
    fileprivate func updateDisplayLinkCadence() {
        guard let link = displayLink, hasActiveClocks else { return }
        let preferredFPS = desiredDriverFPS()
        let current = link.preferredFrameRateRange.preferred ?? 0
        if abs(current - preferredFPS) >= 1 {
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: min(8, preferredFPS),
                maximum: preferredFPS,
                preferred: preferredFPS
            )
        }
    }

    private func desiredDriverFPS() -> Float {
        let minInterval = beats.values
            .filter { $0.clocks > 0 }
            .map(\.interval)
            .min() ?? Self.step
        let rawFPS = (1.0 / max(Self.step, minInterval)).rounded()
        return Float(min(Double(min(30, targetRefreshRate)), max(6, rawFPS)))
    }

    fileprivate func stopIfIdle() {
        guard !hasActiveClocks else { return }
        stopDrivers()
    }

    private var hasActiveClocks: Bool {
        beats.values.contains(where: { $0.clocks > 0 })
    }

    private func stopDrivers() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkProxy = nil
        fallbackTask?.cancel()
        fallbackTask = nil
    }

    private func tick() {
        guard hasActiveClocks else {
            stopDrivers()
            return
        }
        let now = Date.timeIntervalSinceReferenceDate
        let driverStep = Self.step
        for beat in beats.values where beat.clocks > 0 {
            if beat.interval <= Self.step + 1e-9 {
                beat.lastTick = now
                beat.now = now
            } else if now - beat.lastTick >= beat.interval - driverStep * 0.25 {
                beat.lastTick = now
                beat.now = now
            }
        }
    }
}
