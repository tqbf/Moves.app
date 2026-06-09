import SwiftUI

/// Single source of truth for the layout grid every top-level pane shares
/// (INITIAL-PLAN §4.2). Before this, each pane was free-styling its own
/// `.padding(.horizontal, 28)` / `listRowInsets(... leading: 20 ...)` /
/// card padding — Available started near x≈390, Current's card sat farther
/// right, Threads had its own indent. The visual reviewer flagged it as
/// the single biggest "feels unfinished" tell across the app. The fix is
/// to encode the grid in one place and route every pane through it.
///
/// Numbers are picked to match the macOS inset-list defaults Mail and
/// Reminders use — the pane title aligns with the row text leading, and
/// the inspector rail width matches the right-hand inspector in Notes /
/// Mail's "Show Details" panel.
enum PaneMetrics {
  /// Outer leading/trailing padding around pane chrome (title, footer,
  /// card content). Lists handle their own leading via `listRowInsets`
  /// using the same value so non-list chrome and list rows share a
  /// vertical grid line.
  static let horizontalInset: CGFloat = 24

  /// Top padding under the window toolbar before the pane title row.
  /// Matches the macOS "first content row sits 16pt below the toolbar"
  /// spacing in Mail / Reminders.
  static let topInset: CGFloat = 16

  /// Bottom padding above any safe-area footer (working-hours pill, etc.).
  static let bottomInset: CGFloat = 12

  /// Vertical gap between the title row and the first content row.
  static let headerToContentSpacing: CGFloat = 12

  /// Leading inset applied to `List` rows via `listRowInsets`. Same value
  /// as `horizontalInset` so row text aligns with the pane title.
  static let listRowLeading: CGFloat = 24

  /// Trailing inset applied to `List` rows.
  static let listRowTrailing: CGFloat = 24

  /// Vertical padding inside a `List` row. Combined with `rowMinHeight`,
  /// this keeps a two-line row at the comfortable ~60pt density Mail and
  /// Reminders use; one-line rows breathe with the same min-height frame.
  static let listRowVertical: CGFloat = 8

  /// Minimum total row height. The reviewer flagged the row anatomy at
  /// ~32–40pt as "cramped vs the canvas" — bumping to 60 turns the two-
  /// line preview (title + subtitle) into an intentional layout rather
  /// than an accident, and matches the Reminders / Mail density.
  static let rowMinHeight: CGFloat = 60

  /// Width of the accent bar applied to the leading edge of the "Next"
  /// row in Available. Three points: visible without competing with
  /// content, vertical alignment under the row text inset.
  static let nextAccentBarWidth: CGFloat = 3

  /// Width of the trailing inspector rail when visible. Matches Mail's
  /// message-details pane and Notes' attachment inspector. Wider than
  /// 240 (which feels cramped at small window sizes); narrower than 320
  /// (which steals canvas).
  static let inspectorWidth: CGFloat = 280

  /// Width of the divider between content and inspector. 1pt + system
  /// separator color reads as native chrome rather than a drawn line.
  static let inspectorDividerWidth: CGFloat = 1

  /// Semantic "secondary but readable" foreground. macOS's stock
  /// `.secondary` foregroundStyle bottoms out at roughly 50% primary in
  /// light mode — fine for chrome, too gray-on-gray for productivity
  /// scanning where the eye has to land on subtitle text fast. The punch
  /// list flagged this in three places (row subtitles, popover row
  /// subtitles, the working-hours footer caption) and the fix is one
  /// semantic constant rather than a sprinkle of `.opacity(0.72)` at call
  /// sites. 0.72 is the productivity-app sweet spot — heavy enough to
  /// read across the canvas, light enough to stay clearly secondary to
  /// the primary title weight. Applies in both light and dark mode
  /// because `Color.primary` already inverts.
  static let secondaryText: Color = Color.primary.opacity(0.72)
}
