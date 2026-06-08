import SwiftUI

/// "Available" pane in the main window (INITIAL-PLAN §4.2, §12, §22).
///
/// Same §22 + §6 contract as the popover, rendered larger. Threads are
/// grouped into `Visible` (the normal Available list) and the §12
/// "De-emphasized during working hours" section. The §6 visibility
/// classifications (`hide_during_work` / `only_during_work` with no
/// deadline-bearing item) drop rows entirely.
///
/// Click a row → navigate to the thread detail. Switching is not done
/// from this pane; that flow lives in the popover (where it's a one-click
/// affordance during active work).
struct AvailableView: View {
  @Environment(AppStore.self) private var store
  var onSelectThread: (String) -> Void

  var body: some View {
    PaneShell(title: "Available", subtitle: subtitle) {
      let filtered = filtered()
      if filtered.visible.isEmpty, filtered.deemphasized.isEmpty {
        ContentUnavailableView(
          "Nothing available",
          systemImage: "figure.walk.motion",
          description: Text("Add a breadcrumb to a thread, or capture a reminder.")
        )
      } else {
        if !filtered.visible.isEmpty {
          rowGroup(filtered.visible, deemphasized: false)
        }
        if !filtered.deemphasized.isEmpty {
          Text("De-emphasized during working hours")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .kerning(0.5)
            .padding(.top, 8)
          rowGroup(filtered.deemphasized, deemphasized: true)
        }
      }
    }
  }

  private var subtitle: String {
    store.isWorkTime
      ? "Inside working hours. \(WorkingHours.formatMinute(store.workingHours.startMinute))–\(WorkingHours.formatMinute(store.workingHours.endMinute))."
      : "Outside working hours."
  }

  private func filtered() -> WorkingHoursService.FilteredAvailable {
    WorkingHoursService.filter(
      available: store.availableThreads,
      isWorkTime: store.isWorkTime,
      hasDeadline: { row in
        (store.openItemsByThread[row.thread.id] ?? []).contains { $0.dueAt != nil }
      }
    )
  }

  private func rowGroup(_ rows: [AvailableThread], deemphasized: Bool) -> some View {
    VStack(spacing: 0) {
      ForEach(rows) { row in
        AvailableRow(item: row, deemphasized: deemphasized) {
          onSelectThread(row.thread.id)
        }
        if row.id != rows.last?.id {
          Divider().padding(.leading, 12)
        }
      }
    }
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(.background.secondary)
    )
  }
}

private struct AvailableRow: View {
  let item: AvailableThread
  let deemphasized: Bool
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(item.thread.title)
            .font(.system(size: 14, weight: deemphasized ? .regular : .medium))
            .foregroundStyle(deemphasized ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .lineLimit(1)
          Text(item.move.text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        Text(item.thread.kind.rawValue.capitalized)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.tertiary)
          .monospaced()
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .background(hovering ? Color.primary.opacity(0.05) : Color.clear)
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
  }
}
