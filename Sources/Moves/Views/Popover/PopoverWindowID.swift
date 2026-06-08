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
}
