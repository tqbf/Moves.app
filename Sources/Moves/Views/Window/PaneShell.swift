import SwiftUI

/// Vertical-scroll layout wrapper for top-level detail panes whose body
/// is text/cards rather than a List. Used by Current and Time Log.
///
/// The shell intentionally does NOT render a pane title. The sidebar
/// already labels the pane; a big "Threads" / "Available" heading inside
/// the content area was redundant chrome that fought with the actual
/// content for the reader's eye.
struct PaneShell<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
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

/// Variant for panes whose body is (or starts with) a `List`. The list
/// provides its own scrolling; the shell just gives it top padding so it
/// doesn't butt into the toolbar. Same no-title decision as `PaneShell`.
struct PaneListShell<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      content()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .padding(.top, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
