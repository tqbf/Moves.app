import Foundation

/// Stable identifiers for SwiftUI scenes that host Phase-3 flows. Centralized
/// so the popover and `MovesApp` can't drift on raw strings (renaming an
/// enum case becomes a compile error instead of a runtime miss).
enum PopoverWindowID: String {
  case stop = "flow-stop"
  case switchFlow = "flow-switch"
  case park = "flow-park"
  case parkingLot = "parking-lot"
  case main = "main"
  /// Phase-5: explicit segment-completion sheet (§5.5). Hosted as its own
  /// Window for the same reason as Stop/Switch/Park — the popover
  /// auto-dismisses on focus loss and would kill a SwiftUI `.sheet`.
  case completeSegment = "flow-complete-segment"
  /// Phase-5: Markdown import preview sheet (§9). Hosted as its own Window
  /// so the user can drag a file from Finder onto it without the popover
  /// dismissing under them.
  case importMarkdown = "import-markdown"
  /// Phase-6: first-launch onboarding modal. Window scene so the menubar
  /// popover doesn't kill it on focus loss; re-runnable from Settings.
  case onboarding = "onboarding"
}
