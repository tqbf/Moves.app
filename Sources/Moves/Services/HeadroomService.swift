import Foundation

/// Pure projection over upcoming items that drives the popover's Upcoming
/// section (INITIAL-PLAN §2.10, §4.1). "Headroom" is the runway between
/// `now` and the next hard interruption — it is a *display aid*, not a
/// scheduler. See §2.10: "Headroom is a nudge, not the app."
///
/// This service is intentionally pure: it takes `now` and `items` and
/// returns a `Headroom` value. The popover owns the timer that recomputes
/// it; persistence and notification scheduling live elsewhere.
enum HeadroomService {

  /// Result of resolving headroom from a set of upcoming items.
  ///
  /// `nextHard` is the soonest hard-interruption item with a `dueAt` — the
  /// only item allowed to contribute "runway" (§2.10 forbids ranking soft
  /// work). `runway` is `dueAt - now`. A negative runway means the hard
  /// item is overdue and is reported as-is so the UI can render it
  /// honestly ("Call at 4:00pm — 12m overdue").
  struct Headroom: Hashable, Sendable {
    var nextHard: Item?
    /// `nextHard.dueAt - now` if a hard item exists; nil otherwise.
    /// Negative when overdue.
    var runway: TimeInterval?
  }

  /// Resolve headroom from `items` against `now`.
  ///
  /// - Parameters:
  ///   - now: Current time. Pass `Date()` from views; tests pass a fixture.
  ///   - items: Candidate items. Only items with `dueAt != nil` are
  ///     considered; the caller may pass the full upcoming feed.
  static func resolve(now: Date, items: [Item]) -> Headroom {
    let nowSeconds = Int64(now.timeIntervalSince1970)

    let hardWithDue = items
      .filter { $0.interruptionKind == .hard && $0.dueAt != nil }
      .sorted { ($0.dueAt ?? 0) < ($1.dueAt ?? 0) }

    guard let next = hardWithDue.first, let due = next.dueAt else {
      return Headroom(nextHard: nil, runway: nil)
    }

    let runway = TimeInterval(due - nowSeconds)
    return Headroom(nextHard: next, runway: runway)
  }
}
