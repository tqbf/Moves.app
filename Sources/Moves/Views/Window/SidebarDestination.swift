import Foundation

/// Top-level destinations in the main-window sidebar (INITIAL-PLAN §4.2).
/// The §4.2 list — Available, Current, Threads, Captured, Deadlines, Parking
/// Lot — is the canonical surface; we also carry an extra case for
/// "specific thread selected from the Threads list" so the same
/// `NavigationSplitView` selection model drives every detail pane.
///
/// Settings is intentionally NOT a sidebar destination. It lives on the
/// system Settings scene (Cmd-, / Moves → Settings…) per macOS convention.
enum SidebarDestination: Hashable, Sendable {
  case available
  case current
  case threadsList
  case thread(String)
  case captured
  case deadlines
  case parkingLot
  /// Phase 5: §14 weekly rough-time aggregation pane. Sums `time_log` rows
  /// for the active ISO week, with prev/next navigation.
  case timeLog
}
