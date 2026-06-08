import Foundation

/// Deterministic Markdown parser for regimented-thread import (INITIAL-PLAN
/// §9). No LLM, no fuzzy matches — every rule below is enumerated.
///
/// Grammar (§9):
///   1. YAML frontmatter (`---` … `---`) defines thread metadata. Supported
///      keys: `title`, `kind`, `visibility`, `default_estimate_minutes`.
///   2. Each `## ` H2 starts a new segment.
///   3. `key: value` lines immediately after the H2 (no blank line yet)
///      are segment metadata.
///   4. Segment metadata ends at the first blank line.
///   5. `move: …` sets `Segment.builtInMove`.
///   6. `- [ ] …` and `- [x] …` checkboxes become associated `Item`s.
///   7. All other residual content (after metadata, excluding checkboxes)
///      becomes the segment's `body_markdown`.
///   8. Segment order follows file order (orderIndex starts at 0).
///   9. First segment becomes `.active`; the rest stay `.pending`.
///   10. v1 is create-only: a duplicate thread title triggers a warning but
///       still proceeds.
///
/// Supported segment metadata: `date`, `due`, `estimate`, `move`. Anything
/// else is dropped with a warning. Same policy for frontmatter.
///
/// Date formats accepted in segment metadata:
///   - `YYYY-MM-DD`
///   - `YYYY-MM-DD HH:MM`
enum MarkdownImportService {

  /// Parse `source` into a preview the UI can render before commit.
  ///
  /// - Parameters:
  ///   - source: Raw Markdown text.
  ///   - now: Injected "now" for stable test fixtures (used for created_at
  ///     timestamps on threads/segments/items). Production passes `Date()`.
  static func parse(_ source: String, now: Date = Date()) -> ImportPreview {
    var warnings: [String] = []
    let nowSeconds = Int64(now.timeIntervalSince1970)

    // 1. Split off YAML frontmatter (if any).
    let (frontmatter, bodyLines) = splitFrontmatter(source: source, warnings: &warnings)

    // 2. Resolve thread metadata from the frontmatter.
    var threadTitle = "Imported"
    var threadKind: ThreadKind = .regimented
    var threadVisibility: ThreadVisibility = .normal
    var defaultEstimate: Int?

    for (key, value) in frontmatter {
      switch key {
      case "title":
        threadTitle = value
      case "kind":
        if let k = ThreadKind(rawValue: value) {
          threadKind = k
        } else {
          warnings.append("Unknown thread kind '\(value)' — defaulting to 'regimented'.")
        }
      case "visibility":
        if let v = ThreadVisibility(rawValue: value) {
          threadVisibility = v
        } else {
          warnings.append("Unknown visibility '\(value)' — defaulting to 'normal'.")
        }
      case "default_estimate_minutes":
        if let n = Int(value) {
          defaultEstimate = n
        } else {
          warnings.append("default_estimate_minutes must be an integer (got '\(value)').")
        }
      default:
        warnings.append("Unsupported frontmatter key '\(key)' — ignored.")
      }
    }

    let thread = Thread(
      title: threadTitle,
      status: .active,
      kind: threadKind,
      visibility: threadVisibility,
      breadcrumb: "",
      detailMarkdown: "",
      createdAt: nowSeconds,
      updatedAt: nowSeconds,
      lastTouchedAt: nil
    )

    // 3. Split body into segments by H2 boundaries.
    let segmentChunks = splitSegments(bodyLines: bodyLines)
    var segments: [Segment] = []
    var items: [Item] = []

    for (offset, chunk) in segmentChunks.enumerated() {
      let parsed = parseSegmentChunk(
        chunk: chunk,
        orderIndex: offset,
        threadId: thread.id,
        defaultEstimate: defaultEstimate,
        nowSeconds: nowSeconds,
        warnings: &warnings
      )
      var segment = parsed.segment
      // Rule 9: first segment is active, rest pending.
      segment.status = offset == 0 ? .active : .pending
      segments.append(segment)
      items.append(contentsOf: parsed.items)
    }

    return ImportPreview(thread: thread, segments: segments, items: items, warnings: warnings)
  }

  // MARK: - Frontmatter

  /// Split the source into (frontmatter pairs, remaining body lines). If no
  /// frontmatter is present, the body is the whole source and the pairs
  /// list is empty.
  private static func splitFrontmatter(
    source: String,
    warnings: inout [String]
  ) -> ([(key: String, value: String)], [String]) {
    let allLines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard let firstNonEmpty = allLines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    else {
      return ([], allLines)
    }
    guard allLines[firstNonEmpty].trimmingCharacters(in: .whitespaces) == "---" else {
      return ([], allLines)
    }
    // Find the closing fence.
    var closeIndex: Int?
    for i in (firstNonEmpty + 1)..<allLines.count {
      if allLines[i].trimmingCharacters(in: .whitespaces) == "---" {
        closeIndex = i
        break
      }
    }
    guard let close = closeIndex else {
      warnings.append("Frontmatter opener '---' has no matching closer — treating whole file as body.")
      return ([], allLines)
    }
    let pairLines = Array(allLines[(firstNonEmpty + 1)..<close])
    let body = close + 1 < allLines.count
      ? Array(allLines[(close + 1)...])
      : []
    let pairs = parseYAMLPairs(lines: pairLines, warnings: &warnings)
    return (pairs, body)
  }

  /// Parse a flat `key: value` block. Supports quoted and unquoted scalars.
  /// Lines that aren't `key: value` shape get a warning and are skipped.
  /// Block / mapping / list YAML constructs are explicitly out of scope.
  private static func parseYAMLPairs(
    lines: [String],
    warnings: inout [String]
  ) -> [(key: String, value: String)] {
    var result: [(String, String)] = []
    for raw in lines {
      let trimmed = raw.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty { continue }
      if trimmed.hasPrefix("#") { continue } // YAML comment
      guard let colonIdx = trimmed.firstIndex(of: ":") else {
        warnings.append("Frontmatter line '\(trimmed)' is not 'key: value' — ignored.")
        continue
      }
      let key = trimmed[..<colonIdx].trimmingCharacters(in: .whitespaces)
      var value = trimmed[trimmed.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
      // Strip matching surrounding quotes if present.
      if (value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2)
        || (value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2) {
        value = String(value.dropFirst().dropLast())
      }
      result.append((key, value))
    }
    return result
  }

  // MARK: - Segments

  /// Split body lines into per-segment chunks at each `## ` H2.
  ///
  /// Lines appearing before the first H2 are dropped with no warning — they
  /// belong to neither thread metadata (that's frontmatter) nor any segment.
  /// `## ` heading lines stay attached to their own chunk (chunk[0]).
  private static func splitSegments(bodyLines: [String]) -> [[String]] {
    var chunks: [[String]] = []
    var current: [String] = []
    var seenFirst = false
    for line in bodyLines {
      if isH2Heading(line) {
        if seenFirst { chunks.append(current) }
        current = [line]
        seenFirst = true
      } else if seenFirst {
        current.append(line)
      }
    }
    if seenFirst { chunks.append(current) }
    return chunks
  }

  private static func isH2Heading(_ line: String) -> Bool {
    let t = line.trimmingCharacters(in: .whitespaces)
    return t.hasPrefix("## ") && !t.hasPrefix("### ")
  }

  /// Parsed shape of a single segment chunk — split out so the test suite
  /// can assert each field independently if it ever wants to drop down to
  /// the unit level.
  private struct ParsedSegment {
    var segment: Segment
    var items: [Item]
  }

  private static func parseSegmentChunk(
    chunk: [String],
    orderIndex: Int,
    threadId: String,
    defaultEstimate: Int?,
    nowSeconds: Int64,
    warnings: inout [String]
  ) -> ParsedSegment {
    // First line is the H2.
    let heading = chunk.first ?? ""
    let title = heading
      .trimmingCharacters(in: .whitespaces)
      .drop(while: { $0 == "#" })
      .trimmingCharacters(in: .whitespaces)

    var move = ""
    var scheduledAt: Int64?
    var dueAt: Int64?
    var estimate: Int? = defaultEstimate
    var bodyLines: [String] = []
    var items: [Item] = []

    // §9 rule 4 says segment metadata ends at the first blank line. In
    // practice the spec example also places `move:` *after* a blank line
    // (see the Python Refresh fixture in §9). To honor both forms, we
    // recognize supported `key: value` lines anywhere before the first
    // checklist item. Bare key:value lines whose key is *not* in the
    // supported set emit a warning only while we're still in the heading-
    // adjacent metadata block (before the first checklist or non-meta
    // body paragraph).
    let metadataKeys: Set<String> = ["date", "due", "estimate", "move"]
    var sawFirstNonMetaBody = false

    for line in chunk.dropFirst() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Blank line — flush into body.
      if trimmed.isEmpty {
        bodyLines.append(line)
        continue
      }

      // Recognize supported metadata anywhere before the first checklist
      // item / non-meta body paragraph. After that, treat key:value lines
      // as body (so a user's "Note: lorem" inside the body doesn't get
      // eaten as metadata).
      if let (key, value) = parseMetadataLine(trimmed), metadataKeys.contains(key) {
        switch key {
        case "move":
          move = value
        case "date":
          if let date = parseDate(value) {
            scheduledAt = date
          } else {
            warnings.append("Could not parse date '\(value)' for segment '\(title)' — ignored.")
          }
        case "due":
          if let date = parseDate(value) {
            dueAt = date
          } else {
            warnings.append("Could not parse due '\(value)' for segment '\(title)' — ignored.")
          }
        case "estimate":
          if let n = Int(value) {
            estimate = n
          } else {
            warnings.append("estimate must be an integer (got '\(value)') for segment '\(title)' — ignored.")
          }
        default:
          break
        }
        continue
      }

      // Unsupported `key: value` line: warn only while still adjacent to
      // the heading (i.e. before any non-meta body content).
      if !sawFirstNonMetaBody, let (key, _) = parseMetadataLine(trimmed),
         !metadataKeys.contains(key) {
        warnings.append("Unsupported segment metadata key '\(key)' in segment '\(title)' — ignored.")
        continue
      }

      // Checklist item.
      if let item = parseChecklistLine(trimmed, threadId: threadId, nowSeconds: nowSeconds) {
        items.append(item)
        sawFirstNonMetaBody = true
        continue
      }

      // Body content.
      bodyLines.append(line)
      sawFirstNonMetaBody = true
    }

    // Trim leading and trailing blank lines from the body.
    let body = bodyLines
      .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
      .reversed()
      .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
      .reversed()
      .joined(separator: "\n")

    let segment = Segment(
      threadId: threadId,
      title: title,
      orderIndex: orderIndex,
      bodyMarkdown: body,
      builtInMove: move,
      status: .pending,
      scheduledAt: scheduledAt,
      dueAt: dueAt,
      estimateMinutes: estimate,
      createdAt: nowSeconds,
      updatedAt: nowSeconds
    )
    // Re-attach the segment id to each item so the AppStore commit can fill
    // `segment_id` on insert.
    let attached = items.map { item -> Item in
      var copy = item
      copy.segmentId = segment.id
      return copy
    }
    return ParsedSegment(segment: segment, items: attached)
  }

  private static func parseMetadataLine(_ line: String) -> (String, String)? {
    guard let colonIdx = line.firstIndex(of: ":") else { return nil }
    let key = line[..<colonIdx].trimmingCharacters(in: .whitespaces)
    let value = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
    guard !key.isEmpty else { return nil }
    return (key, value)
  }

  /// Parse `YYYY-MM-DD` or `YYYY-MM-DD HH:MM` against UTC. Returns nil on
  /// invalid input. Stored as Unix seconds.
  private static func parseDate(_ raw: String) -> Int64? {
    let formats = ["yyyy-MM-dd HH:mm", "yyyy-MM-dd"]
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    for f in formats {
      formatter.dateFormat = f
      if let date = formatter.date(from: raw) {
        return Int64(date.timeIntervalSince1970)
      }
    }
    return nil
  }

  /// Recognize a `- [ ] …` or `- [x] …` checklist line. The leading marker
  /// determines status: open vs done. Other Markdown list lines are not
  /// considered checklist items.
  private static func parseChecklistLine(
    _ trimmed: String,
    threadId: String,
    nowSeconds: Int64
  ) -> Item? {
    // Allow `- ` and `* ` markers. `+` is uncommon and skipped.
    let prefixes = ["- [ ]", "- [x]", "- [X]", "* [ ]", "* [x]", "* [X]"]
    guard let prefix = prefixes.first(where: { trimmed.hasPrefix($0) }) else { return nil }
    let title = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    guard !title.isEmpty else { return nil }
    let isDone = prefix.contains("x") || prefix.contains("X")
    return Item(
      threadId: threadId,
      segmentId: nil, // filled in by parseSegmentChunk
      title: String(title),
      status: isDone ? .done : .open,
      kind: .task,
      dueKind: .none,
      interruptionKind: .none,
      createdAt: nowSeconds,
      updatedAt: nowSeconds,
      completedAt: isDone ? nowSeconds : nil
    )
  }
}
