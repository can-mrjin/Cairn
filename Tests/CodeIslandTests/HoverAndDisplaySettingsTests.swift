import XCTest
@testable import CodeIsland
import CodeIslandCore

final class HoverAndDisplaySettingsTests: XCTestCase {
    // MARK: - Hover expand delay

    func testDefaultHoverDelayIsUnchanged() {
        XCTAssertEqual(SettingsDefaults.hoverExpandDelay, 0.15)
        XCTAssertEqual(NotchHoverInteraction.expandDelay(forSetting: SettingsDefaults.hoverExpandDelay), 0.15)
    }

    func testHoverDelayIsClampedIntoTheOfferedRange() {
        XCTAssertEqual(NotchHoverInteraction.expandDelay(forSetting: 0.05), 0.05)
        XCTAssertEqual(NotchHoverInteraction.expandDelay(forSetting: 0.1), 0.1)
        XCTAssertEqual(NotchHoverInteraction.expandDelay(forSetting: 0.75), 0.75)
        XCTAssertEqual(NotchHoverInteraction.expandDelay(forSetting: 1.0), 1.0)
        // A hand-written or zeroed preference must never produce an instant or
        // negative timer.
        XCTAssertEqual(NotchHoverInteraction.expandDelay(forSetting: 0), 0.05)
        XCTAssertEqual(NotchHoverInteraction.expandDelay(forSetting: -3), 0.05)
        XCTAssertEqual(NotchHoverInteraction.expandDelay(forSetting: 12), 1.0)
    }

    func testNonFiniteHoverDelayFallsBackToTheDefault() {
        XCTAssertEqual(NotchHoverInteraction.expandDelay(forSetting: .nan), NotchHoverInteraction.expandDelay)
        XCTAssertEqual(NotchHoverInteraction.expandDelay(forSetting: .infinity), NotchHoverInteraction.expandDelay)
    }

    func testHoverDelayRangeMatchesTheRequestedBounds() {
        XCTAssertEqual(NotchHoverInteraction.expandDelayRange.lowerBound, 0.05)
        XCTAssertEqual(NotchHoverInteraction.expandDelayRange.upperBound, 1.0)
    }

    /// An approval or question card that opened while the hover delay was
    /// running must not be swapped out for the session list when it elapses.
    func testElapsedHoverDelayNeverReplacesAPendingCard() {
        XCTAssertFalse(NotchHoverInteraction.hoverExpansionMayReplace(.approvalCard(sessionId: "s")))
        XCTAssertFalse(NotchHoverInteraction.hoverExpansionMayReplace(.questionCard(sessionId: "s")))
        XCTAssertTrue(NotchHoverInteraction.hoverExpansionMayReplace(.collapsed))
        XCTAssertTrue(NotchHoverInteraction.hoverExpansionMayReplace(.sessionList))
        XCTAssertTrue(NotchHoverInteraction.hoverExpansionMayReplace(.completionCard(sessionId: "s")))
    }

    // MARK: - Content font size

    func testContentFontSizeGoesUpTo16pt() {
        XCTAssertEqual(ContentFontSize.choices.first, 10)
        XCTAssertEqual(ContentFontSize.choices.last, 16)
        XCTAssertEqual(ContentFontSize.choices, Array(10...16), "every step is selectable")
        XCTAssertTrue(ContentFontSize.choices.contains(SettingsDefaults.contentFontSize))
    }

    // MARK: - Collapsed width scale slider minimum

    func testNotchWidthScaleSliderMinHonorsNotchPresence() {
        XCTAssertEqual(NotchWidthScale.sliderMin(hasNotch: true), 100)
        XCTAssertEqual(NotchWidthScale.sliderMin(hasNotch: false), 50)
        XCTAssertLessThan(NotchWidthScale.sliderMin(hasNotch: false), NotchWidthScale.sliderMin(hasNotch: true))
        XCTAssertLessThanOrEqual(NotchWidthScale.sliderMin(hasNotch: true), NotchWidthScale.max)
    }

    // MARK: - GPU silhouette animation speed scaling

    func testSilhouetteTimingScalesDurationsByAnimationSpeed() {
        let normalGrow = NotchSilhouetteTiming.profile(for: .growing, speed: 1.0)
        let fastGrow = NotchSilhouetteTiming.profile(for: .growing, speed: 2.0)
        let slowGrow = NotchSilhouetteTiming.profile(for: .growing, speed: 0.5)

        XCTAssertEqual(normalGrow.widthDuration, 0.30, accuracy: 0.0001)
        XCTAssertEqual(normalGrow.heightDuration, 0.34, accuracy: 0.0001)
        XCTAssertEqual(normalGrow.sampleDuration, 0.44, accuracy: 0.0001)
        XCTAssertLessThan(normalGrow.widthDuration, normalGrow.heightDuration, "width should lead height to avoid horizontal text clipping while opening")

        XCTAssertEqual(fastGrow.widthDuration, normalGrow.widthDuration / 2.0, accuracy: 0.0001)
        XCTAssertEqual(fastGrow.heightDuration, normalGrow.heightDuration / 2.0, accuracy: 0.0001)
        XCTAssertEqual(fastGrow.sampleDuration, normalGrow.sampleDuration / 2.0, accuracy: 0.0001)

        XCTAssertEqual(slowGrow.widthDuration, normalGrow.widthDuration * 2.0, accuracy: 0.0001)
        XCTAssertEqual(slowGrow.heightDuration, normalGrow.heightDuration * 2.0, accuracy: 0.0001)
        XCTAssertEqual(slowGrow.sampleDuration, normalGrow.sampleDuration * 2.0, accuracy: 0.0001)

        let shrinkFast = NotchSilhouetteTiming.profile(for: .shrinking, speed: 2.0)
        XCTAssertEqual(shrinkFast.sampleDuration, 0.15, accuracy: 0.0001)

        let microSlow = NotchSilhouetteTiming.profile(for: .micro, speed: 0.5)
        XCTAssertEqual(microSlow.sampleDuration, 0.44, accuracy: 0.0001)
    }

    func testSilhouetteTimingClampsOutOfRangeAndNonFiniteSpeeds() {
        XCTAssertEqual(
            NotchSilhouetteTiming.profile(for: .shrinking, speed: 0.1),
            NotchSilhouetteTiming.profile(for: .shrinking, speed: NotchAnimationSpeed.minimum)
        )
        XCTAssertEqual(
            NotchSilhouetteTiming.profile(for: .shrinking, speed: 10.0),
            NotchSilhouetteTiming.profile(for: .shrinking, speed: NotchAnimationSpeed.maximum)
        )
        XCTAssertEqual(
            NotchSilhouetteTiming.profile(for: .shrinking, speed: .nan),
            NotchSilhouetteTiming.profile(for: .shrinking, speed: NotchAnimationSpeed.normal)
        )
    }

    func testCollapseUnmountDelayScalesWithAnimationSpeed() {
        XCTAssertEqual(NotchSilhouetteTiming.collapseUnmountDelay(speed: 1.0), 0.36, accuracy: 0.0001)
        XCTAssertEqual(NotchSilhouetteTiming.collapseUnmountDelay(speed: 2.0), 0.21, accuracy: 0.0001)
        XCTAssertEqual(NotchSilhouetteTiming.collapseUnmountDelay(speed: 0.5), 0.66, accuracy: 0.0001)
    }
}
