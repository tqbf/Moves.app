import SwiftUI

/// Shared visual frame for the Stop / Switch / Park sheets. They run as
/// separate `Window` scenes (decision: a `MenuBarExtra` popover auto-
/// dismisses on focus loss, which would kill a SwiftUI `.sheet`'s host),
/// so each sheet needs its own padding + title + button row chrome.
///
/// Renders a tight, modal-feeling card: title, content, primary/cancel
/// action row. macOS modal idioms — primary at the right, defaultAction
/// + cancelAction wired so Return / Esc work as expected.
struct FlowSheetChrome<Content: View, Trailing: View>: View {
  let title: String
  let subtitle: String?
  let primary: String
  let onPrimary: () -> Void
  let onCancel: () -> Void
  let isPrimaryEnabled: Bool
  @ViewBuilder var content: () -> Content
  @ViewBuilder var trailingButtons: () -> Trailing

  init(
    title: String,
    subtitle: String? = nil,
    primary: String,
    isPrimaryEnabled: Bool = true,
    onPrimary: @escaping () -> Void,
    onCancel: @escaping () -> Void,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder trailingButtons: @escaping () -> Trailing = { EmptyView() }
  ) {
    self.title = title
    self.subtitle = subtitle
    self.primary = primary
    self.onPrimary = onPrimary
    self.onCancel = onCancel
    self.isPrimaryEnabled = isPrimaryEnabled
    self.content = content
    self.trailingButtons = trailingButtons
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
        if let subtitle {
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
      }

      content()

      HStack(spacing: 8) {
        Spacer()
        trailingButtons()
        Button("Cancel", role: .cancel, action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button(primary, action: onPrimary)
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
          .disabled(!isPrimaryEnabled)
      }
    }
    .padding(20)
    .frame(width: 440)
    .fixedSize(horizontal: false, vertical: true)
  }
}
