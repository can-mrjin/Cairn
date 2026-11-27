import AppKit
import SwiftUI
import os.log

private let log = Logger(subsystem: "com.codeisland", category: "Panel")

private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// The island deliberately overlaps the menu-bar / notch area. AppKit's
    /// default constrain clamps borderless windows below the menu bar whenever
    /// the system re-places windows (display reconfigure, wake from sleep),
    /// which detaches the panel from the notch (#263).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Ensures first click on a nonactivatingPanel fires SwiftUI actions
/// instead of being consumed for key-window activation.
/// Also guards against NSHostingView constraint-update re-entrancy crash:
/// during updateConstraints(), SwiftUI may invalidate the view graph and
/// call setNeedsUpdateConstraints again, which AppKit forbids.
private class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// When true, the deferred handler is setting super — don't re-defer.
    private var applyingDeferred = false
    /// Returns false on surfaces with no text inputs (e.g. `.completionCard`) so
    /// clicking a card to jump to an app never steals key-window focus first.
    var shouldBecomeKeyOnMouseDown: (() -> Bool)?

    override func mouseDown(with event: NSEvent) {
        if shouldBecomeKeyOnMouseDown?() ?? true {
            window?.makeKey()
        }
        super.mouseDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Latest requested value awaiting its deferred apply, or nil when nothing
    /// is queued. Coalescing matters: SwiftUI sets these several times per
    /// animation frame, and the mascot drives frames continuously, so one
    /// `DispatchQueue.main.async` per *set* was a permanent stream of closure
    /// allocations and main-queue wakeups on an otherwise idle Mac (#299).
    private var pendingConstraintsValue: Bool?
    private var pendingLayoutValue: Bool?

    /// Always defer `needsUpdateConstraints = true` to the next run-loop turn.
    /// During AppKit's display-cycle (constraint-update or layout phases),
    /// calling setNeedsUpdateConstraints synchronously re-enters
    /// `_postWindowNeedsUpdateConstraints` and throws.  Deferring avoids
    /// that entirely; the one-tick delay is imperceptible.
    override var needsUpdateConstraints: Bool {
        get { super.needsUpdateConstraints }
        set {
            if applyingDeferred {
                super.needsUpdateConstraints = newValue
                return
            }
            // Nothing queued and already in the requested state — no-op.
            if pendingConstraintsValue == nil, super.needsUpdateConstraints == newValue { return }
            let alreadyScheduled = pendingConstraintsValue != nil
            pendingConstraintsValue = newValue
            guard !alreadyScheduled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let value = self.pendingConstraintsValue else { return }
                self.pendingConstraintsValue = nil
                self.applySuperNeedsUpdateConstraints(value)
            }
        }
    }

    private func applySuperNeedsUpdateConstraints(_ value: Bool) {
        applyingDeferred = true
        super.needsUpdateConstraints = value
        applyingDeferred = false
    }

    override var needsLayout: Bool {
        get { super.needsLayout }
        set {
            if applyingDeferred {
                super.needsLayout = newValue
                return
            }
            if pendingLayoutValue == nil, super.needsLayout == newValue { return }
            let alreadyScheduled = pendingLayoutValue != nil
            pendingLayoutValue = newValue
            guard !alreadyScheduled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let value = self.pendingLayoutValue else { return }
                self.pendingLayoutValue = nil
                self.applySuperNeedsLayout(value)
            }
        }
    }

    private func applySuperNeedsLayout(_ value: Bool) {
        applyingDeferred = true
        super.needsLayout = value
        applyingDeferred = false
    }
}

struct PanelScreenHopFrames {
    let outgoing: NSRect
    let incoming: NSRect
}

struct PanelScreenHopMotion {
    let outgoingOffset: CGFloat
    let incomingOffset: CGFloat
    let fadeOutDuration: TimeInterval
    let incomingPauseDuration: TimeInterval
    let fadeInDuration: TimeInterval
}

enum PanelHeightMetrics {
    /// Window height the panel asks for before clamping to the screen: room
    /// for `maxVisibleSessions` cards plus the notch bar. Shared with the
    /// completion card, whose reply area has to fit inside the same window.
    static func desiredHeight(maxVisibleSessions: Int) -> CGFloat {
        let sessions = CGFloat(max(2, maxVisibleSessions))
        return max(300, sessions * 90 + 60)
    }
}

/// Hide in Fullscreen's hold on the island: the latch a fullscreen app on
/// the island's display sets, and the reveal a shortcut makes over it.
struct PanelFullscreenHide {
    /// The island's display shows a fullscreen app.
    private(set) var isLatched = false
    /// A shortcut asked for the island while the latch hid it. Hide in
    /// Fullscreen keeps the island out of the way by itself; a key press
    /// that asks for it gets it, until it collapses again (#384).
    private(set) var isRevealed = false

    mutating func latch() { isLatched = true }

    mutating func unlatch() {
        isLatched = false
        isRevealed = false
    }

    mutating func reveal() {
        if isLatched { isRevealed = true }
    }

    mutating func islandCollapsed() { isRevealed = false }

    func hidesIsland(hideInFullscreen: Bool) -> Bool {
        hideInFullscreen && isLatched && !isRevealed
    }
}

/// Where the island is for a shortcut the user just pressed.
enum PanelSight {
    /// Whether the press should bring the island to the user rather than
    /// take it as seen. It should when the island is hidden over a
    /// fullscreen app, or up on another display than the one being worked
    /// on — or on its way between two — with the user not on it (typing
    /// into its card, pointing at it). Hidden for another reason — no
    /// session running — there is nothing to bring.
    static func isAway(
        hiddenInFullscreen: Bool,
        isShown: Bool,
        userIsOnIsland: Bool,
        isOnWorkingDisplay: @autoclosure () -> Bool
    ) -> Bool {
        if hiddenInFullscreen { return true }
        guard isShown, !userIsOnIsland else { return false }
        return !isOnWorkingDisplay()
    }
}

@MainActor
class PanelWindowController: NSObject, NSWindowDelegate {
    private enum ScreenHopMetrics {
        static let outgoingOffset: CGFloat = 18
        static let incomingOffset: CGFloat = 30
        static let fadeOutDuration: TimeInterval = 0.14
        static let incomingPauseDuration: TimeInterval = 0.06
        static let fadeInDuration: TimeInterval = 0.34
    }

    nonisolated static func screenHopMotion() -> PanelScreenHopMotion {
        PanelScreenHopMotion(
            outgoingOffset: ScreenHopMetrics.outgoingOffset,
            incomingOffset: ScreenHopMetrics.incomingOffset,
            fadeOutDuration: ScreenHopMetrics.fadeOutDuration,
            incomingPauseDuration: ScreenHopMetrics.incomingPauseDuration,
            fadeInDuration: ScreenHopMetrics.fadeInDuration
        )
    }

    private var panel: NSPanel?
    private var stageView: NotchSilhouetteStageView?
    private var hostingView: NotchHostingView<NotchPanelView>?
    private let appState: AppState

    nonisolated static func screenHopFrames(
        oldFrame: NSRect,
        newFrame: NSRect
    ) -> PanelScreenHopFrames {
        let motion = screenHopMotion()
        return PanelScreenHopFrames(
            outgoing: oldFrame.offsetBy(dx: 0, dy: motion.outgoingOffset),
            incoming: newFrame.offsetBy(dx: 0, dy: motion.incomingOffset)
        )
    }

    private func panelSize(for screen: NSScreen) -> NSSize {
        let desiredH = PanelHeightMetrics.desiredHeight(
            maxVisibleSessions: UserDefaults.standard.integer(forKey: SettingsKey.maxVisibleSessions)
        )
        // Clamp to the screen's usable height. A borderless, non-opaque panel with a
        // very tall backing store (e.g. maxVisibleSessions=99 → 8970pt, ~18k px tall on
        // a Retina display) has its compositing dropped by the macOS 26 WindowServer
        // once the surface goes idle — the card renders blank until a mouse event forces
        // a redraw, which looked like "invisible after ~2s, reappears on hover" (#304).
        // The content is top-anchored and the session list scrolls internally, so the
        // window never needs to be taller than the visible screen.
        let maxH = min(desiredH, screen.visibleFrame.height)
        let screenW = screen.frame.width
        let desiredW = max(620, CGFloat(SettingsManager.shared.expandedPanelWidth) + 40)
        let width = min(desiredW, screenW - 40)
        return NSSize(width: width, height: maxH)
    }

    private var panelSize: NSSize {
        panelSize(for: chosenScreen())
    }

    private var visibilityTimer: Timer?
    private var autoScreenPoller: Timer?
    private var fullscreenPoller: Timer?
    private var hoverExpandTimer: Timer?
    private var hoverCollapseTimer: Timer?
    private var autoHideAfterCollapseWork: DispatchWorkItem?
    private var lastObservedSurface: IslandSurface = .collapsed
    private var currentTopBarHeight: CGFloat = 34
    private var isSessionObservationArmed = false
    private var fullscreenHide = PanelFullscreenHide()
    private var settingsObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var globalClickMonitor: Any?
    private var globalMouseMoveMonitor: Any?
    private var localMouseMoveMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var lastChosenScreenSignature = ""
    private var isAnimatingScreenHop = false
    private var pendingForcedRebuild = false
    private var dragStartMouseX: CGFloat?
    private var dragStartPanelX: CGFloat?
    private var isDraggingPanel = false
    private var localDragMonitor: Any?
    private struct LayoutSettingsSnapshot: Equatable {
        let hideInFullscreen: Bool
        let hideWhenNoSession: Bool
        let allowHorizontalDrag: Bool
        let panelHorizontalOffset: Double
        let avoidMenuBarIcons: Bool
        let expandedPanelWidth: Int
        let maxVisibleSessions: Int

        @MainActor
        static func current() -> Self {
            let s = SettingsManager.shared
            return Self(
                hideInFullscreen: s.hideInFullscreen,
                hideWhenNoSession: s.hideWhenNoSession,
                allowHorizontalDrag: s.allowHorizontalDrag,
                panelHorizontalOffset: s.panelHorizontalOffset,
                avoidMenuBarIcons: s.avoidMenuBarIcons,
                expandedPanelWidth: s.expandedPanelWidth,
                maxVisibleSessions: UserDefaults.standard.integer(forKey: SettingsKey.maxVisibleSessions)
            )
        }
    }

    private var lastDisplayChoice = ""
    private var lastNotchHeightMode = SettingsDefaults.notchHeightMode
    private var lastCustomNotchHeight = SettingsDefaults.customNotchHeight
    private var lastLayoutSettingsSnapshot: LayoutSettingsSnapshot?

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    /// Watch `sessions` / `surface` for changes that affect panel visibility.
    ///
    /// `withObservationTracking` is one-shot, so it has to be re-armed. Doing
    /// that from a 500 ms polling loop meant a permanent timer wakeup on a Mac
    /// where nothing was happening (#299) — and it bought nothing, because the
    /// loop never *detected* anything: `onChange` already fires the instant a
    /// tracked property is written. Re-arm from `onChange` instead, so an idle
    /// app schedules no work at all.
    ///
    /// Re-arming happens in the same main-actor turn as `updateVisibility()`,
    /// with no await between them, so no mutation can slip through the window
    /// where tracking is momentarily disarmed.
    private func armSessionObservation() {
        guard !isSessionObservationArmed else { return }
        isSessionObservationArmed = true
        withObservationTracking {
            _ = appState.sessions
            _ = appState.surface
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isSessionObservationArmed = false
                let newSurface = self.appState.surface
                let surfaceChanged = newSurface != self.lastObservedSurface
                self.lastObservedSurface = newSurface
                if surfaceChanged {
                    self.handleSurfaceTransitionForHover(newSurface)
                }
                self.updateVisibility()
                self.armSessionObservation()
            }
        }
    }

    func showPanel() {
        let screen = chosenScreen()
        let stage = makeStageView(for: screen)
        self.stageView = stage

        let size = panelSize
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.acceptsMouseMovedEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .readOnly
        panel.contentView = stage
        panel.delegate = self

        self.panel = panel
        self.lastChosenScreenSignature = ScreenDetector.signature(for: screen)
        // A follow-up for the card under the pointer would remind someone who
        // is already reading it. The island's own hover says whether the
        // pointer is on the card (`pointerOverIsland`); the window frame —
        // mostly transparent, and as large as the card ever gets — only
        // backs that up against a hover flag a rebuilt view left behind.
        appState.followUps.isPointerOverPanel = { [weak self] in
            guard let panel = self?.panel, panel.isVisible else { return false }
            return panel.frame.contains(NSEvent.mouseLocation)
        }

        setupHorizontalDragMonitor()
        setupPointerHoverMonitors()
        updatePosition()
        panel.orderFrontRegardless()
        MascotAnimationGate.shared.setPanelVisible(true)

        // Screen change observer
        let screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCurrentScreen(forceRebuild: true)
                // macOS may not have finished updating NSScreen.screens when the notification fires.
                // Rebuild again after a short delay to pick up the final screen configuration.
                try? await Task.sleep(nanoseconds: 500_000_000)
                self?.refreshCurrentScreen(forceRebuild: true)
                // A pinned display that went away leaves the island to Auto
                // until it is back.
                self?.configureAutoScreenPolling()
            }
        }
        settingsObservers.append(screenObserver)

        // Active space change — check fullscreen
        let spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.refreshCurrentScreen()
                if self.isActiveSpaceFullscreen() {
                    self.fullscreenHide.latch()
                    self.updateVisibility()
                    self.startFullscreenExitPoller()
                } else {
                    // Non-fullscreen space: clear any stale latch immediately so the panel
                    // doesn't stay hidden for up to 1.5s while the exit poller catches up (#104).
                    if self.fullscreenHide.isLatched {
                        self.fullscreenHide.unlatch()
                        self.fullscreenPoller?.invalidate()
                        self.fullscreenPoller = nil
                    }
                    self.updateVisibility()
                }
            }
        }
        workspaceObservers.append(spaceObserver)

        // Frontmost app change
        let appActivateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.refreshCurrentScreen()
                if !self.fullscreenHide.isLatched { self.updateVisibility() }
            }
        }
        workspaceObservers.append(appActivateObserver)

        // Observe session changes via @Observable tracking
        armSessionObservation()

        // Observe settings changes (display choice, panel height)
        observeSettingsChanges()
        configureAutoScreenPolling()

        // Global click monitor: close panel + repost click when clicking outside
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                guard let self = self, self.appState.surface.isExpanded else { return }
                guard SettingsManager.shared.dismissOnOutsideClick else { return }
                // Don't close during approval/question
                switch self.appState.surface {
                case .approvalCard, .questionCard: return
                default: break
                }
                // Don't collapse if click landed inside the actual visible black island
                // (panelFrame spans the full usable screen height and is mostly transparent below).
                if let panelFrame = self.panel?.frame {
                    let clickLocation = NSEvent.mouseLocation
                    let visibleSize = self.appState.visibleIslandSize
                    if visibleSize.width > 1 && visibleSize.height > 1 {
                        let visibleW = min(panelFrame.width, visibleSize.width + 16)
                        let visibleH = min(panelFrame.height, visibleSize.height + 8)
                        let visibleRect = NSRect(
                            x: panelFrame.midX - visibleW / 2,
                            y: panelFrame.maxY - visibleH,
                            width: visibleW,
                            height: visibleH
                        )
                        if visibleRect.contains(clickLocation) { return }
                    } else if panelFrame.contains(clickLocation) {
                        return
                    }
                }
                self.appState.surface = .collapsed
                self.appState.cancelCompletionQueue()
            }
        }

        // Local ⌘1..⌘9 quick-jump while the Session Hub list is expanded & focused
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == .command,
                  let chars = event.charactersIgnoringModifiers,
                  chars.count == 1,
                  let digit = Int(chars),
                  (1...9).contains(digit) else {
                return event
            }
            guard self.appState.surface == .sessionList else { return event }
            let index = digit - 1
            let ids = self.appState.lastVisibleHubSessionIds
            guard ids.indices.contains(index) else { return event }
            let sid = ids[index]
            guard let session = self.appState.sessions[sid] else { return event }
            self.appState.markSessionRead(sid)
            TerminalActivator.activate(session: session, sessionId: sid)
            if UserDefaults.standard.bool(forKey: SettingsKey.autoCollapseAfterSessionJump) {
                self.appState.surface = .collapsed
            }
            return nil
        }
    }

    private func makeStageView(for screen: NSScreen) -> NotchSilhouetteStageView {
        FrameTicker.shared.bind(to: screen)

        let hasNotch = ScreenDetector.screenHasNotch(screen)
        let notchHeight = ScreenDetector.topBarHeight(for: screen)
        self.currentTopBarHeight = notchHeight
        let notchW = ScreenDetector.notchWidth(for: screen)

        weak var stageRef: NotchSilhouetteStageView?
        let rootView = NotchPanelView(
            appState: appState,
            hasNotch: hasNotch,
            notchHeight: notchHeight,
            notchW: notchW,
            screenWidth: screen.frame.width,
            onSilhouetteChange: { target, animated in
                stageRef?.updateSilhouette(to: target, animated: animated)
            }
        )
        let contentView = NotchHostingView(rootView: rootView)
        contentView.shouldBecomeKeyOnMouseDown = { [weak self] in
            guard let surface = self?.appState.surface else { return true }
            if case .completionCard = surface { return false }
            return true
        }
        contentView.wantsLayer = true
        contentView.sizingOptions = []
        contentView.translatesAutoresizingMaskIntoConstraints = true
        self.hostingView = contentView

        let stage = NotchSilhouetteStageView(hostingView: contentView)
        stageRef = stage
        stage.onPointerActivity = { [weak self] in
            MainActor.assumeIsolated {
                self?.evaluatePointerHover(at: NSEvent.mouseLocation)
            }
        }
        return stage
    }

    /// Rebuild the SwiftUI view when the target screen changes
    /// (notchHeight, notchWidth, hasNotch may be different)
    private func rebuildForCurrentScreen(_ screen: NSScreen) {
        guard let panel = panel else { return }
        let stage = makeStageView(for: screen)
        self.stageView = stage
        panel.contentView = stage
        lastChosenScreenSignature = ScreenDetector.signature(for: screen)
        panel.setFrame(panelFrame(for: screen), display: true)
    }

    private func finishScreenHop(signature: String?) {
        if let signature {
            lastChosenScreenSignature = signature
        }
        isAnimatingScreenHop = false
        if pendingForcedRebuild {
            pendingForcedRebuild = false
            refreshCurrentScreen(forceRebuild: true)
        }
    }

    private func refreshCurrentScreen(forceRebuild: Bool = false) {
        if isAnimatingScreenHop {
            if forceRebuild {
                pendingForcedRebuild = true
            }
            return
        }

        let screen = chosenScreen()
        let signature = ScreenDetector.signature(for: screen)

        if forceRebuild {
            rebuildForCurrentScreen(screen)
            return
        }

        // Not out from under the user: a move rebuilds the island, and one
        // while they point at it or type into it took their half-typed answer
        // and their place with it. It follows at the next check once they've
        // left it (the poll, the next app switch or Space change).
        if signature != lastChosenScreenSignature, !isUserOnIsland {
            animateScreenHop(to: screen, signature: signature)
        }
    }

    private func animateScreenHop(to screen: NSScreen, signature: String) {
        guard let panel = panel else {
            rebuildForCurrentScreen(screen)
            return
        }

        if !panel.isVisible || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            rebuildForCurrentScreen(screen)
            panel.alphaValue = 1
            return
        }

        isAnimatingScreenHop = true
        let oldFrame = panel.frame
        let initialNewFrame = panelFrame(for: screen)
        let motion = Self.screenHopMotion()
        let initialFrames = Self.screenHopFrames(oldFrame: oldFrame, newFrame: initialNewFrame)
        let requestedSignature = signature

        NSAnimationContext.runAnimationGroup { context in
            context.duration = motion.fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(initialFrames.outgoing, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard let panel = self.panel else {
                    self.finishScreenHop(signature: nil)
                    return
                }

                let targetScreen = NSScreen.screens.first {
                    ScreenDetector.signature(for: $0) == requestedSignature
                } ?? self.chosenScreen()
                let resolvedSignature = ScreenDetector.signature(for: targetScreen)
                let resolvedNewFrame = self.panelFrame(for: targetScreen)
                let resolvedFrames = Self.screenHopFrames(oldFrame: oldFrame, newFrame: resolvedNewFrame)

                self.rebuildForCurrentScreen(targetScreen)
                panel.alphaValue = 0
                panel.setFrame(resolvedFrames.incoming, display: true)

                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(motion.incomingPauseDuration * 1_000_000_000))
                    guard let self = self else { return }
                    guard let panel = self.panel else {
                        self.finishScreenHop(signature: nil)
                        return
                    }

                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = motion.fadeInDuration
                        context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                        panel.animator().alphaValue = 1
                        panel.animator().setFrame(resolvedNewFrame, display: true)
                    } completionHandler: { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.finishScreenHop(signature: resolvedSignature)
                        }
                    }
                }
            }
        }
    }

    private func observeSettingsChanges() {
        lastDisplayChoice = SettingsManager.shared.displayChoice
        lastNotchHeightMode = SettingsManager.shared.notchHeightMode.rawValue
        lastCustomNotchHeight = SettingsManager.shared.customNotchHeight
        lastLayoutSettingsSnapshot = LayoutSettingsSnapshot.current()
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let newChoice = SettingsManager.shared.displayChoice
                let newHeightMode = SettingsManager.shared.notchHeightMode.rawValue
                let newCustomHeight = SettingsManager.shared.customNotchHeight
                if newChoice != self.lastDisplayChoice {
                    self.lastDisplayChoice = newChoice
                    self.lastLayoutSettingsSnapshot = LayoutSettingsSnapshot.current()
                    self.refreshCurrentScreen(forceRebuild: true)
                    self.configureAutoScreenPolling()
                } else if newHeightMode != self.lastNotchHeightMode
                    || abs(newCustomHeight - self.lastCustomNotchHeight) > 0.001 {
                    self.lastNotchHeightMode = newHeightMode
                    self.lastCustomNotchHeight = newCustomHeight
                    self.lastLayoutSettingsSnapshot = LayoutSettingsSnapshot.current()
                    self.refreshCurrentScreen(forceRebuild: true)
                } else {
                    // Ignore unrelated UserDefaults writes (Sparkle checks, sound,
                    // language, etc.) so they never trigger expensive fullscreen
                    // checks or menu-bar CGWindowList scans.
                    let snapshot = LayoutSettingsSnapshot.current()
                    guard snapshot != self.lastLayoutSettingsSnapshot else { return }
                    self.lastLayoutSettingsSnapshot = snapshot

                    if snapshot.hideInFullscreen && !self.fullscreenHide.isLatched && self.isActiveSpaceFullscreen() {
                        self.fullscreenHide.latch()
                        self.startFullscreenExitPoller()
                    }
                    self.updateVisibility()
                    self.updatePosition()
                }
            }
        }
        settingsObservers.append(observer)
    }

    private func configureAutoScreenPolling() {
        autoScreenPoller?.invalidate()
        autoScreenPoller = nil

        // Single-display Macs cannot hop between displays; didChangeScreenParametersNotification
        // re-invokes configureAutoScreenPolling() whenever an external monitor is attached.
        guard !isPinnedToConnectedDisplay, NSScreen.screens.count > 1 else { return }

        // Screen-parameter / Space-change / frontmost-app notifications already cover the
        // common cases. This poller is a fallback for the rare path where a window is
        // dragged to another display without switching focus — a low cadence is enough
        // and every tick runs a full CGWindowListCopyWindowInfo, which was measurably
        // contributing to Energy Impact (#92).
        let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCurrentScreen()
            }
        }
        timer.tolerance = 1.5
        autoScreenPoller = timer
    }

    private func updatePosition() {
        guard let panel = panel else { return }
        let screen = chosenScreen()
        // Another display than the one the view was built for is a display
        // change, which rebuilds the view for that display's notch.
        guard ScreenDetector.signature(for: screen) == lastChosenScreenSignature else {
            refreshCurrentScreen()
            return
        }
        let targetFrame = panelFrame(for: screen)
        let currentFrame = panel.frame
        let unchanged = abs(currentFrame.origin.x - targetFrame.origin.x) <= 0.5
            && abs(currentFrame.origin.y - targetFrame.origin.y) <= 0.5
            && abs(currentFrame.size.width - targetFrame.size.width) <= 0.5
            && abs(currentFrame.size.height - targetFrame.size.height) <= 0.5
        guard !unchanged else { return }
        panel.setFrame(targetFrame, display: true)
    }

    private func panelFrame(for screen: NSScreen) -> NSRect {
        let size = panelSize(for: screen)
        let screenFrame = screen.frame
        let centeredX = centeredX(for: size, screen: screen)
        let dragOffset = SettingsManager.shared.allowHorizontalDrag
            ? CGFloat(SettingsManager.shared.panelHorizontalOffset)
            : 0
        var desiredX = centeredX + dragOffset

        // #219: on external screens the simulated notch can land on third-party
        // status items (Bartender & co.) — slide it into the nearest clear gap.
        // A user-dragged offset is an explicit choice and always wins.
        if SettingsManager.shared.avoidMenuBarIcons,
           dragOffset == 0,
           !ScreenDetector.screenHasNotch(screen) {
            let occupied = MenuBarIconAvoidance.occupiedMenuBarRanges(on: screen)
            desiredX = MenuBarIconAvoidance.resolvedX(
                preferredX: desiredX,
                panelWidth: size.width,
                occupied: occupied,
                screenMinX: screenFrame.minX,
                screenMaxX: screenFrame.maxX,
                maxShift: screenFrame.width * MenuBarIconAvoidance.maxShiftFraction
            )
        }

        let x = clampedX(desiredX, panelWidth: size.width, on: screen)
        let y = screenFrame.maxY - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func centeredX(for size: NSSize, screen: NSScreen) -> CGFloat {
        screen.frame.midX - size.width / 2
    }

    private func clampedX(_ desiredX: CGFloat, panelWidth: CGFloat, on screen: NSScreen) -> CGFloat {
        min(max(desiredX, screen.frame.minX), screen.frame.maxX - panelWidth)
    }

    private func setupHorizontalDragMonitor() {
        let dragThreshold: CGFloat = 5

        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, let panel = self.panel,
                  SettingsManager.shared.allowHorizontalDrag else { return event }

            switch event.type {
            case .leftMouseDown:
                if event.window === panel {
                    self.dragStartMouseX = NSEvent.mouseLocation.x
                    self.dragStartPanelX = panel.frame.origin.x
                    self.isDraggingPanel = false
                }
            case .leftMouseDragged:
                if let startMouseX = self.dragStartMouseX,
                   let startPanelX = self.dragStartPanelX {
                    let deltaX = NSEvent.mouseLocation.x - startMouseX
                    // Only start moving after exceeding threshold
                    if !self.isDraggingPanel {
                        guard abs(deltaX) > dragThreshold else { return event }
                        self.isDraggingPanel = true
                    }
                    let screen = self.chosenScreen()
                    let size = panel.frame.size
                    let newX = self.clampedX(startPanelX + deltaX, panelWidth: size.width, on: screen)
                    let fixedY = screen.frame.maxY - size.height
                    panel.setFrameOrigin(NSPoint(x: newX, y: fixedY))
                }
            case .leftMouseUp:
                if self.isDraggingPanel, let panel = self.panel {
                    let screen = self.chosenScreen()
                    let size = panel.frame.size
                    let offset = panel.frame.origin.x - self.centeredX(for: size, screen: screen)
                    SettingsManager.shared.panelHorizontalOffset = Double(offset)
                }
                self.dragStartMouseX = nil
                self.dragStartPanelX = nil
                self.isDraggingPanel = false
            default:
                break
            }
            return event
        }
    }

    /// Choose which screen to display on based on displayChoice setting
    private func chosenScreen() -> NSScreen {
        let screens = NSScreen.screens
        let uuids = screens.map(ScreenDetector.displayUUID(for:))
        var choice = SettingsManager.shared.displayChoice

        // A pin saved as a screen index takes its display's UUID the first
        // time it resolves; the display it names doesn't change.
        if let migrated = DisplayChoice.migrated(choice, displayUUIDs: uuids) {
            lastDisplayChoice = migrated
            SettingsManager.shared.displayChoice = migrated
            choice = migrated
        }
        return ScreenDetector.screen(forDisplayChoice: choice)
    }

    /// Whether the island stays on a pinned display, connected now; Auto
    /// (and a missing pin) follows the window in front.
    private var isPinnedToConnectedDisplay: Bool {
        let uuids = NSScreen.screens.map(ScreenDetector.displayUUID(for:))
        if case .pinned = DisplayChoice.resolve(SettingsManager.shared.displayChoice, displayUUIDs: uuids) {
            return true
        }
        return false
    }

    /// Poll every 3.0s while in fullscreen; stop when fullscreen ends
    private func startFullscreenExitPoller() {
        fullscreenPoller?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else { timer.invalidate(); return }
                if !SettingsManager.shared.hideInFullscreen || !self.isActiveSpaceFullscreen() {
                    self.fullscreenHide.unlatch()
                    self.updateVisibility()
                    timer.invalidate()
                    self.fullscreenPoller = nil
                }
            }
        }
        timer.tolerance = 1.0
        fullscreenPoller = timer
    }

    /// Update panel visibility based on settings
    private func updateVisibility() {
        guard let panel = panel else { return }
        let settings = SettingsManager.shared
        // A shortcut's reveal lasts while the island stays open.
        if !appState.surface.isExpanded { fullscreenHide.islandCollapsed() }
        if fullscreenHide.hidesIsland(hideInFullscreen: settings.hideInFullscreen) {
            panel.orderOut(nil)
            MascotAnimationGate.shared.setPanelVisible(false)
            return
        }

        if settings.hideWhenNoSession && appState.activeSessionCount == 0 {
            let revealForInteraction = appState.surface.isExpanded
                || appState.pointerPrehovering
                || autoHideAfterCollapseWork != nil
            if !revealForInteraction {
                panel.orderOut(nil)
                MascotAnimationGate.shared.setPanelVisible(false)
                return
            }
        } else {
            autoHideAfterCollapseWork?.cancel()
            autoHideAfterCollapseWork = nil
        }

        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        MascotAnimationGate.shared.setPanelVisible(true)
        MascotAnimationGate.shared.setIdleSettled(isIslandSettled())
    }

    /// Collapsed island with nothing running — the state a Mac spends most of
    /// its day in, and the one where a live mascot timeline costs real CPU for
    /// motion nobody is looking at (#299). Any expanded surface, or any session
    /// that is not idle, keeps the mascot animating.
    private func isIslandSettled() -> Bool {
        guard !appState.surface.isExpanded else { return false }
        return appState.sessions.values.allSatisfy { $0.status == .idle }
    }

    /// Whether the frontmost app is fullscreen on the island's display. One
    /// fullscreen on another display — with "Displays have separate Spaces"
    /// each display shows a Space of its own — leaves the island alone.
    private func isActiveSpaceFullscreen() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let primaryMaxY = NSScreen.screens.first?.frame.maxY else { return false }

        // Primary: check if frontmost app has a window covering the entire screen
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return false }
        let appWindows = windowList.compactMap { window -> CGRect? in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  pid == frontApp.processIdentifier,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any] else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
        return ScreenDetector.isFullscreen(
            onScreenFrame: chosenScreen().frame,
            windowListBounds: appWindows,
            primaryScreenMaxY: primaryMaxY
        )
    }

    // MARK: - Shortcuts

    /// Whether the island is up on a screen, whichever display it is on: a
    /// card on it can be seen. Hidden over a fullscreen app, it can't.
    var isIslandOnScreen: Bool {
        panel?.isVisible == true
    }

    /// Whether a shortcut should bring the island to the user rather than
    /// take it as seen (`PanelSight.isAway`). With Auto, the working display
    /// is the one of the window in front, which the island otherwise follows
    /// only on an app switch, a Space change or a 5 s poll — not when the
    /// user moves between two windows of one app on different displays.
    var isIslandAwayFromUser: Bool {
        guard let panel else { return false }
        return PanelSight.isAway(
            hiddenInFullscreen: fullscreenHide.hidesIsland(hideInFullscreen: SettingsManager.shared.hideInFullscreen),
            isShown: panel.isVisible,
            userIsOnIsland: isUserOnIsland,
            isOnWorkingDisplay: !isAnimatingScreenHop
                && ScreenDetector.signature(for: chosenScreen()) == lastChosenScreenSignature
        )
    }

    /// Bring the island to the user for a shortcut they pressed: onto the
    /// display they are working on, and up even where Hide in Fullscreen
    /// hides it, until it collapses again. Call it once the surface the
    /// press opened is set. (#384)
    func bringIslandIntoSight() {
        fullscreenHide.reveal()
        // Typing into its card or pointing at it, the user already has it.
        if !isUserOnIsland { refreshCurrentScreen() }
        updateVisibility()
    }

    /// The user is on the island itself: it holds keyboard focus (they
    /// clicked into it), or the pointer is on it. A view rebuilt mid-hover
    /// can leave `pointerOverIsland` behind, so the window frame backs it up.
    private var isUserOnIsland: Bool {
        guard let panel, panel.isVisible else { return false }
        if panel.isKeyWindow { return true }
        return appState.followUps.pointerOverIsland && panel.frame.contains(NSEvent.mouseLocation)
    }

    /// Whether the island currently holds keyboard focus. It only becomes key
    /// when the user clicks into it (NotchHostingView.mouseDown).
    var isPanelKeyWindow: Bool {
        panel?.isKeyWindow == true
    }

    /// Fast check: is the terminal running the active session the foreground app?
    /// Main-thread safe — no AppleScript or subprocess calls.
    func isActiveTerminalForeground() -> Bool {
        guard let sessionId = appState.activeSessionId,
              let session = appState.sessions[sessionId],
              session.termApp != nil else { return false }
        return TerminalVisibilityDetector.isTerminalFrontmostForSession(session)
    }

    func windowDidMove(_ notification: Notification) {
        // Horizontal drag (setupHorizontalDragMonitor) only ever changes x, and the
        // screen-hop animation runs under isAnimatingScreenHop. A y drifted off the
        // top edge therefore means the system re-placed the panel — e.g. a display
        // reconfigure clamping it below the menu bar (#263) — so snap it back.
        guard !isDraggingPanel, !isAnimatingScreenHop, let panel = panel else { return }
        let expectedY = chosenScreen().frame.maxY - panel.frame.height
        guard abs(panel.frame.origin.y - expectedY) > 0.5 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isDraggingPanel, !self.isAnimatingScreenHop else { return }
            self.updatePosition()
        }
    }

    // MARK: - Event-driven AppKit pointer dwell hover controller
    //
    // SwiftUI `.onHover` on a borderless nonactivating NSPanel drops or sticks
    // across focus switches (e.g. clicking a session card to activate Claude /
    // Antigravity) and programmatic collapses. Watching global + local mouse
    // moves against the exact rendered island rect guarantees that dwelling on
    // the collapsed notch bar for `hoverExpandDelay` ALWAYS pops it open — even
    // milliseconds after clicking a card — while consuming 0% CPU at idle.

    private func setupPointerHoverMonitors() {
        globalMouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluatePointerHover(at: NSEvent.mouseLocation)
            }
        }
        localMouseMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.evaluatePointerHover(at: NSEvent.mouseLocation)
            }
            return event
        }
    }

    /// Screen-space bounding box of the visible island silhouette (collapsed
    /// bar when collapsed; full liquid card panel when expanded).
    /// Pure arithmetic — zero WindowServer/CGWindowList IPC on mouse moves.
    private func visibleIslandHitRect(forExpanded expanded: Bool) -> NSRect? {
        guard let panel else { return nil }
        let settings = SettingsManager.shared
        let autoHiddenForIdle = settings.hideWhenNoSession
            && appState.activeSessionCount == 0
            && !fullscreenHide.hidesIsland(hideInFullscreen: settings.hideInFullscreen)
        guard panel.isVisible || autoHiddenForIdle else { return nil }
        let frame = panel.frame
        let midX = frame.midX + appState.visibleIslandOffsetX
        let topY = frame.maxY
        let topBarH = max(currentTopBarHeight, 32)

        // Include +8pt above `topY` because `NSRect.contains` is half-open
        // (`[minY, maxY)`) and pushing the cursor all the way to the physical
        // top edge of the MacBook display reports `mouseLocation.y == topY`.
        if expanded {
            let w = max(260, appState.visibleIslandSize.width + 18)
            let h = max(topBarH + 10, appState.visibleIslandSize.height + 12)
            return NSRect(x: midX - w / 2, y: topY - h, width: w, height: h + 8)
        } else {
            let collapsedW = appState.collapsedIslandWidth > 1
                ? appState.collapsedIslandWidth
                : max(220, appState.visibleIslandSize.width)
            let w = collapsedW + 14
            let h = topBarH + 8
            return NSRect(x: midX - w / 2, y: topY - h, width: w, height: h + 8)
        }
    }

    private func cancelHoverTimers() {
        hoverExpandTimer?.invalidate()
        hoverExpandTimer = nil
        hoverCollapseTimer?.invalidate()
        hoverCollapseTimer = nil
    }

    private func handleSurfaceTransitionForHover(_ newSurface: IslandSurface) {
        cancelHoverTimers()
        if appState.pointerPrehovering {
            withAnimation(NotchAnimation.hoverPrehover) {
                appState.pointerPrehovering = false
            }
        }
        if newSurface == .collapsed {
            let settings = SettingsManager.shared
            if settings.hideWhenNoSession && appState.activeSessionCount == 0 {
                autoHideAfterCollapseWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.autoHideAfterCollapseWork = nil
                    self.updateVisibility()
                }
                autoHideAfterCollapseWork = work
                let delay = NotchSilhouetteTiming.collapseUnmountDelay(speed: settings.notchAnimationSpeed)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            }
            // Re-evaluate immediately in case the pointer is already sitting on
            // the collapsed notch bar right after a card click collapsed it.
            evaluatePointerHover(at: NSEvent.mouseLocation)
        } else {
            autoHideAfterCollapseWork?.cancel()
            autoHideAfterCollapseWork = nil
            appState.suppressHoverUntilPointerLeaves = false
            updateVisibility()
        }
    }

    private func evaluatePointerHover(at screenPoint: NSPoint) {
        guard !isDraggingPanel else { return }
        let isExpanded = appState.surface.isExpanded
        // Ultra-fast O(1) reject when collapsed and cursor is anywhere below the menu bar
        // (99% of desktop mouse moves) so moving the mouse around apps uses ~0% CPU.
        if !isExpanded,
           let frame = panel?.frame,
           screenPoint.y < frame.maxY - max(currentTopBarHeight, 32) - 16,
           !appState.pointerPrehovering,
           hoverExpandTimer == nil,
           !appState.suppressHoverUntilPointerLeaves {
            appState.followUps.pointerOverIsland = false
            return
        }
        let settings = SettingsManager.shared
        if fullscreenHide.hidesIsland(hideInFullscreen: settings.hideInFullscreen) {
            cancelHoverTimers()
            clearPrehoverIfNeeded()
            return
        }

        let inside = visibleIslandHitRect(forExpanded: isExpanded)?.contains(screenPoint) == true
        appState.followUps.pointerOverIsland = inside

        if !inside && appState.suppressHoverUntilPointerLeaves {
            appState.suppressHoverUntilPointerLeaves = false
        }

        switch appState.surface {
        case .approvalCard, .questionCard:
            cancelHoverTimers()
            return

        case .completionCard:
            if inside {
                appState.completionHasBeenEntered = true
                hoverCollapseTimer?.invalidate()
                hoverCollapseTimer = nil
            } else if appState.completionHasBeenEntered || appState.deferCollapseOnMouseLeave {
                scheduleHoverCollapseIfNeeded(isCompletionCard: true)
            }
            return

        case .collapsed:
            hoverCollapseTimer?.invalidate()
            hoverCollapseTimer = nil

            guard inside else {
                hoverExpandTimer?.invalidate()
                hoverExpandTimer = nil
                clearPrehoverIfNeeded()
                return
            }

            guard settings.hoverToExpand, !appState.suppressHoverUntilPointerLeaves else {
                hoverExpandTimer?.invalidate()
                hoverExpandTimer = nil
                clearPrehoverIfNeeded()
                return
            }
            if settings.smartSuppress && isActiveTerminalForeground() {
                hoverExpandTimer?.invalidate()
                hoverExpandTimer = nil
                clearPrehoverIfNeeded()
                return
            }

            autoHideAfterCollapseWork?.cancel()
            autoHideAfterCollapseWork = nil
            if !appState.pointerPrehovering {
                withAnimation(NotchAnimation.hoverPrehover) {
                    appState.pointerPrehovering = true
                }
                updateVisibility()
            }
            if hoverExpandTimer == nil {
                let delay = NotchHoverInteraction.expandDelay(forSetting: settings.hoverExpandDelay)
                hoverExpandTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.fireHoverExpand()
                    }
                }
            }

        case .sessionList:
            hoverExpandTimer?.invalidate()
            hoverExpandTimer = nil
            if appState.pointerPrehovering {
                appState.pointerPrehovering = false
            }
            if inside {
                hoverCollapseTimer?.invalidate()
                hoverCollapseTimer = nil
            } else if settings.collapseOnMouseLeave {
                scheduleHoverCollapseIfNeeded(isCompletionCard: false)
            }
        }
    }

    private func clearPrehoverIfNeeded() {
        guard appState.pointerPrehovering else { return }
        withAnimation(NotchAnimation.hoverPrehover) {
            appState.pointerPrehovering = false
        }
        updateVisibility()
    }

    private func fireHoverExpand() {
        hoverExpandTimer = nil
        guard appState.surface == .collapsed else {
            clearPrehoverIfNeeded()
            return
        }
        guard SettingsManager.shared.hoverToExpand, !appState.suppressHoverUntilPointerLeaves else {
            clearPrehoverIfNeeded()
            return
        }
        guard visibleIslandHitRect(forExpanded: false)?.contains(NSEvent.mouseLocation) == true else {
            clearPrehoverIfNeeded()
            return
        }
        guard NotchHoverInteraction.hoverExpansionMayReplace(appState.surface) else {
            clearPrehoverIfNeeded()
            return
        }
        if SettingsManager.shared.smartSuppress && isActiveTerminalForeground() {
            clearPrehoverIfNeeded()
            return
        }

        if UserDefaults.standard.bool(forKey: SettingsKey.hapticOnHover) {
            let intensity = UserDefaults.standard.integer(forKey: SettingsKey.hapticIntensity)
            let performer = NSHapticFeedbackManager.defaultPerformer
            switch intensity {
            case 3:
                performer.perform(.levelChange, performanceTime: .now)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    performer.perform(.levelChange, performanceTime: .now)
                }
            case 2:
                performer.perform(.levelChange, performanceTime: .default)
            default:
                performer.perform(.alignment, performanceTime: .default)
            }
        }

        appState.pointerPrehovering = false
        appState.surface = .sessionList
        appState.cancelCompletionQueue()
        if appState.activeSessionId == nil {
            appState.activeSessionId = appState.sessions.keys.sorted().first
        }
    }

    private func scheduleHoverCollapseIfNeeded(isCompletionCard: Bool) {
        guard hoverCollapseTimer == nil else { return }
        let delay: TimeInterval = isCompletionCard ? 0.08 : max(0.08, NotchHoverInteraction.collapseDelay)
        hoverCollapseTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hoverCollapseTimer = nil
                if RunLoop.main.currentMode == .eventTracking { return }
                guard self.visibleIslandHitRect(forExpanded: true)?.contains(NSEvent.mouseLocation) != true else {
                    return
                }
                switch self.appState.surface {
                case .sessionList:
                    guard SettingsManager.shared.collapseOnMouseLeave else { return }
                    self.appState.surface = .collapsed
                case .completionCard:
                    self.appState.deferCollapseOnMouseLeave = false
                    self.appState.cancelCompletionQueue()
                    self.appState.surface = .collapsed
                default:
                    break
                }
            }
        }
    }

    deinit {
        visibilityTimer?.invalidate()
        autoScreenPoller?.invalidate()
        fullscreenPoller?.invalidate()
        hoverExpandTimer?.invalidate()
        hoverCollapseTimer?.invalidate()
        autoHideAfterCollapseWork?.cancel()
        for observer in settingsObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalMouseMoveMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMouseMoveMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localDragMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
