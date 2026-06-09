import Foundation

/// Pure formatter for an elapsed-time interval rendered next to the Current
/// card's title.
///
/// Format rules (matches the UI glow-up brief — items 10–11):
///   - 0s              → `"00:00"`
///   - 16s             → `"00:16"`
///   - 75s             → `"01:15"`
///   - 1 hour or more  → `"H:MM:SS"` (e.g. `3661s` → `"01:01:01"`)
///
/// Negative intervals clamp to zero — the started-at timestamp can briefly
/// be ahead of `Date.now` during clock drift or right after a Switch when
/// the row writes its own start time.
///
/// Lives next to `RowSubtitle` as a pure helper so the elapsed label can
/// be unit-tested without a SwiftUI host, and so any caller (the popover
/// Current section, the main-window Current detail) shares one rendering.
enum ElapsedTime {

  /// Render `interval` (seconds) as `mm:ss` for sub-hour values and
  /// `hh:mm:ss` for one hour or more. Zero-padded everywhere so the label
  /// width stays stable for `.monospacedDigit()` callers.
  static func format(_ interval: TimeInterval) -> String {
    let clamped = max(0, Int(interval.rounded(.down)))
    let hours = clamped / 3600
    let minutes = (clamped % 3600) / 60
    let seconds = clamped % 60
    if hours > 0 {
      return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
  }
}
