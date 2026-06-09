import SwiftUI

/// Reusable right-rail inspector for list-style panes (Available, Threads,
/// Captured, Deadlines). One implementation; each pane provides the
/// selection-resolved detail builder. Matches the macOS Mail / Notes /
/// Reminders "show details" idiom: a fixed-width column on the trailing
/// edge that the user can toggle off when they want the whole canvas for
/// the list.
///
/// Why not `HSplitView`? It forces a draggable divider and trips up
/// keyboard focus inside our outer `NavigationSplitView`. A plain HStack
/// + animated frame is the modern macOS-14+ idiom for fixed-width
/// inspector chrome we don't want resized.
///
/// Why not `.inspector { … }`? That modifier exists on macOS 14+ but only
/// surfaces the inspector at the **window** root (peer of the
/// NavigationSplitView's detail column), not as a per-pane affordance.
/// Each pane in Moves has a different selection type and a different
/// "nothing selected" treatment; one window-scoped inspector can't model
/// that without a sum-typed selection bus.
struct InspectorColumn<Content: View>: View {
  /// Whether the rail is currently visible. Bound to a `@SceneStorage`
  /// in the host pane so the toggle persists across window restarts but
  /// stays per-window if the user opens multiple Moves windows.
  @Binding var isVisible: Bool

  /// Content to render inside the rail. Hosts pass `selectedDetail` /
  /// `nothingSelected` themselves via switch-on-selection — see the
  /// existing `withInspector(...)` helpers below.
  @ViewBuilder var content: () -> Content

  var body: some View {
    if isVisible {
      HStack(spacing: 0) {
        Divider()
        ScrollView {
          content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .frame(width: PaneMetrics.inspectorWidth)
        .background(.background.secondary)
      }
      .transition(.move(edge: .trailing).combined(with: .opacity))
    }
  }
}

/// "Nothing selected" placeholder. Every pane uses the same visual
/// treatment so the user learns the pattern once: a muted icon, a one-
/// line headline, and a single obvious next action (varies per pane).
struct InspectorEmptyState: View {
  let title: String
  let systemImage: String
  let message: String
  let actionLabel: String?
  let action: (() -> Void)?

  init(
    title: String,
    systemImage: String,
    message: String,
    actionLabel: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.title = title
    self.systemImage = systemImage
    self.message = message
    self.actionLabel = actionLabel
    self.action = action
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Image(systemName: systemImage)
        .font(.system(size: 22, weight: .regular))
        .foregroundStyle(.tertiary)
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
      Text(message)
        .font(.system(size: 12))
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
      if let actionLabel, let action {
        Button(actionLabel, action: action)
          .buttonStyle(.bordered)
          .controlSize(.small)
          .padding(.top, 2)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Reusable "selected item" inspector body: prominent title, optional
/// subtitle, optional metadata rows, and a primary action button. Each
/// pane composes its detail from these primitives instead of rolling a
/// bespoke layout per row type.
struct InspectorDetail<Action: View>: View {
  let title: String
  let subtitle: String?
  let metadata: [(label: String, value: String)]
  @ViewBuilder var actions: () -> Action

  init(
    title: String,
    subtitle: String? = nil,
    metadata: [(label: String, value: String)] = [],
    @ViewBuilder actions: @escaping () -> Action = { EmptyView() }
  ) {
    self.title = title
    self.subtitle = subtitle
    self.metadata = metadata
    self.actions = actions
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      if !metadata.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(Array(metadata.enumerated()), id: \.offset) { _, entry in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(entry.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 64, alignment: .leading)
              Text(entry.value)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
          }
        }
        .padding(.top, 4)
      }
      actions()
        .padding(.top, 4)
      Spacer(minLength: 0)
    }
  }
}
