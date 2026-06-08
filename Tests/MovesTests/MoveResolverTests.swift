import XCTest
@testable import Moves

final class MoveResolverTests: XCTestCase {

  func testBreadcrumbWinsWhenPresent() {
    let thread = Thread(
      title: "Python refresh",
      kind: .regimented,
      breadcrumb: "GET nil bulk string"
    )
    let segment = Segment(
      threadId: thread.id,
      title: "Day 08",
      orderIndex: 1,
      builtInMove: "Implement async loop",
      status: .active
    )
    let resolved = MoveResolver.resolve(thread: thread, segments: [segment], openItems: [])
    XCTAssertEqual(resolved?.text, "GET nil bulk string")
    XCTAssertEqual(resolved?.source, .breadcrumb)
  }

  func testActiveSegmentWinsOverPending() {
    let thread = Thread(title: "Calc", kind: .regimented)
    let active = Segment(
      threadId: thread.id,
      title: "Lesson 8",
      orderIndex: 8,
      builtInMove: "Active move",
      status: .active
    )
    let pending = Segment(
      threadId: thread.id,
      title: "Lesson 5",
      orderIndex: 5,
      builtInMove: "Earlier move",
      status: .pending
    )
    let resolved = MoveResolver.resolve(thread: thread, segments: [pending, active], openItems: [])
    XCTAssertEqual(resolved?.text, "Active move")
  }

  func testFallsBackToFirstPendingByOrderIndex() {
    let thread = Thread(title: "Writing", kind: .regimented)
    let second = Segment(
      threadId: thread.id,
      title: "Pass 2",
      orderIndex: 2,
      builtInMove: "Second move",
      status: .pending
    )
    let first = Segment(
      threadId: thread.id,
      title: "Pass 1",
      orderIndex: 1,
      builtInMove: "First move",
      status: .pending
    )
    let resolved = MoveResolver.resolve(thread: thread, segments: [second, first], openItems: [])
    XCTAssertEqual(resolved?.text, "First move")
  }

  func testFallsBackToOpenItem() {
    let thread = Thread(title: "Picture frames")
    let item = Item(threadId: thread.id, title: "Sand half-lap", status: .open)
    let resolved = MoveResolver.resolve(thread: thread, segments: [], openItems: [item])
    XCTAssertEqual(resolved?.text, "Sand half-lap")
    XCTAssertEqual(resolved?.source, .openItem(itemId: item.id))
  }

  func testReturnsNilWhenNoReentryPoint() {
    let thread = Thread(title: "Empty thread")
    XCTAssertNil(MoveResolver.resolve(thread: thread, segments: [], openItems: []))
  }

  func testNormalThreadIgnoresSegments() {
    // A normal (non-regimented) thread with segments shouldn't pull from
    // them — segments only matter for regimented threads.
    let thread = Thread(title: "Normal", kind: .normal)
    let segment = Segment(
      threadId: thread.id,
      title: "Stray",
      orderIndex: 1,
      builtInMove: "Should not be used",
      status: .pending
    )
    XCTAssertNil(MoveResolver.resolve(thread: thread, segments: [segment], openItems: []))
  }

  /// Phase-5 §11 fall-through: a regimented thread with no breadcrumb and
  /// only a pending segment should still surface a move (the segment's
  /// built-in move). Covers the path that the new SegmentsPanel + Markdown
  /// import rely on for first-render-after-import.
  func testRegimentedThreadNoBreadcrumbFallsThroughToPendingSegmentBuiltInMove() {
    let thread = Thread(title: "Imported", kind: .regimented, breadcrumb: "")
    let pending = Segment(
      threadId: thread.id,
      title: "Day 01",
      orderIndex: 0,
      builtInMove: "Write a tiny parser",
      status: .pending
    )
    let resolved = MoveResolver.resolve(thread: thread, segments: [pending], openItems: [])
    XCTAssertEqual(resolved?.text, "Write a tiny parser")
    if case let .segment(_, title) = resolved?.source {
      XCTAssertEqual(title, "Day 01")
    } else {
      XCTFail("Expected segment source, got \(String(describing: resolved?.source))")
    }
  }

  /// Phase-5 §11 fall-through: a regimented thread with no breadcrumb and
  /// only an active segment should surface the active segment's move.
  /// Complements the test above (active vs first-pending pathway).
  func testRegimentedThreadNoBreadcrumbWithActiveSegmentReturnsActiveMove() {
    let thread = Thread(title: "Imported", kind: .regimented, breadcrumb: "")
    let active = Segment(
      threadId: thread.id,
      title: "Day 01",
      orderIndex: 0,
      builtInMove: "Active move",
      status: .active
    )
    let later = Segment(
      threadId: thread.id,
      title: "Day 02",
      orderIndex: 1,
      builtInMove: "Later move",
      status: .pending
    )
    let resolved = MoveResolver.resolve(thread: thread, segments: [active, later], openItems: [])
    XCTAssertEqual(resolved?.text, "Active move")
  }

  func testEmptyBuiltInMoveSkipsToOpenItem() {
    let thread = Thread(title: "Regi", kind: .regimented)
    let segment = Segment(
      threadId: thread.id,
      title: "Lesson",
      orderIndex: 1,
      builtInMove: "",
      status: .active
    )
    let item = Item(threadId: thread.id, title: "fallback", status: .open)
    let resolved = MoveResolver.resolve(thread: thread, segments: [segment], openItems: [item])
    XCTAssertEqual(resolved?.text, "fallback")
  }
}
