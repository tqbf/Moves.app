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
