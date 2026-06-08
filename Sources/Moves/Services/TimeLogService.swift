import Foundation

/// Pure projections over `TimeLogEntry` rows for INITIAL-PLAN.md §14's
/// weekly rough-time view.
///
/// The repository owns the rows; this service does not touch SQLite. Keep
/// it deterministic and Calendar-injectable so the tests can pin a fixture
/// week and assert byte-stable strings.
enum TimeLogService {

  /// `YYYY-MM-DD` for the Monday of the ISO week containing `date`.
  ///
  /// ISO-8601 weeks (Monday-start, `firstWeekday = 2`). Matches the value
  /// `AppStore.weekStartString(for:)` writes to `time_log.week_start` so a
  /// fresh log row joins back to the same bucket via string equality.
  static func weekStart(for date: Date, calendar: Calendar = .iso8601Monday) -> String {
    let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    let monday = calendar.date(from: components) ?? date
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = calendar.timeZone
    return formatter.string(from: monday)
  }

  /// Sum `roughMinutes` per thread. Result is ordered by descending total
  /// (largest aggregates first); ties break on threadId ASC for stability so
  /// the view doesn't re-shuffle across renders.
  ///
  /// Threads with zero matching entries are absent from the result — the
  /// caller decides whether to render an empty row.
  static func aggregate(entries: [TimeLogEntry]) -> [ThreadAggregate] {
    var sums: [String: Int] = [:]
    for entry in entries {
      sums[entry.threadId, default: 0] += entry.roughMinutes
    }
    return sums
      .map { ThreadAggregate(threadId: $0.key, totalMinutes: $0.value) }
      .sorted { lhs, rhs in
        if lhs.totalMinutes != rhs.totalMinutes { return lhs.totalMinutes > rhs.totalMinutes }
        return lhs.threadId < rhs.threadId
      }
  }

  /// "~3h", "~45m", "~1h 30m" — the §14 display format. Rounds to the rough
  /// buckets the user already understands.
  ///
  /// Rules:
  ///   - 0 minutes → "0m" (caller usually filters before calling).
  ///   - < 60 minutes → "~Nm" using 15-minute granularity (15 / 30 / 45 / 60).
  ///   - >= 60 and a whole-hour multiple → "~Nh".
  ///   - >= 60 with leftover minutes → "~Hh Mm" with minutes rounded to 15.
  static func roughBucketLabel(_ minutes: Int) -> String {
    guard minutes > 0 else { return "0m" }
    if minutes < 60 {
      let rounded = roundToFifteen(minutes)
      return "~\(rounded)m"
    }
    let hours = minutes / 60
    let leftover = minutes % 60
    if leftover == 0 {
      return "~\(hours)h"
    }
    let roundedLeftover = roundToFifteen(leftover)
    if roundedLeftover == 0 { return "~\(hours)h" }
    if roundedLeftover == 60 { return "~\(hours + 1)h" }
    return "~\(hours)h \(roundedLeftover)m"
  }

  /// Round UP to the nearest multiple of 15, clamped to [0, 60]. Round-up
  /// matches the §14 chip semantics ("rough time spent" — 20 minutes reads
  /// as "~30m", not "~15m"). Aligns with the bucket labels the user sees
  /// in the rough-time picker.
  private static func roundToFifteen(_ minutes: Int) -> Int {
    let r = ((minutes + 14) / 15) * 15
    return max(0, min(60, r))
  }
}

extension Calendar {
  /// ISO-8601, Monday-first. Used for week_start string formatting so the
  /// app and tests agree on the week boundary.
  static let iso8601Monday: Calendar = {
    var cal = Calendar(identifier: .iso8601)
    cal.firstWeekday = 2
    return cal
  }()
}
