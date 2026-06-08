import Foundation

/// A scheduled notification offset against an item's `due_at`. Negative values
/// fire before due; zero fires at due time. See INITIAL-PLAN.md §8.3 / §10.
struct Alert: Identifiable, Hashable, Sendable {
  let id: String
  let itemId: String
  var offsetMinutes: Int
  /// Unix seconds. Nil until the OS has fired this alert.
  var firedAt: Int64?

  init(
    id: String = UUID().uuidString,
    itemId: String,
    offsetMinutes: Int,
    firedAt: Int64? = nil
  ) {
    self.id = id
    self.itemId = itemId
    self.offsetMinutes = offsetMinutes
    self.firedAt = firedAt
  }
}
