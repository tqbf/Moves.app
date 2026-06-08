import Foundation

/// A coarse rough-time log entry recorded when stopping / switching / parking
/// a thread or completing a segment (INITIAL-PLAN.md §14, §10).
///
/// `roughMinutes` is one of the seven buckets defined in §14:
/// `0, 15, 30, 45, 60, 120, 180` (the last bucket meaning "3h+").
struct TimeLogEntry: Identifiable, Hashable, Sendable {
  let id: String
  let threadId: String
  var segmentId: String?
  /// Week start as `YYYY-MM-DD`, a Monday in the user's local calendar. Stored
  /// as text so weekly grouping is a simple GROUP BY (INITIAL-PLAN.md §14).
  var weekStart: String
  var roughMinutes: Int
  /// Unix seconds.
  var createdAt: Int64

  init(
    id: String = UUID().uuidString,
    threadId: String,
    segmentId: String? = nil,
    weekStart: String,
    roughMinutes: Int,
    createdAt: Int64 = Int64(Date().timeIntervalSince1970)
  ) {
    self.id = id
    self.threadId = threadId
    self.segmentId = segmentId
    self.weekStart = weekStart
    self.roughMinutes = roughMinutes
    self.createdAt = createdAt
  }
}
