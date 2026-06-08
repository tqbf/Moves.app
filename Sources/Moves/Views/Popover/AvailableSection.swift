import SwiftUI

/// "Available" section of the popover (INITIAL-PLAN §4.1, §11, §12, §22).
///
/// One row per active thread with a resolved move. Threads without a
/// re-entry point are absent — that's the §22 invariant, enforced upstream
/// by `AppStore.rebuildAvailable()` filtering on `MoveResolver.resolve`.
///
/// Sectioning (§12): Phase 3 ships `Available` + `De-emphasized` as the
/// two render groups. Working-hours visibility (the policy that classifies
/// rows into de-emphasized) is Phase 4 territory; for now we surface
/// `ThreadVisibility.downweightWork` rows into the de-emphasis group so
/// the layout exists and we don't have to rewire the section later.
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
      if groups.normal.isEmpty, groups.deemphasized.isEmpty {
        Text("No re-entry points")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
      } else {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(groups.normal) { row in
            AvailableRow(item: row, deemphasized: false, action: { handleClick(row) })
          }
        }

        if !groups.deemphasized.isEmpty {
          Text("De-emphasized during working hours")
            .font(.system(size: 10, weight: .medium))
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

  private struct Groups {
    var normal: [AvailableThread]
    var deemphasized: [AvailableThread]
  }

  private func grouped() -> Groups {
    var normal: [AvailableThread] = []
    var deemphasized: [AvailableThread] = []
    for row in store.availableThreads {
      switch row.thread.visibility {
      case .normal, .onlyWork, .hideWork:
        normal.append(row)
      case .downweightWork:
        deemphasized.append(row)
      }
    }
    return Groups(normal: normal, deemphasized: deemphasized)
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
          .font(.system(size: 13, weight: deemphasized ? .regular : .medium))
          .foregroundStyle(deemphasized ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
          .lineLimit(1)
        Text(item.move.text)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 4)
      .padding(.horizontal, 8)
      .contentShape(Rectangle())
    }
    .buttonStyle(AvailableRowButtonStyle())
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
