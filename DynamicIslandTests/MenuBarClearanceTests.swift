import XCTest
@testable import Atoll

/// The screen these use is a 14" MacBook Pro: 1710pt wide, notch 185pt wide and
/// centred, so the menu bar's left strip runs 0...762.5.
final class MenuBarClearanceTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1710, height: 1107)
    private let gap: CGFloat = 8

    private func offset(contentWidth: CGFloat, menusEnd: CGFloat, screen: CGRect? = nil) -> CGFloat {
        MenuBarLayout.clearanceOffset(
            contentWidth: contentWidth,
            screenFrame: screen ?? self.screen,
            menusRightEdge: menusEnd,
            gap: gap
        )
    }

    func testShortMenusLeaveTheNotchCentred() {
        // 300pt of content is centred at 855, so it begins at 705. Menus that
        // end at 606 -- Zen's, measured -- are nowhere near it.
        XCTAssertEqual(offset(contentWidth: 300, menusEnd: 606), 0)
    }

    func testMenusReachingTheContentPushItRight() {
        // Content begins at 705; menus ending at 720 overlap it by 15, plus the
        // 8pt gap.
        XCTAssertEqual(offset(contentWidth: 300, menusEnd: 720), 23)
    }

    func testTheGapAloneIsEnoughToMove() {
        // Menus end exactly where the content begins: no overlap, but they would
        // be flush, so the content still steps aside by the gap.
        XCTAssertEqual(offset(contentWidth: 300, menusEnd: 705), 8)
    }

    // The notification card is as wide as the open notch, and on this screen an
    // app's menus run well past where it begins. The dodge it asked for was
    // nearly its own width -- which does not clear the menus, it just carries
    // the card off the notch and out of the black panel it is drawn in, leaving
    // a full-width black rectangle with a sliver of card at the edge.

    func testContentAsWideAsTheNotchStaysPut() {
        // 626pt of card is centred at 855, so it begins at 542. Xcode's menus
        // end around 1150 -- an overlap bigger than half the card.
        XCTAssertEqual(offset(contentWidth: 626, menusEnd: 1150), 0)
    }

    func testAWideCardStillStepsAsideFromShortMenus() {
        // The cap is on how far, not on how wide: menus ending at 600 ask for
        // 66pt, well inside half the card, and that still happens.
        XCTAssertEqual(offset(contentWidth: 626, menusEnd: 600), 66)
    }

    func testTheCapIsHalfTheContentWidth() {
        // 300pt of content begins at 705; menus ending at 847 ask for exactly
        // 150 -- the last shift that still leaves the content over the centre.
        XCTAssertEqual(offset(contentWidth: 300, menusEnd: 847), 150)
        // One point more and it would clear the centre, so it does not move.
        XCTAssertEqual(offset(contentWidth: 300, menusEnd: 848), 0)
    }

    func testMenusEndingJustShortOfTheGapDoNotMove() {
        XCTAssertEqual(offset(contentWidth: 300, menusEnd: 697), 0)
    }

    func testAWiderActivityIsCoveredSooner() {
        // 500pt of content begins at 605, so the same menus that cleared a
        // 300pt activity now overlap it.
        XCTAssertEqual(offset(contentWidth: 500, menusEnd: 606), 9)
        XCTAssertEqual(offset(contentWidth: 300, menusEnd: 606), 0)
    }

    func testTheShiftStopsAtTheScreenEdge() {
        // Content this wide has only 105pt of room on the right, so a demand for
        // more than that is capped rather than pushing it off screen.
        let wide: CGFloat = 1500
        let headroom = screen.maxX - (screen.midX - wide / 2 + wide)
        XCTAssertEqual(offset(contentWidth: wide, menusEnd: 1000), headroom)
        XCTAssertEqual(headroom, 105)
    }

    func testContentFillingTheScreenNeverMoves() {
        XCTAssertEqual(offset(contentWidth: 1710, menusEnd: 900), 0)
    }

    func testNoContentMeansNoShift() {
        XCTAssertEqual(offset(contentWidth: 0, menusEnd: 900), 0)
    }

    func testAnExternalDisplayIsMeasuredOnItsOwnGeometry() {
        // A screen that does not start at x=0 -- the arithmetic is in global
        // coordinates, so a second display must not be treated as if it did.
        let external = CGRect(x: 1710, y: 0, width: 2560, height: 1440)
        // Centre is 2990, so 300pt of content begins at 2840.
        XCTAssertEqual(offset(contentWidth: 300, menusEnd: 2850, screen: external), 18)
        XCTAssertEqual(offset(contentWidth: 300, menusEnd: 2000, screen: external), 0)
    }
}
