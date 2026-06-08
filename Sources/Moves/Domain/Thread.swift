import Foundation

/// An ongoing line of work. The primary noun in Moves.
///
/// See INITIAL-PLAN.md §3 for vocabulary and §10 for the schema this maps to.
struct Thread: Identifiable, Hashable, Sendable {
  /// UUID string. Generated client-side.
  let id: String
  var title: String
  var status: ThreadStatus
  var kind: ThreadKind
  var visibility: ThreadVisibility
  var breadcrumb: String
  var detailMarkdown: String
  /// Unix seconds.
  var createdAt: Int64
  var updatedAt: Int64
  /// Unix seconds. Nil if the thread has never been touched.
  var lastTouchedAt: Int64?

  init(
    id: String = UUID().uuidString,
    title: String,
    status: ThreadStatus = .active,
    kind: ThreadKind = .normal,
    visibility: ThreadVisibility = .normal,
    breadcrumb: String = "",
    detailMarkdown: String = "",
    createdAt: Int64 = Int64(Date().timeIntervalSince1970),
    updatedAt: Int64 = Int64(Date().timeIntervalSince1970),
    lastTouchedAt: Int64? = nil
  ) {
    self.id = id
    self.title = title
    self.status = status
    self.kind = kind
    self.visibility = visibility
    self.breadcrumb = breadcrumb
    self.detailMarkdown = detailMarkdown
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.lastTouchedAt = lastTouchedAt
  }
}

enum ThreadStatus: String, Sendable, CaseIterable {
  case active
  case parked
  case done
}

enum ThreadKind: String, Sendable, CaseIterable {
  case normal
  case regimented
}

/// Working-hours visibility policy (INITIAL-PLAN.md §6). The schema names
/// these `normal / hide_work / downweight_work / only_work`.
enum ThreadVisibility: String, Sendable, CaseIterable {
  case normal
  case hideWork = "hide_work"
  case downweightWork = "downweight_work"
  case onlyWork = "only_work"
}
