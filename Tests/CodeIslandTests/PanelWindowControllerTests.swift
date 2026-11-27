import AppKit
import XCTest
@testable import CodeIsland

final class PanelWindowControllerTests: XCTestCase {
    func testScreenHopMotionUsesMoreVisibleTiming() {
        let motion = PanelWindowController.screenHopMotion()

        XCTAssertEqual(motion.outgoingOffset, 18)
        XCTAssertEqual(motion.incomingOffset, 30)
        XCTAssertEqual(motion.fadeOutDuration, 0.14, accuracy: 0.001)
        XCTAssertEqual(motion.incomingPauseDuration, 0.06, accuracy: 0.001)
        XCTAssertEqual(motion.fadeInDuration, 0.34, accuracy: 0.001)
    }

    func testScreenHopFramesRetractOldFrameAndDropIntoNewFrame() {
        let oldFrame = NSRect(x: 100, y: 820, width: 420, height: 180)
        let newFrame = NSRect(x: 1800, y: 900, width: 420, height: 180)

        let frames = PanelWindowController.screenHopFrames(
            oldFrame: oldFrame,
            newFrame: newFrame
        )

        XCTAssertEqual(frames.outgoing.origin.x, oldFrame.origin.x)
        XCTAssertEqual(frames.outgoing.origin.y, oldFrame.origin.y + 18)
        XCTAssertEqual(frames.outgoing.size, oldFrame.size)

        XCTAssertEqual(frames.incoming.origin.x, newFrame.origin.x)
        XCTAssertEqual(frames.incoming.origin.y, newFrame.origin.y + 30)
        XCTAssertEqual(frames.incoming.size, newFrame.size)
    }

    @MainActor
    func testSilhouetteStageReprojectsPathsOnBoundsResizeAfterFlight() {
        let host = NSView(frame: .zero)
        let stage = NotchSilhouetteStageView(hostingView: host)
        stage.animationSpeedProvider = { 1.0 }
        stage.frame = NSRect(x: 0, y: 0, width: 640, height: 320)
        stage.layoutSubtreeIfNeeded()

        let collapsed = NotchSilhouetteTarget(
            totalWidth: 260,
            height: 36,
            shoulder: 8,
            bottomRadius: 13,
            offsetX: 0,
            expanded: false,
            usesVibrancy: false,
            strokeOpacity: 0
        )
        let expanded = NotchSilhouetteTarget(
            totalWidth: 580,
            height: 220,
            shoulder: 16,
            bottomRadius: 24,
            offsetX: 0,
            expanded: true,
            usesVibrancy: false,
            strokeOpacity: 0.08
        )

        stage.updateSilhouette(to: collapsed, animated: false)
        stage.updateSilhouette(to: expanded, animated: true)

        // Resize the stage while a flight is installed (or immediately after it):
        // layout() must clear the flight and re-project every shape layer to the new bounds.
        stage.frame = NSRect(x: 0, y: 0, width: 760, height: 480)
        stage.layoutSubtreeIfNeeded()

        XCTAssertFalse(stage.isFlightActive)

        guard let backdropBox = stage.currentBackdropPathBounds,
              let contentMaskBox = stage.currentContentMaskPathBounds else {
            return XCTFail("Expected rendered silhouette paths after bounds resize")
        }

        XCTAssertEqual(backdropBox.maxY, 480, accuracy: 0.5)
        XCTAssertEqual(backdropBox.midX, 380, accuracy: 0.5)
        XCTAssertEqual(backdropBox.width, 580, accuracy: 0.5)
        XCTAssertEqual(backdropBox.height, 220, accuracy: 0.5)

        XCTAssertEqual(contentMaskBox.maxY, 480, accuracy: 0.5)
        XCTAssertEqual(contentMaskBox.midX, 380, accuracy: 0.5)
    }
}
