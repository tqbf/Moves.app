import Foundation

/// One thread's rough-time aggregate for a given ISO week. Produced by
/// `TimeLogService.aggregate(entries:)` and consumed by `WeeklyView`.
struct ThreadAggregate: Sendable, Hashable, Identifiable {
  var id: String { threadId }
  let threadId: String
  /// Sum of all `rough_minutes` for this thread in the source entry set.
  let totalMinutes: Int
}

/// A week's projection: the resolved Monday (YYYY-MM-DD) and one row per
/// thread that had at least one log entry. Threads with no rows are absent;
/// `WeeklyView` resolves thread titles by joining against `AppStore.threads`.
struct WeeklySummary: Sendable, Hashable {
  let weekStart: String
  let entries: [ThreadAggregate]

  /// Convenience for the empty case. Used by the view when navigating to a
  /// week with no rows so it can render an empty state without a force-unwrap.
  static func empty(weekStart: String) -> WeeklySummary {
    WeeklySummary(weekStart: weekStart, entries: [])
  }
}
