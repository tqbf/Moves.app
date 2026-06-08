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
struct PaneShell<Content: View>: View {
  let title: String
  var subtitle: String?
  @ViewBuilder var content: () -> Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.system(size: 24, weight: .semibold))
          if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(.system(size: 13))
              .foregroundStyle(.secondary)
          }
        }
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
