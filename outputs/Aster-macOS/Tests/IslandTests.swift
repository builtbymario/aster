import CoreGraphics
import SwiftUI
import XCTest
@testable import Aster

final class IslandTests: XCTestCase {
    /// A 14-inch MacBook: 1470 × 956 points with a 179 × 32 notch.
    let macBook = IslandLayout.make(screen: CGRect(x: 0, y: 0, width: 1470, height: 956), safeTop: 32,
                                    left: CGRect(x: 0, y: 924, width: 645.5, height: 32), right: CGRect(x: 824.5, y: 924, width: 645.5, height: 32), menuBar: 32)

    func testTheIslandMatchesTheNotch() {
        XCTAssertTrue(macBook.hasNotch)
        XCTAssertEqual(macBook.notch, CGSize(width: 179, height: 32))
        XCTAssertEqual(macBook.compact, CGSize(width: 179 + 96, height: 32), "The live activity adds an ear on each side")
        XCTAssertEqual(macBook.expanded, CGSize(width: 420, height: 32 + 452))
        XCTAssertEqual(macBook.panel.midX, 735, "The island hangs from the top center")
        XCTAssertEqual(macBook.panel.maxY, 956)
        XCTAssertTrue(macBook.hotZone.contains(CGPoint(x: 735, y: 955)), "Pointing at the notch opens the island")
        XCTAssertTrue(macBook.hotZone.contains(CGPoint(x: 735 + 130, y: 940)), "Its ears count too")
        XCTAssertFalse(macBook.hotZone.contains(CGPoint(x: 735, y: 900)), "Below the menu bar does not")
        XCTAssertFalse(macBook.hotZone.contains(CGPoint(x: 300, y: 950)), "Menus on the left stay usable")
    }

    func testScreensWithoutANotchGetAnIslandAtTheTopCenter() {
        let display = IslandLayout.make(screen: CGRect(x: -1920, y: 0, width: 1920, height: 1080), safeTop: 0, left: nil, right: nil, menuBar: 25)
        XCTAssertFalse(display.hasNotch)
        XCTAssertEqual(display.notch, CGSize(width: 180, height: 25))
        XCTAssertEqual(display.panel.midX, -960); XCTAssertEqual(display.panel.maxY, 1080)
        let hiddenMenuBar = IslandLayout.make(screen: CGRect(x: 0, y: 0, width: 1280, height: 480), safeTop: 0, left: nil, right: nil, menuBar: 0)
        XCTAssertEqual(hiddenMenuBar.notch.height, 24, "An auto-hidden menu bar still leaves a reachable island")
        XCTAssertEqual(hiddenMenuBar.expanded.height, 440, "The open island never runs off a short screen")
    }

    func testTheShapeIsFlatOnTopAndStaysInsideItsFrame() {
        for (top, bottom) in [(6.0, 13.0), (14.0, 30.0), (40.0, 400.0)] {
            let rect = CGRect(x: 0, y: 0, width: 275, height: 32)
            let path = IslandShape(topRadius: top, bottomRadius: bottom).path(in: rect)
            XCTAssertTrue(rect.insetBy(dx: -0.5, dy: -0.5).contains(path.boundingRect), "Radii are clamped to the frame")
            XCTAssertTrue(path.contains(CGPoint(x: rect.midX, y: 1)), "The top edge is flat against the screen edge")
            XCTAssertTrue(path.contains(CGPoint(x: rect.midX, y: rect.maxY - 1)))
        }
    }
}
