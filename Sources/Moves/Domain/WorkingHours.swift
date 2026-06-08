import Foundation

/// One global "working hours" window (INITIAL-PLAN §6). Not a context system —
/// it's a decluttering tool that drives `ThreadVisibility` policies on the
/// Available list.
///
/// Stored as JSON in the `settings` table under key `working_hours` with shape:
///
///   {
///     "days": [1, 2, 3, 4, 5],   // 1 = Monday, 7 = Sunday (ISO-8601)
///     "start": "09:00",          // 24h, local time
///     "end":   "17:30"           // 24h, local time
///   }
///
/// A window that wraps midnight (start > end) is supported — interpreted as
/// "from start through end-of-day, plus midnight through end". Both endpoints
/// are inclusive of the start minute and exclusive of the end minute, so
/// 09:00–17:00 means [09:00, 17:00).
struct WorkingHours: Hashable, Sendable, Codable {
  /// ISO-8601 weekdays (1 = Monday, ..., 7 = Sunday). Empty means
  /// "no working hours" — every time of day is non-work.
  var days: Set<Int>
  /// Minute-of-day [0, 1440).
  var startMinute: Int
  var endMinute: Int

  init(days: Set<Int>, startMinute: Int, endMinute: Int) {
    self.days = days
    self.startMinute = max(0, min(1439, startMinute))
    self.endMinute = max(0, min(1440, endMinute))
  }

  /// Default — Monday–Friday, 09:00–17:30. Matches the §6 example.
  static let `default` = WorkingHours(
    days: [1, 2, 3, 4, 5],
    startMinute: 9 * 60,
    endMinute: 17 * 60 + 30
  )

  // MARK: - JSON (settings table payload)

  /// The DTO shape stored in the `settings` table. `start` and `end` are
  /// `"HH:mm"` strings so the row is human-readable in a SQLite browser.
  private struct DTO: Codable {
    var days: [Int]
    var start: String
    var end: String
  }

  private static let formatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "HH:mm"
    return f
  }()

  static func formatMinute(_ minute: Int) -> String {
    let clamped = max(0, min(1440, minute))
    let h = clamped / 60
    let m = clamped % 60
    return String(format: "%02d:%02d", h, m)
  }

  static func parseMinute(_ s: String) -> Int? {
    let parts = s.split(separator: ":")
    guard parts.count == 2,
          let h = Int(parts[0]),
          let m = Int(parts[1]),
          (0...24).contains(h),
          (0...59).contains(m)
    else { return nil }
    return h * 60 + m
  }

  /// Encode to the JSON value stored in `settings`. Always succeeds.
  func encodedJSON() -> String {
    let dto = DTO(
      days: days.sorted(),
      start: Self.formatMinute(startMinute),
      end: Self.formatMinute(endMinute)
    )
    let data = (try? JSONEncoder().encode(dto)) ?? Data("{}".utf8)
    return String(data: data, encoding: .utf8) ?? "{}"
  }

  /// Best-effort decode. Returns nil on any malformed input — callers fall
  /// back to `.default`.
  static func decodedJSON(_ json: String) -> WorkingHours? {
    guard let data = json.data(using: .utf8),
          let dto = try? JSONDecoder().decode(DTO.self, from: data),
          let start = parseMinute(dto.start),
          let end = parseMinute(dto.end)
    else { return nil }
    return WorkingHours(days: Set(dto.days), startMinute: start, endMinute: end)
  }
}

/// Static labels for the ISO weekday integers — used by the Settings UI.
enum WorkingHoursWeekday: Int, CaseIterable, Sendable {
  case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

  var shortLabel: String {
    switch self {
    case .monday: return "Mon"
    case .tuesday: return "Tue"
    case .wednesday: return "Wed"
    case .thursday: return "Thu"
    case .friday: return "Fri"
    case .saturday: return "Sat"
    case .sunday: return "Sun"
    }
  }
}
