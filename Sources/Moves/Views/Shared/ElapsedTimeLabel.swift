import SwiftUI

/// Self-ticking label that renders the elapsed time since `startedAt`.
///
/// Implementation note: wrapped in a `TimelineView(.periodic(...))` so the
/// timeline drives the redraw, *scoped to just this label*. The enclosing
/// Current card does not re-render every second — only the digits inside
/// this view. This is the modern idiom for ticking clocks in SwiftUI; an
/// `@State` `Timer` would invalidate the whole pane on every tick.
///
/// Typography is `.monospacedDigit()` rounded design so the digits don't
/// jitter as they advance (`01:09` → `01:10`).
struct ElapsedTimeLabel: View {

  /// Wall-clock start time. The label renders `Date.now - startedAt`,
  /// floored to seconds, on every tick.
  let startedAt: Date

  /// Font for the digits. The popover surface uses a compact label
  /// (`.callout`); the main-window Current detail uses a large rounded
  /// title. Callers supply whichever fits — the timer mechanism is the
  /// same.
  var font: Font = .system(.title, design: .rounded)

  /// Foreground style. Defaults to primary; the popover sometimes wants
  /// `.secondary` because the elapsed label is the second beat next to
  /// the started-at clock time.
  var foregroundStyle: HierarchicalShapeStyle = .primary

  var body: some View {
    TimelineView(.periodic(from: startedAt, by: 1)) { context in
      Text(ElapsedTime.format(context.date.timeIntervalSince(startedAt)))
        .font(font)
        .fontWeight(.semibold)
        .monospacedDigit()
        .foregroundStyle(foregroundStyle)
        .accessibilityLabel("Elapsed \(ElapsedTime.format(context.date.timeIntervalSince(startedAt)))")
    }
  }
}
