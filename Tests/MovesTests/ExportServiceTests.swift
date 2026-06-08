import XCTest
@testable import Moves

/// Tests Phase-6 `ExportService`: SQLite snapshot round-trips and the
/// Markdown bundle round-trips with `MarkdownImportService` for the
/// regimented case.
@MainActor
final class ExportServiceTests: XCTestCase {
  private var tempDir: URL!
  private var store: AppStore!

  override func setUp() async throws {
    tempDir = FileManager.default.temporaryDirectory
      .appending(path: "moves-export-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    store = AppStore(databasePath: dbPath, enableNotifications: false)
  }

  override func tearDown() async throws {
    store = nil
    if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
  }

  private var dbPath: String {
    tempDir.appending(path: "moves.sqlite3").path(percentEncoded: false)
  }

  // MARK: - SQLite snapshot

  func testSnapshotIsValidDatabaseWithSameThreads() async throws {
    let thread = Moves.Thread(title: "Ship Moves v1")
    try await store.threadRepository.insert(thread)

    let destination = tempDir.appending(path: "snapshot.sqlite3")
    try await store.exportService().exportSnapshot(to: destination)

    XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path),
                  "VACUUM INTO should land at the chosen path")

    // Open the snapshot as a fresh DB and verify the thread is present.
    let restored = try Database(path: destination.path(percentEncoded: false))
    let threadRepo = ThreadRepository(database: restored)
    let threads = try await threadRepo.all()
    XCTAssertEqual(threads.map(\.title), ["Ship Moves v1"])
  }

  func testSnapshotOverwritesExistingFile() async throws {
    let destination = tempDir.appending(path: "snapshot.sqlite3")
    try "pre-existing".write(to: destination, atomically: true, encoding: .utf8)

    let thread = Moves.Thread(title: "Pay quarterly taxes")
    try await store.threadRepository.insert(thread)

    try await store.exportService().exportSnapshot(to: destination)

    let restored = try Database(path: destination.path(percentEncoded: false))
    let threadRepo = ThreadRepository(database: restored)
    let threads = try await threadRepo.all()
    XCTAssertEqual(threads.map(\.title), ["Pay quarterly taxes"])
  }

  // MARK: - Markdown bundle

  func testMarkdownBundleWritesOnePerThreadAndCaptured() async throws {
    // Two threads + one orphan captured item.
    let regimented = Moves.Thread(title: "Python refresh", kind: .regimented)
    try await store.threadRepository.insert(regimented)
    let seg = Segment(
      threadId: regimented.id,
      title: "Day 01",
      orderIndex: 0,
      bodyMarkdown: "",
      builtInMove: "Write parser",
      status: .active
    )
    try await store.segmentRepository.insert(seg)
    let task = Item(
      threadId: regimented.id,
      segmentId: seg.id,
      title: "sketch the AST",
      status: .open,
      kind: .task
    )
    try await store.itemRepository.insert(task)

    let normal = Moves.Thread(title: "Ship Moves v1")
    try await store.threadRepository.insert(normal)

    let orphan = Item(threadId: nil, title: "call dentist", status: .captured, kind: .capture)
    try await store.itemRepository.insert(orphan)

    let dest = tempDir.appending(path: "bundle", directoryHint: .isDirectory)
    let summary = try await store.exportService().exportMarkdownBundle(to: dest)
    XCTAssertEqual(summary.threadFileCount, 2)
    XCTAssertEqual(summary.capturedItemCount, 1)

    let fm = FileManager.default
    XCTAssertTrue(fm.fileExists(atPath: dest.appending(path: "python-refresh.md").path))
    XCTAssertTrue(fm.fileExists(atPath: dest.appending(path: "ship-moves-v1.md").path))
    XCTAssertTrue(fm.fileExists(atPath: dest.appending(path: "captured.md").path))
    XCTAssertTrue(fm.fileExists(atPath: dest.appending(path: "time-log.csv").path))

    let pythonMd = try String(contentsOf: dest.appending(path: "python-refresh.md"), encoding: .utf8)
    XCTAssertTrue(pythonMd.contains("title: Python refresh"))
    XCTAssertTrue(pythonMd.contains("kind: regimented"))
    XCTAssertTrue(pythonMd.contains("## Day 01"))
    XCTAssertTrue(pythonMd.contains("move: Write parser"))
    XCTAssertTrue(pythonMd.contains("- [ ] sketch the AST"))

    let capturedMd = try String(contentsOf: dest.appending(path: "captured.md"), encoding: .utf8)
    XCTAssertTrue(capturedMd.contains("## call dentist"))
  }

  func testMarkdownBundleRoundTripsWithImporter() async throws {
    // Seed a regimented thread with one segment + one task, export, then
    // re-import the .md and assert the parsed shape matches.
    let original = Moves.Thread(title: "Regimented A", kind: .regimented)
    try await store.threadRepository.insert(original)
    let seg = Segment(
      threadId: original.id,
      title: "Step 1",
      orderIndex: 0,
      bodyMarkdown: "",
      builtInMove: "Do thing",
      status: .active,
      estimateMinutes: 30
    )
    try await store.segmentRepository.insert(seg)
    let task = Item(
      threadId: original.id,
      segmentId: seg.id,
      title: "first task",
      status: .open,
      kind: .task
    )
    try await store.itemRepository.insert(task)

    let dest = tempDir.appending(path: "roundtrip", directoryHint: .isDirectory)
    _ = try await store.exportService().exportMarkdownBundle(to: dest)

    let mdURL = dest.appending(path: "regimented-a.md")
    let md = try String(contentsOf: mdURL, encoding: .utf8)
    let preview = MarkdownImportService.parse(md)

    XCTAssertEqual(preview.thread.title, "Regimented A")
    XCTAssertEqual(preview.thread.kind, .regimented)
    XCTAssertEqual(preview.segments.count, 1)
    XCTAssertEqual(preview.segments.first?.title, "Step 1")
    XCTAssertEqual(preview.segments.first?.builtInMove, "Do thing")
    XCTAssertEqual(preview.segments.first?.estimateMinutes, 30)
    XCTAssertEqual(preview.items.count, 1)
    XCTAssertEqual(preview.items.first?.title, "first task")
    XCTAssertEqual(preview.items.first?.status, .open)
    XCTAssertTrue(preview.warnings.isEmpty,
                  "round-trip should not introduce parser warnings: \(preview.warnings)")
  }

  func testTimeLogCSVHasHeaderAndOneRowPerEntry() async throws {
    let thread = Moves.Thread(title: "Thread X")
    try await store.threadRepository.insert(thread)
    let entry = TimeLogEntry(
      threadId: thread.id,
      segmentId: nil,
      weekStart: "2026-06-08",
      roughMinutes: 30
    )
    try await store.timeLogRepository.insert(entry)

    let dest = tempDir.appending(path: "csv", directoryHint: .isDirectory)
    _ = try await store.exportService().exportMarkdownBundle(to: dest)

    let csv = try String(contentsOf: dest.appending(path: "time-log.csv"), encoding: .utf8)
    let rows = csv.split(separator: "\n").map(String.init)
    XCTAssertEqual(rows.first, "week_start,thread_title,segment_title,rough_minutes")
    XCTAssertEqual(rows.dropFirst().first, "2026-06-08,Thread X,,30")
  }

  func testTimeLogCSVQuotesCommas() async throws {
    let thread = Moves.Thread(title: "Sales, taxes, and trouble")
    try await store.threadRepository.insert(thread)
    let entry = TimeLogEntry(
      threadId: thread.id,
      segmentId: nil,
      weekStart: "2026-06-08",
      roughMinutes: 60
    )
    try await store.timeLogRepository.insert(entry)

    let dest = tempDir.appending(path: "csv-quote", directoryHint: .isDirectory)
    _ = try await store.exportService().exportMarkdownBundle(to: dest)

    let csv = try String(contentsOf: dest.appending(path: "time-log.csv"), encoding: .utf8)
    XCTAssertTrue(csv.contains("\"Sales, taxes, and trouble\""))
  }

  // MARK: - Slug

  func testSlugBasic() {
    XCTAssertEqual(ExportService.slug("Ship Moves v1"), "ship-moves-v1")
    XCTAssertEqual(ExportService.slug("Pay! quarterly... taxes"), "pay-quarterly-taxes")
    XCTAssertEqual(ExportService.slug("   "), "thread")
    XCTAssertEqual(ExportService.slug("12 — easy"), "12-easy")
  }

  // MARK: - CSV quoting

  func testCSVQuoteEscapesEmbeddedQuotes() {
    XCTAssertEqual(ExportService.csvQuote("plain"), "plain")
    XCTAssertEqual(ExportService.csvQuote("with,comma"), "\"with,comma\"")
    XCTAssertEqual(ExportService.csvQuote("she said \"hi\""), "\"she said \"\"hi\"\"\"")
  }
}
