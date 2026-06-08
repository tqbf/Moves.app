import SwiftUI

/// Shared frame for top-level detail panes. One large title in the toolbar
/// position, then a vertical content stack inside a `ScrollView`. Keeps
/// chrome consistent across Available / Threads / Captured / Deadlines /
/// Parking Lot.
///
/// Unlike the menu-bar popover, this is a regular `Window` scene — the
/// Phase-3 gate note about `ScrollView` collapsing children does NOT
/// apply here, so the body is wrapped in `ScrollView` for natural content
/// overflow.
struct PaneShell<Subtitle: View, Content: View>: View {
  let title: String
  @ViewBuilder var subtitle: () -> Subtitle
  @ViewBuilder var content: () -> Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        PaneHeader(title: title, subtitle: subtitle)
        content()
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

extension PaneShell where Subtitle == PaneSubtitleText {
  init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
    self.title = title
    self.subtitle = { PaneSubtitleText(text: subtitle) }
    self.content = content
  }
}

/// Variant of `PaneShell` for panes whose body is a `List` (or starts
/// with one). The header sits above the list at the same horizontal inset
/// as `PaneShell`; the list provides its own scrolling and renders the
/// macOS-native row separators + swipe-action chrome.
///
/// Use `PaneListShell` whenever the pane wants per-row swipe-to-delete —
/// `.swipeActions` is only honored inside `List`/`Form`, not a plain
/// `VStack { ForEach }`.
struct PaneListShell<Subtitle: View, Content: View>: View {
  let title: String
  @ViewBuilder var subtitle: () -> Subtitle
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PaneHeader(title: title, subtitle: subtitle)
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 12)
      content()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

extension PaneListShell where Subtitle == PaneSubtitleText {
  init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
    self.title = title
    self.subtitle = { PaneSubtitleText(text: subtitle) }
    self.content = content
  }
}

/// Default subtitle rendering: a 13pt secondary `Text` line, or nothing
/// at all when `text` is nil/empty. Exists so the string-based
/// `PaneShell` / `PaneListShell` initializers preserve their old
/// behavior — callers that want a richer subtitle (pills, chips, etc.)
/// pass a `@ViewBuilder` closure instead.
struct PaneSubtitleText: View {
  let text: String?

  var body: some View {
    if let text, !text.isEmpty {
      Text(text)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
    }
  }
}

/// Shared title/subtitle block. Pulled out of both shells so the typography
/// can't drift between scrollable and list-hosted panes.
private struct PaneHeader<Subtitle: View>: View {
  let title: String
  @ViewBuilder let subtitle: () -> Subtitle

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 24, weight: .semibold))
      subtitle()
    }
  }
}
