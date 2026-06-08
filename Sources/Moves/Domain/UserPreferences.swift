import Foundation

/// User-facing preferences that drive Phase-6 settings additions:
///
///   - **Default alert offsets** per item kind (reminder vs deadline-task).
///     INITIAL-PLAN §8.3 documented configurable offsets but v1 only shipped
///     the "at due time" default. The shape stores integer minutes-before-
///     due; positive values fire before due, zero fires at due.
///   - **Badge enable/disable.** When false, the menubar `•N` suffix and
///     the popover header's `•N due` chip are suppressed. The DB query
///     still runs (it's cheap), so the toggle is purely render-time.
///   - **Onboarded version.** Set after the user finishes the onboarding
///     flow. Future versions can bump this string to retrigger an updated
///     onboarding pass.
///
/// Persisted as a JSON blob under the `user_preferences` settings key. Old
/// builds without the key fall back to `.default` (badge on, no alert
/// offsets stored). The struct is value-typed + Codable for trivial
/// round-trip; tests assert encode/decode stability.
struct UserPreferences: Equatable, Sendable, Codable {

  // MARK: - Alert offsets

  /// Minutes-before-due offsets for `kind = .reminder` items. v1 default:
  /// `[0]` (one notification at due time).
  var reminderOffsetsMinutes: [Int]
  /// Minutes-before-due offsets for items with `kind = .task` AND a
  /// non-nil `due_at` — UI labels these "deadline tasks" per §8.3.
  /// v1 default: `[24*60, 60, 0]` (morning-of, 1 hour before, at due time).
  /// "Morning of" is approximated as 1 day before; future work can promote
  /// this to a clock-time-of-day setting.
  var deadlineTaskOffsetsMinutes: [Int]

  // MARK: - Badge

  /// Render-time toggle for the menubar `•N` badge and the popover header
  /// `•N due` chip. Default: true.
  var badgeEnabled: Bool

  // MARK: - Onboarding

  /// `nil` until the user finishes onboarding. Future versions can compare
  /// against the current bundled onboarding version.
  var onboardedVersion: String?

  // MARK: - Defaults

  static let `default` = UserPreferences(
    reminderOffsetsMinutes: [0],
    deadlineTaskOffsetsMinutes: [24 * 60, 60, 0],
    badgeEnabled: true,
    onboardedVersion: nil
  )

  /// Current onboarding version. Bump when the onboarding flow changes
  /// materially enough that returning users should see it again.
  static let currentOnboardingVersion = "1.0"

  // MARK: - Codable

  /// Decode from the persisted JSON. Missing keys fall back to defaults so
  /// older shapes survive a v1 → v1.x upgrade without losing the badge
  /// preference.
  static func decodedJSON(_ json: String) -> UserPreferences? {
    guard let data = json.data(using: .utf8) else { return nil }
    let decoder = JSONDecoder()
    if let decoded = try? decoder.decode(UserPreferences.self, from: data) {
      return decoded
    }
    // Best-effort decode of a partial blob: use defaults for anything
    // missing. Lets a future release add a key without breaking older DBs.
    if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      var defaults = UserPreferences.default
      if let r = obj["reminderOffsetsMinutes"] as? [Int] { defaults.reminderOffsetsMinutes = r }
      if let d = obj["deadlineTaskOffsetsMinutes"] as? [Int] { defaults.deadlineTaskOffsetsMinutes = d }
      if let b = obj["badgeEnabled"] as? Bool { defaults.badgeEnabled = b }
      if let v = obj["onboardedVersion"] as? String { defaults.onboardedVersion = v }
      return defaults
    }
    return nil
  }

  func encodedJSON() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(self)
    return String(data: data, encoding: .utf8) ?? "{}"
  }
}

/// Convenience labels for the alert-offset editor in Settings.
enum AlertOffsetLabel {
  /// Human-readable label like "at due time", "1h before", "morning of".
  /// "Morning of" maps to 24*60; other day-multiples render as "1d", "2d".
  static func describe(minutes: Int) -> String {
    if minutes == 0 { return "at due time" }
    if minutes == 24 * 60 { return "morning of" }
    if minutes < 60 { return "\(minutes)m before" }
    if minutes < 24 * 60 {
      let hours = minutes / 60
      let rest = minutes % 60
      if rest == 0 { return "\(hours)h before" }
      return "\(hours)h \(rest)m before"
    }
    let days = minutes / (24 * 60)
    let rest = minutes % (24 * 60)
    if rest == 0 { return "\(days)d before" }
    return "\(days)d \(rest)m before"
  }
}
