import Foundation

/// An ordered unit inside a regimented thread (INITIAL-PLAN.md §3, §10).
struct Segment: Identifiable, Hashable, Sendable {
  let id: String
  let threadId: String
  var title: String
  var orderIndex: Int
  var bodyMarkdown: String
  var builtInMove: String
  var status: SegmentStatus
  /// Unix seconds.
  var scheduledAt: Int64?
  /// Unix seconds.
  var dueAt: Int64?
  var estimateMinutes: Int?
  var createdAt: Int64
  var updatedAt: Int64

  init(
    id: String = UUID().uuidString,
    threadId: String,
    title: String,
    orderIndex: Int,
    bodyMarkdown: String = "",
    builtInMove: String = "",
    status: SegmentStatus = .pending,
    scheduledAt: Int64? = nil,
    dueAt: Int64? = nil,
    estimateMinutes: Int? = nil,
    createdAt: Int64 = Int64(Date().timeIntervalSince1970),
    updatedAt: Int64 = Int64(Date().timeIntervalSince1970)
  ) {
    self.id = id
    self.threadId = threadId
    self.title = title
    self.orderIndex = orderIndex
    self.bodyMarkdown = bodyMarkdown
    self.builtInMove = builtInMove
    self.status = status
    self.scheduledAt = scheduledAt
    self.dueAt = dueAt
    self.estimateMinutes = estimateMinutes
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

enum SegmentStatus: String, Sendable, CaseIterable {
  case pending
  case active
  case done
  case skipped
}
