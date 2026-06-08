import Foundation

/// Deterministic capture-string parser. The grammar is intentionally tiny —
/// every form is listed in INITIAL-PLAN.md §15. There is no fuzzy matching,
/// no LLM, and no "tonight"/"this weekend" — those are v2 candidates.
///
/// Recognized forms (case-insensitive, trailing whitespace ignored):
///
///   * `… in <N>m` / `in <N>h`         → relative; hard; datetime
///   * `… at <H>` / `at <H>pm`         → next clock time; hard; datetime
///   * `… tomorrow`                    → tomorrow 00:00; soft; date
///   * `… tomorrow <H>` / `… tomorrow <H>am` / `tomorrow <H>:<M>pm`
///                                     → tomorrow at time; soft; datetime
///   * `… <weekday>`                   → next weekday 00:00; soft; date
///   * `… <weekday> <H>pm`             → next weekday at time; soft; datetime
///   * `… due <…>` / `… by <…>`        → same as the rhs form, but soft
///   * `… YYYY-MM-DD`                  → that date 00:00; soft; date
///   * `… YYYY-MM-DD HH:MM`            → that datetime; soft; datetime
///   * no match                        → no `due_at`; interruption `.none`
///
/// The trailing date phrase is stripped from the title. Tokens are matched
/// against the *suffix* only — "due" or "by" mid-title without a real date
/// phrase after it doesn't trigger soft-mode. See tests for every example
/// in §15.
struct ParsedCapture: Equatable, Sendable {
  var title: String
  var dueAt: Date?
  var dueKind: DueKind
  var interruptionKind: InterruptionKind
}

enum CaptureParser {

  /// Parse a single capture line as of `now`. Pure; no clock reads.
  static func parse(_ input: String, now: Date, calendar: Calendar = .autoupdatingCurrent) -> ParsedCapture {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return ParsedCapture(title: "", dueAt: nil, dueKind: .none, interruptionKind: .none)
    }

    // Tokenize on whitespace. Tokens keep their original spelling for the
    // title path; matchers compare against lowercased copies.
    let tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    let lower = tokens.map { $0.lowercased() }

    // Try every recognized suffix-pattern. Each returns a (tokensConsumed,
    // dueAt, dueKind, defaultInterruption) tuple — defaultInterruption is the
    // *intrinsic* kind for the pattern, before `due`/`by` overrides apply.
    if let match = matchSuffix(tokens: tokens, lower: lower, now: now, calendar: calendar) {
      let titleTokens = tokens.prefix(tokens.count - match.consumed)
      let title = titleTokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
      return ParsedCapture(
        title: title,
        dueAt: match.dueAt,
        dueKind: match.dueKind,
        interruptionKind: match.interruptionKind
      )
    }

    return ParsedCapture(
      title: trimmed,
      dueAt: nil,
      dueKind: .none,
      interruptionKind: .none
    )
  }

  // MARK: - Suffix matching

  /// A successful suffix match.
  private struct SuffixMatch {
    let consumed: Int
    let dueAt: Date
    let dueKind: DueKind
    let interruptionKind: InterruptionKind
  }

  /// Walk the longest-possible suffix patterns first. Order matters — `due
  /// friday 5pm` must beat bare `5pm` etc.
  private static func matchSuffix(
    tokens: [String],
    lower: [String],
    now: Date,
    calendar: Calendar
  ) -> SuffixMatch? {
    let n = tokens.count

    // ---- `due …` / `by …` prefix on the date phrase → force soft. ----
    // We look for "due" or "by" as a non-final token, then re-parse the
    // remainder as the bare form and convert it to soft.
    for split in 0..<n {
      let head = lower[split]
      guard head == "due" || head == "by" else { continue }
      let restLower = Array(lower[(split + 1)...])
      let restTokens = Array(tokens[(split + 1)...])
      guard !restLower.isEmpty else { continue }
      if let inner = matchBareSuffix(tokens: restTokens, lower: restLower, now: now, calendar: calendar),
         inner.consumed == restLower.count {
        // Whole rest of the string was a recognized date phrase. Consume it
        // plus the `due`/`by` keyword. Force soft.
        return SuffixMatch(
          consumed: (n - split),
          dueAt: inner.dueAt,
          dueKind: inner.dueKind,
          interruptionKind: .soft
        )
      }
    }

    // ---- Bare date phrase as the trailing tokens. ----
    return matchBareSuffix(tokens: tokens, lower: lower, now: now, calendar: calendar)
  }

  /// Try every bare (no `due`/`by` keyword) suffix pattern, longest first.
  /// "Bare" patterns set their own intrinsic interruption kind (hard for
  /// `in`/`at`, soft for date/weekday/tomorrow). `due`/`by` override to soft
  /// at the call site.
  private static func matchBareSuffix(
    tokens: [String],
    lower: [String],
    now: Date,
    calendar: Calendar
  ) -> SuffixMatch? {
    let n = tokens.count

    // Try each starting position from earliest (longest suffix) to latest
    // (shortest). Return the longest match.
    for start in 0..<n {
      let head = lower[start]
      let remaining = Array(lower[(start + 1)...])

      // `in <N>m` / `in <N>h` (exactly 2 tokens)
      if head == "in", remaining.count == 1, let off = parseRelativeOffset(remaining[0]) {
        let due = now.addingTimeInterval(TimeInterval(off))
        return SuffixMatch(consumed: n - start, dueAt: due, dueKind: .datetime, interruptionKind: .hard)
      }

      // `at <H>` / `at <H>pm` / `at <H>:<M>` / `at <H>:<M>pm` (exactly 2 tokens)
      if head == "at", remaining.count == 1, let clock = parseClockTime(remaining[0]) {
        let due = nextClockOccurrence(of: clock, after: now, calendar: calendar)
        return SuffixMatch(consumed: n - start, dueAt: due, dueKind: .datetime, interruptionKind: .hard)
      }

      // `tomorrow` (exactly 1 token)
      if head == "tomorrow", remaining.isEmpty {
        let due = startOfTomorrow(after: now, calendar: calendar)
        return SuffixMatch(consumed: n - start, dueAt: due, dueKind: .date, interruptionKind: .soft)
      }

      // `tomorrow <H[am|pm]>` (exactly 2 tokens)
      if head == "tomorrow", remaining.count == 1, let clock = parseClockTime(remaining[0]) {
        let due = combine(date: startOfTomorrow(after: now, calendar: calendar), with: clock, calendar: calendar)
        return SuffixMatch(consumed: n - start, dueAt: due, dueKind: .datetime, interruptionKind: .soft)
      }

      // `<weekday>` (exactly 1 token)
      if remaining.isEmpty, let weekday = parseWeekday(head) {
        let day = nextWeekdayStart(weekday: weekday, after: now, calendar: calendar)
        return SuffixMatch(consumed: n - start, dueAt: day, dueKind: .date, interruptionKind: .soft)
      }

      // `<weekday> <H[am|pm]>` (exactly 2 tokens)
      if remaining.count == 1, let weekday = parseWeekday(head), let clock = parseClockTime(remaining[0]) {
        let day = nextWeekdayStart(weekday: weekday, after: now, calendar: calendar)
        let due = combine(date: day, with: clock, calendar: calendar)
        return SuffixMatch(consumed: n - start, dueAt: due, dueKind: .datetime, interruptionKind: .soft)
      }

      // `YYYY-MM-DD` (exactly 1 token)
      if remaining.isEmpty, let date = parseISODate(head, calendar: calendar) {
        return SuffixMatch(consumed: n - start, dueAt: date, dueKind: .date, interruptionKind: .soft)
      }

      // `YYYY-MM-DD HH:MM` (exactly 2 tokens)
      if remaining.count == 1,
         let date = parseISODate(head, calendar: calendar),
         let clock = parseClockTime(remaining[0]),
         clock.hadExplicitMinutes
      {
        let due = combine(date: date, with: clock, calendar: calendar)
        return SuffixMatch(consumed: n - start, dueAt: due, dueKind: .datetime, interruptionKind: .soft)
      }
    }

    return nil
  }

  // MARK: - Atomic parsers

  /// Match `<N>m` / `<N>h`. Returns the offset in seconds.
  private static func parseRelativeOffset(_ token: String) -> Int? {
    guard token.count >= 2 else { return nil }
    let unit = token.last!
    let numberPart = String(token.dropLast())
    guard let value = Int(numberPart), value > 0 else { return nil }
    switch unit {
    case "m": return value * 60
    case "h": return value * 3600
    default: return nil
    }
  }

  /// A clock-time intent: hour + optional minute + optional am/pm. Used both
  /// for `at <H>` style ("next occurrence") and for date-bound times
  /// ("tomorrow 9am", "Friday 5pm", "2026-06-12 17:00").
  struct ClockTime: Equatable {
    var hour: Int       // 0...23 if am/pm specified or hadExplicitMinutes, else 1...12
    var minute: Int     // 0...59
    var amPm: AmPm?     // nil → ambiguous (e.g. "at 4") OR explicit 24-hour ("17:00")
    var hadExplicitMinutes: Bool
    var hadAmPm: Bool { amPm != nil }
  }

  enum AmPm: Equatable { case am, pm }

  /// Parse a clock-time token: `4`, `4pm`, `4:30`, `4:30pm`, `09`, `17:00`, `9am`.
  private static func parseClockTime(_ token: String) -> ClockTime? {
    var rest = token
    var amPm: AmPm?
    if rest.hasSuffix("am") {
      amPm = .am
      rest = String(rest.dropLast(2))
    } else if rest.hasSuffix("pm") {
      amPm = .pm
      rest = String(rest.dropLast(2))
    }

    let pieces = rest.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    guard pieces.count == 1 || pieces.count == 2 else { return nil }

    guard let rawHour = Int(pieces[0]) else { return nil }
    let rawMinute: Int
    let hadMinutes: Bool
    if pieces.count == 2 {
      guard let m = Int(pieces[1]), pieces[1].count == 2, (0...59).contains(m) else { return nil }
      rawMinute = m
      hadMinutes = true
    } else {
      rawMinute = 0
      hadMinutes = false
    }

    if amPm != nil {
      guard (1...12).contains(rawHour) else { return nil }
      return ClockTime(hour: rawHour, minute: rawMinute, amPm: amPm, hadExplicitMinutes: hadMinutes)
    }

    // No am/pm. If explicit minutes (e.g. "17:00"), interpret as 24-hour.
    if hadMinutes {
      guard (0...23).contains(rawHour) else { return nil }
      return ClockTime(hour: rawHour, minute: rawMinute, amPm: nil, hadExplicitMinutes: true)
    }

    // Bare integer like "4". Only meaningful for "at 4" (ambiguous → next
    // 4:00). Restrict to 1...12 — a bare "23" would just be noise here.
    guard (1...12).contains(rawHour) else { return nil }
    return ClockTime(hour: rawHour, minute: 0, amPm: nil, hadExplicitMinutes: false)
  }

  /// Return the next absolute moment matching this clock time after `now`.
  /// For ambiguous bare hours (`at 4`), this is the next occurrence on a
  /// 12-hour clock (so 4am or 4pm, whichever is next).
  private static func nextClockOccurrence(of clock: ClockTime, after now: Date, calendar: Calendar) -> Date {
    if clock.hadAmPm || clock.hadExplicitMinutes {
      let hour24 = canonical24Hour(clock)
      return nextDate(hour: hour24, minute: clock.minute, after: now, calendar: calendar)
    }
    // Ambiguous bare hour. Try both 12-hour candidates; pick the earliest
    // strictly after `now`.
    let amHour = clock.hour == 12 ? 0 : clock.hour
    let pmHour = clock.hour == 12 ? 12 : clock.hour + 12
    let am = nextDate(hour: amHour, minute: clock.minute, after: now, calendar: calendar)
    let pm = nextDate(hour: pmHour, minute: clock.minute, after: now, calendar: calendar)
    return min(am, pm)
  }

  /// Convert a (possibly am/pm-tagged) ClockTime into a 24-hour hour value.
  private static func canonical24Hour(_ clock: ClockTime) -> Int {
    switch clock.amPm {
    case .am: return clock.hour == 12 ? 0 : clock.hour
    case .pm: return clock.hour == 12 ? 12 : clock.hour + 12
    case .none: return clock.hour
    }
  }

  /// Next absolute moment at the given hour/minute strictly after `now`. If
  /// today's H:M is in the future, returns today's; otherwise tomorrow's.
  private static func nextDate(hour: Int, minute: Int, after now: Date, calendar: Calendar) -> Date {
    var components = calendar.dateComponents([.year, .month, .day], from: now)
    components.hour = hour
    components.minute = minute
    components.second = 0
    let candidate = calendar.date(from: components) ?? now
    if candidate > now {
      return candidate
    }
    return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
  }

  // MARK: - Date pieces

  /// Match `monday`...`sunday` (case-insensitive). Returns Calendar weekday
  /// (1 = Sunday, 7 = Saturday).
  private static func parseWeekday(_ token: String) -> Int? {
    switch token {
    case "sunday": return 1
    case "monday": return 2
    case "tuesday": return 3
    case "wednesday": return 4
    case "thursday": return 5
    case "friday": return 6
    case "saturday": return 7
    default: return nil
    }
  }

  /// Start of the next occurrence of `weekday` strictly after `now`. "Next
  /// Friday" when today is Friday means seven days from now, not today —
  /// matches the grammar's "next occurrence of that weekday".
  private static func nextWeekdayStart(weekday target: Int, after now: Date, calendar: Calendar) -> Date {
    let today = calendar.component(.weekday, from: now)
    var delta = (target - today + 7) % 7
    if delta == 0 { delta = 7 }
    let startOfToday = calendar.startOfDay(for: now)
    return calendar.date(byAdding: .day, value: delta, to: startOfToday) ?? startOfToday
  }

  /// Start-of-day for tomorrow.
  private static func startOfTomorrow(after now: Date, calendar: Calendar) -> Date {
    let startOfToday = calendar.startOfDay(for: now)
    return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
  }

  /// Combine a date (start-of-day) with a ClockTime, returning the absolute
  /// moment. Used for "tomorrow 9am", "Friday 5pm", "2026-06-12 17:00".
  private static func combine(date: Date, with clock: ClockTime, calendar: Calendar) -> Date {
    let hour = canonical24Hour(clock)
    var components = calendar.dateComponents([.year, .month, .day], from: date)
    components.hour = hour
    components.minute = clock.minute
    components.second = 0
    return calendar.date(from: components) ?? date
  }

  /// Match `YYYY-MM-DD`. Returns start-of-day in the supplied calendar.
  private static func parseISODate(_ token: String, calendar: Calendar) -> Date? {
    let parts = token.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    guard parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return nil }
    guard
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2]),
      (1...12).contains(month),
      (1...31).contains(day)
    else { return nil }
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = 0
    components.minute = 0
    components.second = 0
    guard let date = calendar.date(from: components) else { return nil }
    // Reject silent rollovers (e.g. 2026-02-30 → March). Round-trip the
    // calendar fields and require them to match what we asked for.
    let check = calendar.dateComponents([.year, .month, .day], from: date)
    guard check.year == year, check.month == month, check.day == day else { return nil }
    return date
  }
}
