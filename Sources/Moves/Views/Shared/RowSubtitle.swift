import SwiftUI

/// Row subtitle text used across list panes (Available, Threads, Popover).
///
/// One job: strip the trailing-ellipsis dance. User-typed sources
/// (breadcrumbs, segment moves, item titles) often end in `...` or `…`;
/// when SwiftUI then tail-truncates a too-long line it appends another
/// ellipsis on top, producing strings like
/// `Write an mOS blog post, or something about meta-apps....`. The fix is
/// to drop any trailing run of dots/ellipsis characters from the source
/// **before** handing the string to `Text`, and let SwiftUI's
/// `.truncationMode(.tail)` own the truncation glyph.
///
/// Modifier set is standardized so every row subtitle reads the same:
/// `PaneMetrics.secondaryText` foreground (semantic constant — see batch 8
/// item 30; stock `.secondary` was too gray-on-gray for productivity
/// scanning), single line, tail truncation.
struct RowSubtitle: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(Self.sanitize(text))
      .foregroundStyle(PaneMetrics.secondaryText)
      .lineLimit(1)
      .truncationMode(.tail)
  }

  /// Trim trailing whitespace + any run of `.` or `…` so SwiftUI's tail
  /// truncation isn't fighting with literal source ellipses. Empty / all-
  /// dots input falls through to the trimmed result (we don't invent
  /// content).
  static func sanitize(_ input: String) -> String {
    var s = Substring(input)
    while let last = s.last, last.isWhitespace || last == "." || last == "\u{2026}" {
      s = s.dropLast()
    }
    return String(s)
  }
}
