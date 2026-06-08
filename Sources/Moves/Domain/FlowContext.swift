import Foundation

/// Context payload for a flow sheet (Stop/Switch/Park). The popover stages
/// the relevant thread (and, for Switch, the new target) on the AppStore
/// before opening a separate `Window` scene; the sheet view reads it from
/// the store on appear, mutates locally, and calls back into the store on
/// confirm.
///
/// We don't pass this through `openWindow`'s value parameter because the
/// popover scene already loses focus the moment the sheet opens — easier
/// to stage state on the @Observable store and let the sheet read it.
enum FlowContext: Hashable, Sendable {
  case stop(threadId: String)
  case `switch`(fromThreadId: String, toThreadId: String)
  case park(threadId: String)
  /// Phase-5 segment-completion sheet (§5.5). The sheet logs rough time
  /// against `(threadId, segmentId)` and advances to the next pending
  /// segment in the same thread.
  case completeSegment(threadId: String, segmentId: String)
}
