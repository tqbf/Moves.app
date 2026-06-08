import Foundation

/// The seven rough-time buckets from INITIAL-PLAN §14. These are the *only*
/// time values the app stores — there is no precise timer. Used by Stop /
/// Switch sheets (Phase 3) and segment-completion (Phase 5).
///
/// `none` means "the user explicitly said don't record" and skips the
/// `time_log` write — distinct from "I forgot to fill it in" (which is
/// impossible because the picker defaults to a real bucket when shown).
enum RoughTimeBucket: String, CaseIterable, Hashable, Sendable {
  case none
  case m15
  case m30
  case m45
  case h1
  case h2
  case h3plus

  /// Rough minute count for the `time_log.rough_minutes` column. `nil` for
  /// `.none` — the caller should skip the insert.
  var minutes: Int? {
    switch self {
    case .none: return nil
    case .m15: return 15
    case .m30: return 30
    case .m45: return 45
    case .h1: return 60
    case .h2: return 120
    case .h3plus: return 180
    }
  }

  /// Chip label shown in the `RoughTimePicker` row.
  var label: String {
    switch self {
    case .none: return "none"
    case .m15: return "15m"
    case .m30: return "30m"
    case .m45: return "45m"
    case .h1: return "1h"
    case .h2: return "2h"
    case .h3plus: return "3h+"
    }
  }
}
