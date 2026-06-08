import Foundation

/// Single-row table holding "what am I currently working on?" (INITIAL-PLAN.md
/// §10). All fields are optional — "no current thread" is a valid state (§2.6).
struct CurrentState: Hashable, Sendable {
  var threadId: String?
  var segmentId: String?
  /// Unix seconds. Records when the current thread was set, used for coarse
  /// later time estimation (§5.1).
  var startedAt: Int64?

  init(threadId: String? = nil, segmentId: String? = nil, startedAt: Int64? = nil) {
    self.threadId = threadId
    self.segmentId = segmentId
    self.startedAt = startedAt
  }

  static let empty = CurrentState()
}
