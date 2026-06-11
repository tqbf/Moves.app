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

/// Per-chip time-pressure state for a single deadline. Distinct from
/// `DeadlineUrgency` (which is a *fleet-wide* signal: "any hard item
/// overdue right now?") because the chip needs day-level granularity
/// per-row — "due today" reads differently from "due Friday" even though
/// both are non-overdue futures. The menubar / popover header still use
/// the three-state `DeadlineUrgency` count signal.
///
/// Color policy (batch 6, item 24):
/// - `.overdue` → system red `#FF3B30` + `exclamationmark.triangle.fill`
///   (Apple HIG urgent/destructive).
/// - `.dueToday`, `.dueTomorrow`, `.dueFuture` → system orange `#FF9500`
///   + `bell.fill` (warning). The reviewer asked us not to add a third
///   "due today" color — orange stays consistent across all non-overdue
///   futures; the relative-date label inside the chip already
///   distinguishes "Today at 3:00 PM" vs "Tomorrow at 9:00 AM" vs the
///   absolute date.
///
/// `DeadlineChip` derives this from `dueAt + now` inside a `TimelineView`
/// so the chip flips to `.overdue` the minute the deadline passes,
/// without callers having to subscribe to a timer.
enum DeadlineChipUrgency: Sendable, Equatable {
  /// `dueAt < now`. Chip tints red and uses the warning-triangle glyph.
  case overdue

  /// `dueAt` falls inside `[startOfToday, endOfToday)`. Chip stays
  /// orange + bell. Documented separately from `.dueFuture` because the
  /// urgency-computation tests assert this case explicitly — even though
  /// today renders the same as a more distant future, the *concept* is
  /// distinct (the user has hours, not days).
  case dueToday

  /// `dueAt` falls inside the calendar day immediately after today.
  /// Orange + bell, same render as `.dueFuture`.
  case dueTomorrow

  /// `dueAt > endOfTomorrow`. Orange + bell. Anything farther out — the
  /// chip's relative-date label carries the day specificity.
  case dueFuture

  /// Compute urgency from a deadline against a reference time. Pure;
  /// covered by `DeadlineChipUrgencyTests`. The optional `calendar`
  /// parameter lets tests pin to a fixed calendar/timezone — production
  /// callers should use the default `.current`.
  static func from(
    dueAt: Date,
    now: Date,
    calendar: Calendar = .current
  ) -> DeadlineChipUrgency {
    if dueAt < now { return .overdue }
    let startOfToday = calendar.startOfDay(for: now)
    guard let startOfTomorrow = calendar.date(
      byAdding: .day,
      value: 1,
      to: startOfToday
    ) else {
      // Should never happen with a sane calendar, but if it does, treat
      // "today" as the only same-day bucket and fall through.
      return dueAt < startOfToday.addingTimeInterval(86_400) ? .dueToday : .dueFuture
    }
    guard let startOfDayAfter = calendar.date(
      byAdding: .day,
      value: 2,
      to: startOfToday
    ) else {
      return dueAt < startOfTomorrow ? .dueToday : .dueTomorrow
    }
    if dueAt < startOfTomorrow { return .dueToday }
    if dueAt < startOfDayAfter { return .dueTomorrow }
    return .dueFuture
  }
}
