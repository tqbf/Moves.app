import XCTest
@testable import Moves

/// Cover the sanitizer that strips trailing ellipsis/dot runs from row
/// subtitle source strings. The render-time fix exists so SwiftUI's
/// `.truncationMode(.tail)` isn't fighting literal `...` in user-typed
/// breadcrumbs / item titles.
final class RowSubtitleTests: XCTestCase {

  func testStripsTriplePeriod() {
    XCTAssertEqual(
      RowSubtitle.sanitize("Write an mOS blog post, or something about meta-apps..."),
      "Write an mOS blog post, or something about meta-apps"
    )
  }

  func testStripsHorizontalEllipsis() {
    XCTAssertEqual(
      RowSubtitle.sanitize("Pick up dowels\u{2026}"),
      "Pick up dowels"
    )
  }

  func testStripsMixedDotsAndEllipsis() {
    XCTAssertEqual(
      RowSubtitle.sanitize("loose end..\u{2026}."),
      "loose end"
    )
  }

  func testStripsTrailingWhitespaceAroundDots() {
    XCTAssertEqual(
      RowSubtitle.sanitize("done...   "),
      "done"
    )
  }

  func testLeavesInteriorDotsAlone() {
    XCTAssertEqual(
      RowSubtitle.sanitize("see e.g. notes.md for context"),
      "see e.g. notes.md for context"
    )
  }

  func testEmptyAndAllDotsCollapseToEmpty() {
    XCTAssertEqual(RowSubtitle.sanitize(""), "")
    XCTAssertEqual(RowSubtitle.sanitize("..."), "")
    XCTAssertEqual(RowSubtitle.sanitize("\u{2026}"), "")
  }
}
