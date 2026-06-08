import Foundation

/// Pure resolver for a thread's displayed re-entry move (INITIAL-PLAN.md §11).
/// A "move" is a UI projection — there is no `moves` table.
///
/// Resolution order:
///
///   1. If `thread.breadcrumb` is non-empty: show breadcrumb.
///   2. Else if thread is regimented with an active or pending segment whose
///      `builtInMove` is non-empty: show segment.builtInMove.
///   3. Else if thread has an open item: show first open item's title.
///   4. Else: no move — thread should not appear in Available (§22).
///
/// For regimented threads, an active segment wins over a pending segment; if
/// no active segment exists, the first pending segment (by `orderIndex`)
/// becomes the displayed segment. Only explicit completion advances it.
enum MoveResolver {

  /// What we resolved, including provenance — callers (the popover) display
  /// the resolved text and use the kind for secondary copy / iconography.
  struct ResolvedMove: Hashable, Sendable {
    enum Source: Hashable, Sendable {
      case breadcrumb
      case segment(segmentId: String, segmentTitle: String)
      case openItem(itemId: String)
    }
    var text: String
    var source: Source
  }

  /// Returns the resolved move for `thread`, or nil if the thread has no
  /// re-entry point and should not appear in Available.
  ///
  /// - Parameters:
  ///   - thread: The thread being resolved.
  ///   - segments: Segments belonging to this thread. Order does not matter;
  ///     the resolver sorts by `orderIndex`.
  ///   - openItems: Items belonging to this thread with status `.open`,
  ///     pre-filtered by the caller. Ordering follows the caller's intent
  ///     (typically `createdAt` ascending).
  static func resolve(
    thread: Thread,
    segments: [Segment],
    openItems: [Item]
  ) -> ResolvedMove? {
    let breadcrumb = thread.breadcrumb.trimmingCharacters(in: .whitespacesAndNewlines)
    if !breadcrumb.isEmpty {
      return ResolvedMove(text: breadcrumb, source: .breadcrumb)
    }

    if thread.kind == .regimented, let segment = displayedSegment(for: segments) {
      let move = segment.builtInMove.trimmingCharacters(in: .whitespacesAndNewlines)
      if !move.isEmpty {
        return ResolvedMove(
          text: move,
          source: .segment(segmentId: segment.id, segmentTitle: segment.title)
        )
      }
    }

    if let item = openItems.first {
      return ResolvedMove(text: item.title, source: .openItem(itemId: item.id))
    }

    return nil
  }

  /// The segment a regimented thread should currently display: active beats
  /// the first pending segment by `orderIndex`. Returns nil otherwise.
  static func displayedSegment(for segments: [Segment]) -> Segment? {
    if let active = segments.first(where: { $0.status == .active }) {
      return active
    }
    return segments
      .filter { $0.status == .pending }
      .sorted { $0.orderIndex < $1.orderIndex }
      .first
  }
}
