import Foundation

/// Projection used by the popover's Available section: a thread *plus* its
/// resolved re-entry move. The presence of a non-nil move is the §22
/// invariant — threads without one don't make it into this list.
///
/// Built by `AppStore.rebuildAvailable()` from `MoveResolver.resolve(...)`.
struct AvailableThread: Identifiable, Hashable, Sendable {
  var thread: Thread
  var move: MoveResolver.ResolvedMove

  var id: String { thread.id }
}
