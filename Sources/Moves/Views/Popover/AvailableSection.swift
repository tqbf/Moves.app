import SwiftUI

/// "Available" section of the popover (INITIAL-PLAN §4.1, §11, §12, §22).
///
/// One row per active thread with a resolved move. Threads without a
/// re-entry point are absent — that's the §22 invariant, enforced upstream
/// by `AppStore.rebuildAvailable()` filtering on `MoveResolver.resolve`.
///
/// Sectioning (§12): two render groups, `Available` and
/// `De-emphasized during working hours`. Classification routes through
/// `WorkingHoursService.classify(...)` — the same §6 policy the
/// main-window Available pane uses — so a `.downweightWork` thread
/// only deemphs while it's actually work-time, and `.hideWork` /
/// `.onlyWork` are respected too.
///
/// Clicking a row:
///   - no Current → `start(_:)`
///   - Current exists and clicked row ≠ Current → open Switch sheet
///   - clicked row == Current → no-op (the row is the same Current
///     surface; user can stop via the Current section).
struct AvailableSection: View {
  @Environment(AppStore.self) private var store
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    PopoverSectionContainer(title: "Available") {
      let groups = grouped()
      if groups.visible.isEmpty, groups.deemphasized.isEmpty {
        Text("No re-entry points")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(groups.visible) { row in
            AvailableRow(item: row, deemphasized: false, action: { handleClick(row) })
          }
        }

        if !groups.deemphasized.isEmpty {
          Text("De-emphasized during working hours")
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.tertiary)
            .padding(.top, 6)
          VStack(alignment: .leading, spacing: 2) {
            ForEach(groups.deemphasized) { row in
              AvailableRow(item: row, deemphasized: true, action: { handleClick(row) })
            }
          }
        }
      }
    }
  }

  // MARK: - Grouping

  /// Apply the §6 working-hours classifier — same path the main-window
  /// Available pane uses. `.downweightWork` rows land in `deemphasized`
  /// only while it's actually work-time; outside work-time they sit in
  /// `visible`. `.hideWork` / `.onlyWork` get dropped entirely when the
  /// policy says so (no row, no entry — the popover is short on space
  /// already; an empty section for a hidden row would be confusing).
  private func grouped() -> WorkingHoursService.FilteredAvailable {
    WorkingHoursService.filter(
      available: store.availableThreads,
      isWorkTime: store.isWorkTime,
      hasDeadline: { row in
        (store.openItemsByThread[row.thread.id] ?? []).contains { $0.dueAt != nil }
      }
    )
  }

  // MARK: - Click handling

  private func handleClick(_ row: AvailableThread) {
    let currentId = store.current.threadId
    if currentId == nil {
      Task { await store.start(row.thread) }
      return
    }
    if currentId == row.thread.id {
      return // Already current.
    }
    store.pendingFlow = .switch(fromThreadId: currentId!, toThreadId: row.thread.id)
    openWindow(id: PopoverWindowID.switchFlow.rawValue)
  }
}

// MARK: - Row

private struct AvailableRow: View {
  let item: AvailableThread
  let deemphasized: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 1) {
        Text(item.thread.title)
          .font(.callout)
          .fontWeight(deemphasized ? .regular : .medium)
          .foregroundStyle(deemphasized ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
          .lineLimit(1)
        RowSubtitle(item.move.text)
          .font(.caption)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 4)
      .padding(.horizontal, 8)
      .contentShape(Rectangle())
    }
    .buttonStyle(AvailableRowButtonStyle())
    .accessibilityLabel("Switch to \(item.thread.title). Next move: \(item.move.text).")
  }
}

/// Custom button style: rounded-rect highlight on hover/press so the rows
/// feel clickable (macOS finder-sidebar idiom). Avoids the default
/// SwiftUI `.plain` button look which gives no affordance at all.
///
/// Hover state lives on a private inner view because `@State` on a
/// `ButtonStyle` struct isn't kept-alive between `makeBody` calls.
private struct AvailableRowButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    HoverHighlight(isPressed: configuration.isPressed) {
      configuration.label
    }
  }
}

private struct HoverHighlight<Content: View>: View {
  let isPressed: Bool
  @ViewBuilder var content: () -> Content
  @State private var hovering = false

  var body: some View {
    content()
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(background)
      )
      .onHover { hovering = $0 }
  }

  private var background: Color {
    if isPressed { return Color.accentColor.opacity(0.18) }
    if hovering { return Color.primary.opacity(0.06) }
    return Color.clear
  }
}
