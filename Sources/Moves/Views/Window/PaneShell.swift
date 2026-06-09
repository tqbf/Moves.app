import SwiftUI

/// Vertical-scroll layout wrapper for top-level detail panes whose body
/// is text/cards rather than a List. Used by Current and Time Log.
///
/// Renders a pane title row (title + count badge + accessory slot) at
/// the top of the content. The sidebar still labels the destination, but
/// having no title in-pane meant the reader had to look back at the
/// sidebar to remember what they were looking at — a tax that grew with
/// every new pane. The header echoes Mail's "Inbox · 12" / Reminders'
/// "Today · 4" idiom; titles are short and the count is the secondary
/// hierarchy beat.
struct PaneShell<Content: View, Accessory: View>: View {
  let title: String
  let count: Int?
  @ViewBuilder var accessory: () -> Accessory
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PaneHeader(title: title, count: count, accessory: accessory)
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          content()
          Spacer(minLength: 0)
        }
        .padding(.horizontal, PaneMetrics.horizontalInset)
        .padding(.top, PaneMetrics.headerToContentSpacing)
        .padding(.bottom, PaneMetrics.bottomInset)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

extension PaneShell where Accessory == EmptyView {
  init(
    title: String,
    count: Int? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.count = count
    self.accessory = { EmptyView() }
    self.content = content
  }
}

/// Variant for panes whose body is (or starts with) a `List`. The list
/// provides its own scrolling; the shell renders the pane header above
/// it.
struct PaneListShell<Content: View, Accessory: View>: View {
  let title: String
  let count: Int?
  @ViewBuilder var accessory: () -> Accessory
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PaneHeader(title: title, count: count, accessory: accessory)
      content()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

extension PaneListShell where Accessory == EmptyView {
  init(
    title: String,
    count: Int? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.count = count
    self.accessory = { EmptyView() }
    self.content = content
  }
}

// MARK: - Pane header

/// In-pane title row. `title` matches the sidebar destination label so
/// the user sees one consistent name as their eye moves from the sidebar
/// into the content. `count` renders as the macOS "inbox · N" idiom — a
/// muted dot-separated secondary digit, not a colored badge (badges
/// belong on the sidebar; in-pane they read as alerts and overstate the
/// data). `accessory` is a trailing slot for sort/filter/segmented
/// controls a pane may want (Time Log uses it for the week navigator).
private struct PaneHeader<Accessory: View>: View {
  let title: String
  let count: Int?
  @ViewBuilder var accessory: () -> Accessory

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(title)
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(.primary)
      if let count, count > 0 {
        Text("·")
          .font(.system(size: 16))
          .foregroundStyle(.tertiary)
        Text("\(count)")
          .font(.system(size: 15, weight: .regular))
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      Spacer(minLength: 8)
      accessory()
    }
    .padding(.horizontal, PaneMetrics.horizontalInset)
    .padding(.top, PaneMetrics.topInset)
    .padding(.bottom, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
