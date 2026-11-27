import AppKit
import QuartzCore
import SwiftUI

/// Pure-MIT Core Animation silhouette target for FlowIsland's notch panel.
///
/// Driving the outer silhouette, backdrop, vibrancy mask, and content clip via
/// GPU `CAKeyframeAnimation(keyPath: "path")` completely decouples 120 Hz
/// ProMotion expand/collapse motion from SwiftUI layout and the main run loop.
struct NotchSilhouetteTarget: Equatable {
    /// Total rendered width including both top concave shoulders (`bodyWidth + shoulder * 2`).
    var totalWidth: CGFloat
    /// Total rendered height anchored at the top edge of the display.
    var height: CGFloat
    /// Concave top shoulder flare radius on each side.
    var shoulder: CGFloat
    /// Continuous bottom corner radius.
    var bottomRadius: CGFloat
    /// Horizontal offset from display center (0 when centered on the hardware notch).
    var offsetX: CGFloat
    /// Whether the panel is in an expanded state.
    var expanded: Bool
    /// Whether macOS vibrancy glass surface should show when expanded.
    var usesVibrancy: Bool
    /// Subtle edge stroke opacity (0 when collapsed, ~0.08–0.14 when expanded).
    var strokeOpacity: Float
}

enum NotchSilhouetteMotionKind: Equatable {
    case micro
    case growing
    case shrinking
}

struct NotchSilhouetteTimingProfile: Equatable {
    let widthDuration: TimeInterval
    let widthBounce: Double
    let heightDuration: TimeInterval
    let heightBounce: Double
    let sampleDuration: TimeInterval
}

/// Scales Core Animation GPU silhouette spring and collapse-unmount durations
/// by `NotchAnimationSpeed` (`0.5×–2.0×`) so Settings → Animation Speed drives
/// the live 120 Hz stage as well as SwiftUI fallbacks.
enum NotchSilhouetteTiming {
    static let baseCollapseSampleDuration: TimeInterval = 0.30
    static let collapseUnmountMargin: TimeInterval = 0.06

    static func profile(for kind: NotchSilhouetteMotionKind, speed rawSpeed: Double) -> NotchSilhouetteTimingProfile {
        let speed = NotchAnimationSpeed.clamped(rawSpeed)
        switch kind {
        case .micro:
            return NotchSilhouetteTimingProfile(
                widthDuration: 0.16 / speed,
                widthBounce: 0.06,
                heightDuration: 0.14 / speed,
                heightBounce: 0.0,
                sampleDuration: 0.22 / speed
            )
        case .growing:
            return NotchSilhouetteTimingProfile(
                widthDuration: 0.38 / speed,
                widthBounce: 0.22,
                heightDuration: 0.32 / speed,
                heightBounce: 0.18,
                sampleDuration: 0.52 / speed
            )
        case .shrinking:
            return NotchSilhouetteTimingProfile(
                widthDuration: 0.25 / speed,
                widthBounce: 0.0,
                heightDuration: 0.20 / speed,
                heightBounce: 0.0,
                sampleDuration: baseCollapseSampleDuration / speed
            )
        }
    }

    static func collapseUnmountDelay(speed rawSpeed: Double) -> TimeInterval {
        let speed = NotchAnimationSpeed.clamped(rawSpeed)
        return baseCollapseSampleDuration / speed + collapseUnmountMargin
    }
}

/// Analytical damped harmonic oscillator used to sample 120 Hz spring keyframes
/// directly for `CAKeyframeAnimation(keyPath: "path")` without touching SwiftUI.
private struct AnalyticSpring {
    let duration: TimeInterval
    let bounce: Double

    /// Normalized progress from 0 toward 1 at `time` seconds.
    func value(at time: TimeInterval) -> CGFloat {
        guard time > 0 else { return 0 }
        let omega = (2.0 * Double.pi) / max(0.05, duration)
        let zeta = max(0.05, 1.0 - bounce)
        if zeta >= 1.0 {
            let decay = exp(-omega * time)
            return CGFloat(1.0 - decay * (1.0 + omega * time))
        }
        let dampedOmega = omega * sqrt(max(0.0001, 1.0 - zeta * zeta))
        let decay = exp(-zeta * omega * time)
        let cosTerm = cos(dampedOmega * time)
        let sinTerm = (zeta * omega / dampedOmega) * sin(dampedOmega * time)
        return CGFloat(1.0 - decay * (cosTerm + sinTerm))
    }

    /// Approximate overshoot fraction past target for clamping within panel bounds.
    var overshootFraction: Double {
        guard bounce > 0 else { return 0 }
        let zeta = max(0.05, 1.0 - bounce)
        guard zeta < 1.0 else { return 0 }
        return exp(-Double.pi * zeta / sqrt(1.0 - zeta * zeta))
    }

    func clamped(travel: CGFloat, maxOvershoot: CGFloat) -> AnalyticSpring {
        guard bounce > 0, travel > 0 else { return self }
        guard Double(travel) * overshootFraction > Double(maxOvershoot) else { return self }
        let ratio = max(0.001, Double(maxOvershoot / travel))
        let lnR = log(ratio)
        let zeta = -lnR / sqrt(Double.pi * Double.pi + lnR * lnR)
        return AnalyticSpring(duration: duration, bounce: max(0, 1.0 - zeta))
    }
}

/// Captures an in-flight GPU path transition so reversing or retargeting mid-flight
/// starts from the exact currently visible geometry with zero visual jump.
private struct ActiveSilhouetteFlight {
    let start: NotchSilhouetteTarget
    let end: NotchSilhouetteTarget
    let beginTime: CFTimeInterval
    let totalDuration: TimeInterval
    let widthSpring: AnalyticSpring
    let heightSpring: AnalyticSpring

    func interpolated(at now: CFTimeInterval) -> NotchSilhouetteTarget {
        let elapsed = max(0, now - beginTime)
        if elapsed >= totalDuration { return end }
        let pw = widthSpring.value(at: elapsed)
        let ph = heightSpring.value(at: elapsed)
        let p = max(0, min(1, (pw + ph) * 0.5))
        return NotchSilhouetteTarget(
            totalWidth: start.totalWidth + (end.totalWidth - start.totalWidth) * pw,
            height: max(20, start.height + (end.height - start.height) * ph),
            shoulder: max(0, start.shoulder + (end.shoulder - start.shoulder) * p),
            bottomRadius: max(0, start.bottomRadius + (end.bottomRadius - start.bottomRadius) * p),
            offsetX: start.offsetX + (end.offsetX - start.offsetX) * pw,
            expanded: end.expanded,
            usesVibrancy: end.usesVibrancy,
            strokeOpacity: end.strokeOpacity
        )
    }
}

/// Non-interactive overlay view that renders the subtle edge stroke above the
/// hosted SwiftUI content without intercepting clicks or hover events.
private final class PassthroughStrokeView: NSView {
    let shapeLayer = CAShapeLayer()
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        shapeLayer.fillColor = nil
        shapeLayer.lineWidth = 0.75
        shapeLayer.strokeColor = NSColor.white.withAlphaComponent(0.14).cgColor
        shapeLayer.opacity = 0
        layer?.addSublayer(shapeLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.frame = bounds
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Non-interactive backdrop view holding the solid black `CAShapeLayer` fill.
private final class PassthroughBackdropView: NSView {
    let shapeLayer = CAShapeLayer()
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        shapeLayer.fillColor = NSColor.black.cgColor
        layer?.addSublayer(shapeLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.frame = bounds
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Top-level `NSView` stage for `PanelWindowController` that composites:
/// 1. Pure black GPU `CAShapeLayer` backdrop
/// 2. Optional macOS `NSVisualEffectView` vibrancy backdrop (masked by the same GPU silhouette)
/// 3. Fixed-frame `NotchHostingView` SwiftUI content (masked by the same GPU silhouette)
/// 4. Subtle top edge stroke overlay (`CAShapeLayer`)
///
/// Uses standard non-flipped AppKit coordinates (`y = bounds.height` at the top
/// screen bezel, growing downward toward `y = 0`) across ALL four subviews and
/// `CAShapeLayer`s so backdrop, vibrancy mask, content mask, and stroke share
/// one identical `CGPath` with zero flip mismatch.
/// Plain non-flipped container view wrapping `NSHostingView` so `contentMaskLayer`
/// always operates in standard AppKit non-flipped layer coordinates — immune to
/// `NSHostingView`'s internal `layer.isGeometryFlipped` quirk on macOS 26/27.
private final class ContentMaskContainerView: NSView {
    override var isOpaque: Bool { false }
}

final class NotchSilhouetteStageView: NSView {
    private let backdropView = PassthroughBackdropView(frame: .zero)
    private let vibrancyView = NSVisualEffectView(frame: .zero)
    private let vibrancyTintLayer = CAGradientLayer()
    private let vibrancyMaskLayer = CAShapeLayer()
    private let contentContainer = ContentMaskContainerView(frame: .zero)
    private let contentMaskLayer = CAShapeLayer()
    private let strokeView = PassthroughStrokeView(frame: .zero)
    let hostingView: NSView

    private var pointerTrackingArea: NSTrackingArea?
    private var currentTarget: NotchSilhouetteTarget?
    private var activeFlight: ActiveSilhouetteFlight?
    private var lastRenderedBounds: CGRect = .zero
    private var vibrancyHideWork: DispatchWorkItem?

    /// Speed multiplier provider (defaults to `SettingsManager.shared.notchAnimationSpeed`).
    var animationSpeedProvider: @MainActor () -> Double = { SettingsManager.shared.notchAnimationSpeed }

    /// Fired on `.mouseEntered`, `.mouseMoved`, `.mouseExited` even when the
    /// panel is not the key window (`.activeAlways`).
    var onPointerActivity: (() -> Void)?

    /// Exposed for unit testing bounds-resize re-projection and flight expiry.
    var currentBackdropPathBounds: CGRect? { backdropView.shapeLayer.path?.boundingBoxOfPath }
    var currentContentMaskPathBounds: CGRect? { contentMaskLayer.path?.boundingBoxOfPath }
    var isFlightActive: Bool { activeFlight != nil }

    override var isOpaque: Bool { false }

    init(hostingView: NSView) {
        self.hostingView = hostingView
        super.init(frame: .zero)
        wantsLayer = true
        autoresizesSubviews = false

        // 1. Solid black backdrop
        addSubview(backdropView)

        // 2. macOS dark vibrancy glass backdrop (shown only when vibrancy mode + expanded)
        vibrancyView.material = .hudWindow
        vibrancyView.blendingMode = .behindWindow
        vibrancyView.state = .active
        vibrancyView.appearance = NSAppearance(named: .darkAqua)
        vibrancyView.wantsLayer = true
        vibrancyView.isHidden = true
        vibrancyTintLayer.colors = [
            NSColor.black.withAlphaComponent(0.90).cgColor,
            NSColor.black.withAlphaComponent(0.54).cgColor,
            NSColor.black.withAlphaComponent(0.62).cgColor,
        ]
        vibrancyTintLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        vibrancyTintLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        vibrancyView.layer?.addSublayer(vibrancyTintLayer)
        vibrancyMaskLayer.fillColor = NSColor.black.cgColor
        vibrancyView.layer?.mask = vibrancyMaskLayer
        addSubview(vibrancyView)

        // 3. Hosted SwiftUI content wrapped in a plain non-flipped container
        //    masked by the exact same GPU silhouette as backdrop & vibrancy.
        contentContainer.wantsLayer = true
        contentContainer.autoresizesSubviews = false
        hostingView.wantsLayer = true
        contentContainer.addSubview(hostingView)
        contentMaskLayer.fillColor = NSColor.black.cgColor
        contentContainer.layer?.mask = contentMaskLayer
        addSubview(contentContainer)

        // 4. Crisp border highlight on top
        addSubview(strokeView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdropView.frame = bounds
        vibrancyView.frame = bounds
        vibrancyTintLayer.frame = bounds
        vibrancyMaskLayer.frame = bounds
        contentContainer.frame = bounds
        hostingView.frame = contentContainer.bounds
        contentMaskLayer.frame = contentContainer.bounds
        strokeView.frame = bounds
        if let flight = activeFlight, CACurrentMediaTime() >= flight.beginTime + flight.totalDuration {
            activeFlight = nil
        }
        if let target = currentTarget, activeFlight == nil || bounds != lastRenderedBounds {
            activeFlight = nil
            removePathAnimations()
            applyStaticTarget(target)
        }
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = pointerTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        pointerTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onPointerActivity?()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onPointerActivity?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPointerActivity?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let target = currentTarget else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        let visual = activeFlight?.interpolated(at: CACurrentMediaTime()) ?? target
        let hitRect = CGRect(
            x: bounds.midX + visual.offsetX - visual.totalWidth / 2 - 4,
            y: bounds.height - visual.height - 6,
            width: visual.totalWidth + 8,
            height: visual.height + 6
        )
        guard hitRect.contains(local) else { return nil }
        return super.hitTest(point)
    }

    /// Updates the GPU silhouette to `target`, animating at native 120 Hz via
    /// `CAKeyframeAnimation(keyPath: "path")` when `animated` is true.
    func updateSilhouette(to target: NotchSilhouetteTarget, animated: Bool) {
        if let existing = currentTarget, existing == target { return }

        let now = CACurrentMediaTime()
        let previous = activeFlight?.interpolated(at: now) ?? currentTarget
        currentTarget = target

        let shouldAnimate = animated
            && previous != nil
            && bounds.width > 1
            && bounds.height > 1
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        guard shouldAnimate, let start = previous else {
            activeFlight = nil
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            removePathAnimations()
            applyStaticTarget(target)
            CATransaction.commit()
            return
        }

        let heightDelta = target.height - start.height
        let widthDelta = target.totalWidth - start.totalWidth
        let isGrowing = heightDelta > 4 || widthDelta > 30
        let isShrinking = heightDelta < -4 || widthDelta < -30
        let isMicro = !isGrowing && !isShrinking

        let speed = NotchAnimationSpeed.clamped(animationSpeedProvider())
        let motionKind: NotchSilhouetteMotionKind = isMicro ? .micro : (isGrowing ? .growing : .shrinking)
        let timing = NotchSilhouetteTiming.profile(for: motionKind, speed: speed)
        let rawWidthSpring = AnalyticSpring(duration: timing.widthDuration, bounce: timing.widthBounce)
        let rawHeightSpring = AnalyticSpring(duration: timing.heightDuration, bounce: timing.heightBounce)
        let sampleDuration = timing.sampleDuration

        let maxWidthOvershoot = max(0, min(12, (bounds.width - target.totalWidth) * 0.45))
        let maxHeightOvershoot = max(0, min(12, bounds.height - target.height))
        let widthSpring = rawWidthSpring.clamped(
            travel: abs(widthDelta),
            maxOvershoot: maxWidthOvershoot
        )
        let heightSpring = rawHeightSpring.clamped(
            travel: abs(heightDelta),
            maxOvershoot: maxHeightOvershoot
        )

        let flight = ActiveSilhouetteFlight(
            start: start,
            end: target,
            beginTime: now,
            totalDuration: sampleDuration,
            widthSpring: widthSpring,
            heightSpring: heightSpring
        )
        activeFlight = flight
        lastRenderedBounds = bounds

        // Sample 90 keyframes + explicit 120 Hz ProMotion preferredFrameRateRange
        // so WindowServer runs the path morph at native 120 fps instead of 60 fps.
        let steps = 90
        var paths: [CGPath] = []
        var keyTimes: [NSNumber] = []
        paths.reserveCapacity(steps + 1)
        keyTimes.reserveCapacity(steps + 1)

        for i in 0...steps {
            let fraction = Double(i) / Double(steps)
            let sampleTime = now + sampleDuration * fraction
            let state = (i == steps) ? target : flight.interpolated(at: sampleTime)
            paths.append(Self.silhouettePath(for: state, in: bounds, flipped: false))
            keyTimes.append(NSNumber(value: fraction))
        }

        let proMotionRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)

        let pathAnim = CAKeyframeAnimation(keyPath: "path")
        pathAnim.values = paths
        pathAnim.keyTimes = keyTimes
        pathAnim.calculationMode = .linear
        pathAnim.duration = sampleDuration
        pathAnim.preferredFrameRateRange = proMotionRange

        let finalPath = paths.last ?? Self.silhouettePath(for: target, in: bounds, flipped: false)

        vibrancyHideWork?.cancel()
        vibrancyHideWork = nil

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let showGlass = target.usesVibrancy && target.expanded
        // Keep black backdrop underneath during glass fade so collapse never pops
        backdropView.shapeLayer.opacity = 1
        if showGlass {
            vibrancyView.isHidden = false
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = vibrancyView.layer?.presentation()?.opacity ?? vibrancyView.layer?.opacity ?? 0
            fadeIn.toValue = Float(1.0)
            fadeIn.duration = 0.16 / speed
            fadeIn.preferredFrameRateRange = proMotionRange
            vibrancyView.layer?.opacity = 1.0
            vibrancyView.layer?.add(fadeIn, forKey: "vibrancyOpacity")
        } else if !vibrancyView.isHidden {
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = vibrancyView.layer?.presentation()?.opacity ?? vibrancyView.layer?.opacity ?? 1
            fadeOut.toValue = Float(0.0)
            fadeOut.duration = 0.14 / speed
            fadeOut.preferredFrameRateRange = proMotionRange
            vibrancyView.layer?.opacity = 0.0
            vibrancyView.layer?.add(fadeOut, forKey: "vibrancyOpacity")
            let hideWork = DispatchWorkItem { [weak self] in
                guard let self, !(self.currentTarget?.usesVibrancy == true && self.currentTarget?.expanded == true) else { return }
                self.vibrancyView.isHidden = true
            }
            vibrancyHideWork = hideWork
            DispatchQueue.main.asyncAfter(deadline: .now() + sampleDuration + 0.04, execute: hideWork)
        }

        // Set model-layer final paths BEFORE installing the keyframe animation
        backdropView.shapeLayer.path = finalPath
        vibrancyMaskLayer.path = finalPath
        contentMaskLayer.path = finalPath
        strokeView.shapeLayer.path = finalPath

        backdropView.shapeLayer.add(pathAnim, forKey: "notchSilhouettePath")
        if !vibrancyView.isHidden {
            vibrancyMaskLayer.add(pathAnim, forKey: "notchSilhouettePath")
        }
        contentMaskLayer.add(pathAnim, forKey: "notchSilhouettePath")
        strokeView.shapeLayer.add(pathAnim, forKey: "notchSilhouettePath")

        let strokeOpacityAnim = CABasicAnimation(keyPath: "opacity")
        strokeOpacityAnim.fromValue = strokeView.shapeLayer.presentation()?.opacity ?? strokeView.shapeLayer.opacity
        strokeOpacityAnim.toValue = target.strokeOpacity
        strokeOpacityAnim.duration = (isGrowing ? 0.20 : 0.12) / speed
        strokeOpacityAnim.preferredFrameRateRange = proMotionRange
        strokeView.shapeLayer.opacity = target.strokeOpacity
        strokeView.shapeLayer.add(strokeOpacityAnim, forKey: "notchStrokeOpacity")
        CATransaction.commit()
        CATransaction.flush()
    }

    private func removePathAnimations() {
        vibrancyHideWork?.cancel()
        vibrancyHideWork = nil
        backdropView.shapeLayer.removeAnimation(forKey: "notchSilhouettePath")
        vibrancyMaskLayer.removeAnimation(forKey: "notchSilhouettePath")
        vibrancyView.layer?.removeAnimation(forKey: "vibrancyOpacity")
        contentMaskLayer.removeAnimation(forKey: "notchSilhouettePath")
        strokeView.shapeLayer.removeAnimation(forKey: "notchSilhouettePath")
        strokeView.shapeLayer.removeAnimation(forKey: "notchStrokeOpacity")
    }

    private func applyStaticTarget(_ target: NotchSilhouetteTarget) {
        let path = Self.silhouettePath(for: target, in: bounds, flipped: false)
        lastRenderedBounds = bounds
        let showGlass = target.usesVibrancy && target.expanded
        vibrancyView.isHidden = !showGlass
        vibrancyView.layer?.opacity = showGlass ? 1.0 : 0.0
        backdropView.shapeLayer.opacity = 1
        backdropView.shapeLayer.path = path
        vibrancyMaskLayer.path = path
        contentMaskLayer.path = path
        strokeView.shapeLayer.path = path
        strokeView.shapeLayer.opacity = target.strokeOpacity
    }

    /// Continuous-curvature concave-shoulder notch silhouette path anchored at
    /// the top bezel in either flipped (`y = 0` at top, e.g. `NSHostingView`) or
    /// non-flipped (`y = bounds.height` at top, e.g. standard `NSView`) coords.
    static func silhouettePath(for target: NotchSilhouetteTarget, in bounds: CGRect, flipped: Bool = false) -> CGPath {
        let width = max(24, target.totalWidth)
        let height = max(20, target.height)
        let ext = min(max(0, target.shoulder), width / 6, height / 2)
        let topY: CGFloat = flipped ? 0 : bounds.height
        let dir: CGFloat = flipped ? 1 : -1
        let bottomY = topY + dir * height
        let minX = bounds.midX + target.offsetX - width / 2
        let maxX = minX + width
        let leftWall = minX + ext
        let rightWall = maxX - ext
        let bodyWidth = max(0, rightWall - leftWall)
        let br = min(max(0, target.bottomRadius), bodyWidth / 4, height / 2)
        let k: CGFloat = 0.62

        let p = CGMutablePath()
        // Top bezel edge (left -> right)
        p.move(to: CGPoint(x: minX, y: topY))
        p.addLine(to: CGPoint(x: maxX, y: topY))
        // Right concave top shoulder curving away from top bezel into right wall
        p.addCurve(
            to: CGPoint(x: rightWall, y: topY + dir * ext),
            control1: CGPoint(x: rightWall + ext * 0.42, y: topY),
            control2: CGPoint(x: rightWall, y: topY + dir * ext * 0.42)
        )
        // Right straight wall toward bottom edge
        p.addLine(to: CGPoint(x: rightWall, y: bottomY - dir * br))
        // Bottom-right superellipse corner
        p.addCurve(
            to: CGPoint(x: rightWall - br, y: bottomY),
            control1: CGPoint(x: rightWall, y: bottomY - dir * br * (1 - k)),
            control2: CGPoint(x: rightWall - br * (1 - k), y: bottomY)
        )
        // Bottom edge (right -> left)
        p.addLine(to: CGPoint(x: leftWall + br, y: bottomY))
        // Bottom-left superellipse corner
        p.addCurve(
            to: CGPoint(x: leftWall, y: bottomY - dir * br),
            control1: CGPoint(x: leftWall + br * (1 - k), y: bottomY),
            control2: CGPoint(x: leftWall, y: bottomY - dir * br * (1 - k))
        )
        // Left straight wall back toward top bezel
        p.addLine(to: CGPoint(x: leftWall, y: topY + dir * ext))
        // Left concave top shoulder curving back to top bezel
        p.addCurve(
            to: CGPoint(x: minX, y: topY),
            control1: CGPoint(x: leftWall, y: topY + dir * ext * 0.42),
            control2: CGPoint(x: leftWall - ext * 0.42, y: topY)
        )
        p.closeSubpath()
        return p
    }
}
