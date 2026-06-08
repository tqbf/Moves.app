import XCTest
@testable import Moves

/// Coverage for the §9 deterministic parser. The fixtures pin a known "now"
/// so timestamps don't drift across CI hosts; date parsing uses UTC.
final class MarkdownImportServiceTests: XCTestCase {

  private var now: Date {
    // 2026-06-08 14:30 UTC — same fixture as CaptureParserTests so debugging
    // is consistent across services.
    var components = DateComponents()
    components.year = 2026
    components.month = 6
    components.day = 8
    components.hour = 14
    components.minute = 30
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    return cal.date(from: components)!
  }

  // MARK: - §9 example (the DOD)

  /// The "Definition of done" requires the §9 example file to produce a
  /// regimented thread with 2 segments, first active, all checkboxes as
  /// items. This test pins that exactly.
  func testParsesSection9Example() {
    let source = """
    ---
    title: Python Refresh
    kind: regimented
    visibility: normal
    default_estimate_minutes: 60
    ---

    ## Day 01: Modern Python syntax
    date: 2026-06-01
    estimate: 60

    move: Write a tiny parser using dataclasses and match/case.

    - [ ] Review dataclasses
    - [ ] Review type hints
    - [ ] Write parser
    - [ ] Add pytest cases

    ## Day 02: pathlib, argparse, pytest
    date: 2026-06-02
    estimate: 60

    move: Build a compact access-log parser.

    - [ ] Parse one line
    - [ ] Add named-group regex
    - [ ] Add invalid-line tests
    """

    let preview = MarkdownImportService.parse(source, now: now)
    XCTAssertEqual(preview.thread.title, "Python Refresh")
    XCTAssertEqual(preview.thread.kind, .regimented)
    XCTAssertEqual(preview.thread.visibility, .normal)
    XCTAssertEqual(preview.segments.count, 2)

    // First segment is active per §9 rule 9.
    XCTAssertEqual(preview.segments[0].status, .active)
    XCTAssertEqual(preview.segments[0].title, "Day 01: Modern Python syntax")
    XCTAssertEqual(preview.segments[0].builtInMove, "Write a tiny parser using dataclasses and match/case.")
    XCTAssertEqual(preview.segments[0].estimateMinutes, 60)
    XCTAssertEqual(preview.segments[0].orderIndex, 0)

    XCTAssertEqual(preview.segments[1].status, .pending)
    XCTAssertEqual(preview.segments[1].title, "Day 02: pathlib, argparse, pytest")
    XCTAssertEqual(preview.segments[1].builtInMove, "Build a compact access-log parser.")
    XCTAssertEqual(preview.segments[1].orderIndex, 1)

    XCTAssertEqual(preview.items.count, 7)
    let firstSegItems = preview.items.filter { $0.segmentId == preview.segments[0].id }
    XCTAssertEqual(firstSegItems.count, 4)
    XCTAssertEqual(firstSegItems.map(\.title).sorted(),
                   ["Add pytest cases", "Review dataclasses", "Review type hints", "Write parser"])
    for item in preview.items {
      XCTAssertEqual(item.status, .open)
      XCTAssertEqual(item.kind, .task)
    }
  }

  // MARK: - Frontmatter

  func testFrontmatterUnsupportedKeyEmitsWarning() {
    let source = """
    ---
    title: Test
    kind: regimented
    tags: [foo, bar]
    ---

    ## Only segment
    move: do it
    """
    let preview = MarkdownImportService.parse(source, now: now)
    XCTAssertTrue(preview.warnings.contains(where: { $0.contains("tags") }))
  }

  func testFrontmatterUnknownKindWarnsAndDefaults() {
    let source = """
    ---
    title: Test
    kind: gibberish
    ---

    ## A
    move: x
    """
    let preview = MarkdownImportService.parse(source, now: now)
    XCTAssertEqual(preview.thread.kind, .regimented)
    XCTAssertTrue(preview.warnings.contains(where: { $0.contains("kind") }))
  }

  func testNoFrontmatterStillParsesSegments() {
    let source = """
    ## Segment one
    move: alpha

    - [ ] one
    """
    let preview = MarkdownImportService.parse(source, now: now)
    XCTAssertEqual(preview.thread.title, "Imported")
    XCTAssertEqual(preview.segments.count, 1)
    XCTAssertEqual(preview.items.count, 1)
  }

  func testFrontmatterDefaultEstimateAppliesWhenSegmentOmitsIt() {
    let source = """
    ---
    title: Test
    default_estimate_minutes: 90
    ---

    ## Only segment
    move: x
    """
    let preview = MarkdownImportService.parse(source, now: now)
    XCTAssertEqual(preview.segments.first?.estimateMinutes, 90)
  }

  // MARK: - Segment metadata

  func testSegmentMetadataDueDateParses() {
    let source = """
    ## Lesson 1
    due: 2026-06-12 17:00

    - [ ] one
    """
    let preview = MarkdownImportService.parse(source, now: now)
    let dueAt = preview.segments.first?.dueAt
    XCTAssertNotNil(dueAt)
    // 2026-06-12 17:00 UTC
    let expected = Int64(
      Date(timeIntervalSince1970: 1_781_628_400 - (-3600 * 0)).timeIntervalSince1970
    )
    // Easier: just compute from the components.
    var comps = DateComponents()
    comps.year = 2026; comps.month = 6; comps.day = 12; comps.hour = 17; comps.minute = 0
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    XCTAssertEqual(dueAt, Int64(cal.date(from: comps)!.timeIntervalSince1970))
    _ = expected
  }

  func testSegmentMetadataInvalidDateWarns() {
    let source = """
    ## Lesson 1
    due: not-a-date

    - [ ] one
    """
    let preview = MarkdownImportService.parse(source, now: now)
    XCTAssertNil(preview.segments.first?.dueAt)
    XCTAssertTrue(preview.warnings.contains(where: { $0.contains("due") }))
  }

  func testUnsupportedSegmentMetadataKeyWarns() {
    let source = """
    ## Lesson 1
    priority: high
    move: x

    - [ ] one
    """
    let preview = MarkdownImportService.parse(source, now: now)
    XCTAssertTrue(preview.warnings.contains(where: { $0.contains("priority") }))
    XCTAssertEqual(preview.segments.first?.builtInMove, "x")
  }

  // MARK: - Checklist + body

  func testCheckedItemsLandAsDone() {
    let source = """
    ## Segment
    move: x

    - [ ] open one
    - [x] done one
    - [X] done two
    """
    let preview = MarkdownImportService.parse(source, now: now)
    let statuses = preview.items.map(\.status)
    XCTAssertEqual(statuses.filter { $0 == .open }.count, 1)
    XCTAssertEqual(statuses.filter { $0 == .done }.count, 2)
  }

  func testResidualBodyBecomesSegmentBodyMarkdown() {
    let source = """
    ## Segment
    move: x

    Some paragraph that explains the segment.

    - [ ] one
    - [ ] two

    Another paragraph that lands in the body too.
    """
    let preview = MarkdownImportService.parse(source, now: now)
    let body = preview.segments.first?.bodyMarkdown ?? ""
    XCTAssertTrue(body.contains("Some paragraph that explains the segment."))
    XCTAssertTrue(body.contains("Another paragraph"))
    XCTAssertFalse(body.contains("- [ ]"))
    XCTAssertEqual(preview.items.count, 2)
  }

  func testEmptyInputProducesEmptyPreview() {
    let preview = MarkdownImportService.parse("", now: now)
    XCTAssertEqual(preview.segments.count, 0)
    XCTAssertEqual(preview.items.count, 0)
  }

  func testContentBeforeFirstH2IsDropped() {
    let source = """
    Some intro paragraph that has no segment.

    ## Real segment
    move: x

    - [ ] one
    """
    let preview = MarkdownImportService.parse(source, now: now)
    XCTAssertEqual(preview.segments.count, 1)
    XCTAssertFalse(preview.segments.first?.bodyMarkdown.contains("intro paragraph") ?? true)
  }

  func testUnclosedFrontmatterEmitsWarningAndFallsBackToBody() {
    let source = """
    ---
    title: Broken

    ## Segment
    move: x
    """
    let preview = MarkdownImportService.parse(source, now: now)
    XCTAssertTrue(preview.warnings.contains(where: { $0.contains("Frontmatter") }))
    XCTAssertEqual(preview.thread.title, "Imported") // default
  }
}
