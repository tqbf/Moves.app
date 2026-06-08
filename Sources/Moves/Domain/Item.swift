import Foundation

/// A captured thing: inbox capture, reminder, deadline task, lightweight todo.
/// May or may not be attached to a thread. See INITIAL-PLAN.md §3 / §10.
struct Item: Identifiable, Hashable, Sendable {
  let id: String
  var threadId: String?
  var segmentId: String?
  var title: String
  var bodyMarkdown: String
  var status: ItemStatus
  var kind: ItemKind
  /// Unix seconds.
  var dueAt: Int64?
  var dueKind: DueKind
  var interruptionKind: InterruptionKind
  var createdAt: Int64
  var updatedAt: Int64
  /// Unix seconds.
  var completedAt: Int64?

  init(
    id: String = UUID().uuidString,
    threadId: String? = nil,
    segmentId: String? = nil,
    title: String,
    bodyMarkdown: String = "",
    status: ItemStatus = .captured,
    kind: ItemKind = .capture,
    dueAt: Int64? = nil,
    dueKind: DueKind = .none,
    interruptionKind: InterruptionKind = .none,
    createdAt: Int64 = Int64(Date().timeIntervalSince1970),
    updatedAt: Int64 = Int64(Date().timeIntervalSince1970),
    completedAt: Int64? = nil
  ) {
    self.id = id
    self.threadId = threadId
    self.segmentId = segmentId
    self.title = title
    self.bodyMarkdown = bodyMarkdown
    self.status = status
    self.kind = kind
    self.dueAt = dueAt
    self.dueKind = dueKind
    self.interruptionKind = interruptionKind
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.completedAt = completedAt
  }
}

enum ItemStatus: String, Sendable, CaseIterable {
  case captured
  case open
  case done
  case canceled
}

enum ItemKind: String, Sendable, CaseIterable {
  case capture
  case task
  case reminder
}

enum DueKind: String, Sendable, CaseIterable {
  case none
  case date
  case datetime
}

enum InterruptionKind: String, Sendable, CaseIterable {
  case none
  case soft
  case hard
}
