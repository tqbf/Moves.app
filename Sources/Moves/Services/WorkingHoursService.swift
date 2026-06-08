import Foundation

/// Pure decision logic for "is `date` inside working hours?" plus the §6
/// visibility filter applied to the Available list. Stateless — the caller
/// (the `AppStore`) owns the `WorkingHours` config and decides when to
/// recompute.
///
/// The §6 policy:
///   - `normal`            — always shown
///   - `hide_during_work`  — hidden during working hours, *unless* the thread
///                            has a deadline-bearing item
///   - `downweight_during_work` — shown in the de-emphasized group during
///                                 working hours
///   - `only_during_work`  — shown only during working hours, unless the
///                            thread has a deadline-bearing item
///
/// "Deadline-bearing" means the thread has at least one open item with a
/// non-nil `due_at` (per §6's "unless deadline-bearing" carve-out and §12's
/// "deadline-bearing first" priority).
enum WorkingHoursService {

  /// True if `date` is inside `hours`'s window. ISO-8601 weekday match plus
  /// a minute-of-day range check (start-inclusive, end-exclusive). Handles
  /// midnight-wrap when `startMinute > endMinute`.
  static func isInside(date: Date, hours: WorkingHours, calendar: Calendar = Calendar(identifier: .iso8601)) -> Bool {
    var cal = calendar
    cal.firstWeekday = 2 // Monday — ISO-8601
    let components = cal.dateComponents([.weekday, .hour, .minute], from: date)
    // Calendar.Component.weekday returns 1 = Sunday, ..., 7 = Saturday.
    // We want ISO-8601: 1 = Monday, ..., 7 = Sunday.
    let isoWeekday = ((components.weekday ?? 1) + 5) % 7 + 1
    guard hours.days.contains(isoWeekday) else { return false }

    let minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)

    if hours.startMinute == hours.endMinute {
      // Zero-length window — never inside.
      return false
    }
    if hours.startMinute < hours.endMinute {
      return minuteOfDay >= hours.startMinute && minuteOfDay < hours.endMinute
    }
    // Wraps midnight: in if at-or-after start OR before end.
    return minuteOfDay >= hours.startMinute || minuteOfDay < hours.endMinute
  }

  /// Visibility classification for one thread under the current working-hours
  /// regime. `Visible` = render in the normal section; `Deemphasized` =
  /// render in the muted "during working hours" section; `Hidden` = drop
  /// from Available entirely.
  enum Classification: Hashable, Sendable {
    case visible
    case deemphasized
    case hidden
  }

  /// Apply §6 to one (thread, has-deadline?) pair against the current work
  /// state. Stateless and called per row by `filter(...)`.
  static func classify(
    visibility: ThreadVisibility,
    isWorkTime: Bool,
    hasDeadlineItem: Bool
  ) -> Classification {
    switch visibility {
    case .normal:
      return .visible
    case .hideWork:
      // Hidden during working hours unless deadline-bearing.
      if isWorkTime, !hasDeadlineItem { return .hidden }
      return .visible
    case .downweightWork:
      // Shown in the de-emphasized section during working hours.
      return isWorkTime ? .deemphasized : .visible
    case .onlyWork:
      // Shown only during working hours, unless deadline-bearing.
      if isWorkTime { return .visible }
      if hasDeadlineItem { return .visible }
      return .hidden
    }
  }

  /// Result of running the filter over an Available projection — two
  /// ordered lists, preserving input order. The caller renders them in
  /// `Available` then `De-emphasized during working hours`.
  struct FilteredAvailable: Hashable, Sendable {
    var visible: [AvailableThread]
    var deemphasized: [AvailableThread]
  }

  /// Apply the §6 visibility policy to an Available projection. `hasDeadline`
  /// is invoked per row so the caller can keep the open-item lookup outside
  /// this pure layer.
  static func filter(
    available: [AvailableThread],
    isWorkTime: Bool,
    hasDeadline: (AvailableThread) -> Bool
  ) -> FilteredAvailable {
    var visible: [AvailableThread] = []
    var deemphasized: [AvailableThread] = []
    for row in available {
      let cls = classify(
        visibility: row.thread.visibility,
        isWorkTime: isWorkTime,
        hasDeadlineItem: hasDeadline(row)
      )
      switch cls {
      case .visible:
        visible.append(row)
      case .deemphasized:
        deemphasized.append(row)
      case .hidden:
        break
      }
    }
    return FilteredAvailable(visible: visible, deemphasized: deemphasized)
  }
}
