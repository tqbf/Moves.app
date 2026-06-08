import Foundation

/// Top-level destinations in the main-window sidebar (INITIAL-PLAN §4.2).
/// The §4.2 list — Available, Current, Threads, Captured, Deadlines, Parking
/// Lot, Settings — is the canonical surface; we also carry an extra case
/// for "specific thread selected from the Threads list" so the same
/// `NavigationSplitView` selection model drives every detail pane.
enum SidebarDestination: Hashable, Sendable {
  case available
  case current
  case threadsList
  case thread(String)
  case captured
  case deadlines
  case parkingLot
  case settings
}
