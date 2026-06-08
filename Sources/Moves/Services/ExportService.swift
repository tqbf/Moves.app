import Foundation

/// Phase-6 backup/export (INITIAL-PLAN §18). Two flavors:
///
///   - **SQLite snapshot.** `VACUUM INTO` to a user-chosen path. Canonical
///     backup: byte-for-byte the live DB, no schema drift risk, restorable
///     by replacing the live file. See `exportSnapshot(to:)`.
///   - **Markdown bundle.** A directory containing one `.md` per thread
///     (frontmatter + `## segments` per §9), one `captured.md` for orphan
///     captured items (status = `.captured`, no thread), and one
///     `time-log.csv` aggregating rough-time entries by (week_start,
///     thread_title, segment_title, rough_minutes). Human-readable, and
///     regimented threads round-trip with `MarkdownImportService`.
///
/// Both flavors run off the same `Database` actor + repositories, so the
/// export view sees a consistent snapshot.
@MainActor
struct ExportService {

  // MARK: - Errors

  enum ExportError: Error, CustomStringConvertible {
    case destinationExists(String)
    case createDirectoryFailed(String)
    case writeFailed(String)

    var description: String {
      switch self {
      case let .destinationExists(path):
        return "Destination already exists: \(path)"
      case let .createDirectoryFailed(message):
        return "Could not create export directory: \(message)"
      case let .writeFailed(message):
        return "Write failed: \(message)"
      }
    }
  }

  // MARK: - Dependencies

  let database: Database
  let threadRepository: ThreadRepository
  let segmentRepository: SegmentRepository
  let itemRepository: ItemRepository
  let timeLogRepository: TimeLogRepository

  init(
    database: Database,
    threadRepository: ThreadRepository,
    segmentRepository: SegmentRepository,
    itemRepository: ItemRepository,
    timeLogRepository: TimeLogRepository
  ) {
    self.database = database
    self.threadRepository = threadRepository
    self.segmentRepository = segmentRepository
    self.itemRepository = itemRepository
    self.timeLogRepository = timeLogRepository
  }

  // MARK: - SQLite snapshot

  /// `VACUUM INTO` the live database to `destination`. If the file exists,
  /// we replace it (matches NSSavePanel semantics — the panel already
  /// confirms overwrite intent with the user). SQLite's `VACUUM INTO`
  /// itself refuses to write over an existing file, so we delete first.
  func exportSnapshot(to destination: URL) async throws {
    let path = destination.path(percentEncoded: false)
    if FileManager.default.fileExists(atPath: path) {
      try FileManager.default.removeItem(atPath: path)
    }
    try await database.snapshot(to: path)
  }

  // MARK: - Markdown bundle

  /// Write a Markdown bundle into the directory at `destination`. The
  /// directory is created if missing; existing contents are left alone
  /// unless they collide with our files (`<thread>.md`, `captured.md`,
  /// `time-log.csv`).
  ///
  /// Per-thread file shape (round-trippable with `MarkdownImportService`):
  ///
  ///     ---
  ///     title: Ship Moves v1
  ///     kind: regimented
  ///     visibility: normal
  ///     ---
  ///
  ///     ## Day 01
  ///
  ///     move: Write parser
  ///     estimate: 60
  ///
  ///     - [ ] sketch the AST
  ///
  ///     Notes paragraph here.
  ///
  /// `captured.md` is a single H2 per item with metadata lines and the
  /// body if any. `time-log.csv` has a header row + one row per
  /// `time_log` entry.
  @discardableResult
  func exportMarkdownBundle(to destination: URL) async throws -> ExportSummary {
    let fm = FileManager.default
    do {
      try fm.createDirectory(at: destination, withIntermediateDirectories: true)
    } catch {
      throw ExportError.createDirectoryFailed(String(describing: error))
    }

    var threadFiles = 0
    let threads = try await threadRepository.all()
    for thread in threads {
      let segments = try await segmentRepository.forThread(thread.id)
      let items = try await itemRepository.forThread(thread.id)
      let markdown = Self.renderThreadMarkdown(
        thread: thread,
        segments: segments,
        items: items
      )
      let url = destination.appendingPathComponent("\(Self.slug(thread.title)).md")
      try Self.write(markdown, to: url)
      threadFiles += 1
    }

    let orphan = try await itemRepository.orphanCaptured()
    let capturedURL = destination.appendingPathComponent("captured.md")
    try Self.write(Self.renderCapturedMarkdown(items: orphan), to: capturedURL)

    // Time-log CSV. One row per time_log entry. Looked up per thread so we
    // can resolve titles (segment titles via the segment repo).
    let csvURL = destination.appendingPathComponent("time-log.csv")
    let csv = try await renderTimeLogCSV(threads: threads)
    try Self.write(csv, to: csvURL)

    return ExportSummary(
      directory: destination,
      threadFileCount: threadFiles,
      capturedItemCount: orphan.count
    )
  }

  /// Result of a Markdown export so the view can render a confirmation.
  struct ExportSummary: Sendable {
    let directory: URL
    let threadFileCount: Int
    let capturedItemCount: Int
  }

  // MARK: - Markdown rendering (pure)

  /// Emit one `.md` per thread that round-trips with
  /// `MarkdownImportService.parse` for the regimented case. For normal
  /// threads we still emit segments-as-H2 if any exist; the parser will
  /// treat them as segments on re-import (which becomes a regimented
  /// thread). This is the conservative shape — we don't ship an "items
  /// belong to no segment" representation, since the v1 importer requires
  /// an H2 boundary.
  static func renderThreadMarkdown(
    thread: Thread,
    segments: [Segment],
    items: [Item]
  ) -> String {
    var lines: [String] = []

    // YAML frontmatter — only emit keys the parser recognizes.
    lines.append("---")
    lines.append("title: \(escapeYAML(thread.title))")
    lines.append("kind: \(thread.kind.rawValue)")
    lines.append("visibility: \(thread.visibility.rawValue)")
    lines.append("---")
    lines.append("")

    if !thread.detailMarkdown.trimmingCharacters(in: .whitespaces).isEmpty {
      // §9 parser drops content before the first H2; we still emit it so
      // a human reader sees the notes. A future round-trip extension could
      // promote this into a `description:` frontmatter scalar.
      lines.append(thread.detailMarkdown.trimmingCharacters(in: .whitespacesAndNewlines))
      lines.append("")
    }

    let sortedSegments = segments.sorted { $0.orderIndex < $1.orderIndex }

    if sortedSegments.isEmpty {
      // No segments — emit a single synthetic segment so items survive
      // round-trip. Title is the thread title; items become checklist
      // entries. Skipped if there are no items either.
      if !items.isEmpty {
        lines.append("## \(thread.title)")
        lines.append("")
        renderItems(items, into: &lines)
      }
    } else {
      for segment in sortedSegments {
        lines.append("## \(segment.title)")
        lines.append("")

        if !segment.builtInMove.trimmingCharacters(in: .whitespaces).isEmpty {
          lines.append("move: \(segment.builtInMove)")
        }
        if let scheduled = segment.scheduledAt {
          lines.append("date: \(formatYMDHM(scheduled))")
        }
        if let due = segment.dueAt {
          lines.append("due: \(formatYMDHM(due))")
        }
        if let estimate = segment.estimateMinutes {
          lines.append("estimate: \(estimate)")
        }
        // Blank line after metadata block per §9 rule 4.
        if segment.builtInMove.isEmpty == false
          || segment.scheduledAt != nil
          || segment.dueAt != nil
          || segment.estimateMinutes != nil {
          lines.append("")
        }

        let segItems = items.filter { $0.segmentId == segment.id }
        renderItems(segItems, into: &lines)

        let trimmedBody = segment.bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
          lines.append(trimmedBody)
          lines.append("")
        }
      }

      // Items without a segment under a regimented thread are unusual but
      // possible (e.g. a captured item attached to the thread before any
      // segment existed). Park them at the end under a synthetic H2 so
      // round-trip doesn't drop them.
      let unsegmented = items.filter { $0.segmentId == nil }
      if !unsegmented.isEmpty {
        lines.append("## Unsegmented items")
        lines.append("")
        renderItems(unsegmented, into: &lines)
      }
    }

    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
  }

  private static func renderItems(_ items: [Item], into lines: inout [String]) {
    if items.isEmpty { return }
    for item in items {
      let marker: String
      switch item.status {
      case .done:
        marker = "- [x]"
      case .open, .captured:
        marker = "- [ ]"
      case .canceled:
        // §9 parser doesn't distinguish canceled items; mark them done
        // with a comment so the human reader can spot them but the
        // checklist count stays honest.
        marker = "- [x]"
      }
      lines.append("\(marker) \(item.title)")
    }
    lines.append("")
  }

  /// `captured.md` — one H2 per orphan captured item with the title; the
  /// due / kind metadata in a small key:value block underneath.
  static func renderCapturedMarkdown(items: [Item]) -> String {
    var lines: [String] = ["# Captured", ""]
    if items.isEmpty {
      lines.append("_Nothing in the inbox._")
      lines.append("")
      return lines.joined(separator: "\n")
    }
    for item in items {
      lines.append("## \(item.title)")
      lines.append("")
      lines.append("kind: \(item.kind.rawValue)")
      lines.append("interruption: \(item.interruptionKind.rawValue)")
      if let due = item.dueAt {
        lines.append("due: \(formatYMDHM(due))")
      }
      lines.append("")
      let trimmedBody = item.bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmedBody.isEmpty {
        lines.append(trimmedBody)
        lines.append("")
      }
    }
    return lines.joined(separator: "\n")
  }

  /// `time-log.csv` — `week_start,thread_title,segment_title,rough_minutes`.
  /// One row per `time_log` entry. Headers come first. Quoting handles
  /// titles that contain commas or quotes.
  private func renderTimeLogCSV(threads: [Thread]) async throws -> String {
    var rows: [String] = ["week_start,thread_title,segment_title,rough_minutes"]
    // Build a (threadId -> title) and (segmentId -> title) map up front so
    // we avoid an N-row lookup per entry.
    let threadTitle = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0.title) })
    var segmentTitleCache: [String: String] = [:]
    for thread in threads where thread.kind == .regimented {
      let segments = try await segmentRepository.forThread(thread.id)
      for segment in segments {
        segmentTitleCache[segment.id] = segment.title
      }
    }
    for thread in threads {
      let entries = try await timeLogRepository.forThread(thread.id)
      for entry in entries {
        let segmentLabel = entry.segmentId.flatMap { segmentTitleCache[$0] } ?? ""
        let title = threadTitle[entry.threadId] ?? ""
        rows.append([
          entry.weekStart,
          Self.csvQuote(title),
          Self.csvQuote(segmentLabel),
          String(entry.roughMinutes),
        ].joined(separator: ","))
      }
    }
    return rows.joined(separator: "\n") + "\n"
  }

  // MARK: - Helpers

  /// Slug a thread title for the filename (`Ship Moves v1` → `ship-moves-v1`).
  /// Falls back to "thread-<id-suffix>" if the title slug is empty.
  static func slug(_ title: String) -> String {
    let lowered = title.lowercased()
    let mapped = lowered.map { ch -> Character in
      if ch.isLetter || ch.isNumber { return ch }
      return "-"
    }
    var compressed = ""
    var lastDash = false
    for ch in mapped {
      if ch == "-" {
        if !lastDash, !compressed.isEmpty {
          compressed.append("-")
        }
        lastDash = true
      } else {
        compressed.append(ch)
        lastDash = false
      }
    }
    let trimmed = compressed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return trimmed.isEmpty ? "thread" : trimmed
  }

  /// Quote a CSV field if it contains a comma, double quote, or newline.
  /// Standard `""` escape for embedded quotes.
  static func csvQuote(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") {
      return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return value
  }

  /// Frontmatter values pass through unquoted unless they contain special
  /// characters that would break parsing. The §9 parser strips matching
  /// quotes — so we add them when needed.
  private static func escapeYAML(_ value: String) -> String {
    if value.contains(":") || value.contains("#") || value.contains("'") {
      return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
    return value
  }

  /// Format a Unix-seconds timestamp as `YYYY-MM-DD HH:MM` in UTC. Matches
  /// the §9 parser's `parseDate` formats. Reused for `date:` / `due:`.
  private static func formatYMDHM(_ seconds: Int64) -> String {
    Self.dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
  }

  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f
  }()

  private static func write(_ contents: String, to url: URL) throws {
    do {
      try contents.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      throw ExportError.writeFailed(String(describing: error))
    }
  }
}
