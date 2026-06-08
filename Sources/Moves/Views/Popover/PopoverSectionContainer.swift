import SwiftUI

/// Shared section frame for the popover. Each domain section
/// (Current / Upcoming / Available / Captured) wraps its rows in this
/// container so titles, spacing, and section dividers stay consistent
/// across the popover. Keeps the parent `MenuPopoverView` readable.
///
/// Modeled on macOS finder-style "muted caption" section headers — small,
/// uppercase, secondary-foreground. Matches the `macos-design` skill's
/// preferred section affordance for tight chrome-less popovers.
struct PopoverSectionContainer<Content: View>: View {
  let title: String
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title.uppercased())
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundStyle(.tertiary)
        .kerning(0.5)

      content()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
