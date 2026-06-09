import Foundation

/// Three-state urgency signal driving the menubar knight tint and the
/// popover-header chip. Derived from `AppStore.dueOrOverdueHardCount` and
/// `dueSoonHardCount` via `AppStore.renderedDeadlineUrgency` (which also
/// applies the badge-enabled preference gate).
///
/// `.overdue` dominates `.near` when both buckets have rows: a passed
/// deadline outranks an approaching one for the at-a-glance signal.
enum DeadlineUrgency: Sendable, Equatable {
  /// No hard-interruption deadline is approaching or recently passed.
  /// Menubar shows template knight; popover header shows no chip.
  case none

  /// At least one hard item is due within the next 30 minutes (strict
  /// future). Menubar tints the knight orange (system orange,
  /// `#FF9500` / `#FF9F0A` — Apple HIG "warning"); popover header
  /// shows "•N soon" in orange.
  case near

  /// At least one hard item passed within the last hour. Menubar
  /// tints the knight red (system red, `#FF3B30` / `#FF453A` — Apple
  /// HIG "urgent/destructive") and shows the `•N` count chip; popover
  /// header shows "•N overdue" in red.
  case overdue
}
