import Foundation

/// Parsed Markdown import ready for the user to confirm before commit.
/// Produced by `MarkdownImportService.parse(_:now:)`; consumed by
/// `ImportMarkdownView` for the preview render and by `AppStore.importMarkdown`
/// to materialize rows in a single transaction.
///
/// All identifiers (`thread.id`, `segment.id`, `item.id`) are pre-assigned by
/// the parser so the preview can refer to them and the commit step writes
/// them verbatim. The first pending segment is what `MoveResolver` will
/// surface in Available; that selection is encoded by the per-row
/// `Segment.status` already (the parser sets segment 0 to `.active` per §9
/// rule 9 — "First pending segment becomes active").
struct ImportPreview: Sendable, Hashable {
  var thread: Thread
  var segments: [Segment]
  /// Items keyed by segment id (parser-assigned). The flat representation is
  /// the storage layout; the UI groups by segment for preview.
  var items: [Item]
  /// Non-fatal warnings the user should see before committing. Examples:
  ///   - Unsupported frontmatter key (`tags: [foo]`)
  ///   - Unsupported segment metadata key (`priority: high`)
  ///   - A thread with the same title already exists (create-only v1 produces
  ///     a duplicate).
  ///   - YAML parse failure on a specific line (the line is dropped, others
  ///     keep going).
  var warnings: [String]
}

/// Result of an `AppStore.importMarkdown(_:)` commit. Reports counts so the
/// UI can show "Imported X segments, Y items" after dismiss. Mirrors the
/// shape of `ImportPreview` but with the actual inserted ids.
struct ImportResult: Sendable, Hashable {
  var threadId: String
  var segmentCount: Int
  var itemCount: Int
  var warnings: [String]
}
