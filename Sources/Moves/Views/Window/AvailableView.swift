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
/// affordance during active work). Swipe-left on a row to delete the
/// underlying thread.
struct AvailableView: View {
  @Environment(AppStore.self) private var store
  var onSelectThread: (String) -> Void

  var body: some View {
    PaneListShell(title: "Available", subtitle: { workingStatus }) {
      let filtered = filtered()
      if filtered.visible.isEmpty, filtered.deemphasized.isEmpty {
        ContentUnavailableView(
          "Nothing available",
          systemImage: "figure.walk.motion",
          description: Text("Add a breadcrumb to a thread, or capture a reminder.")
        )
      } else {
        List {
          if !filtered.visible.isEmpty {
            Section {
              ForEach(filtered.visible) { row in
                rowView(row, deemphasized: false)
              }
            }
          }
          if !filtered.deemphasized.isEmpty {
            Section("De-emphasized during working hours") {
              ForEach(filtered.deemphasized) { row in
                rowView(row, deemphasized: true)
              }
            }
          }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
      }
    }
  }

  /// Subtitle: a "Working: yes/no" pill plus the configured hours range
  /// as a muted caption. The pill is the at-a-glance signal — "yes" is
  /// the more urgent state (the user is at work, the de-emphasized
  /// section is being suppressed) so it gets the orange urgency tint
  /// that the menubar badge and Upcoming hard-deadline icons already
  /// use. "No" gets a neutral gray. Hours stay visible so the user can
  /// see what window the answer is being computed against without
  /// opening Settings.
  @ViewBuilder
  private var workingStatus: some View {
    let working = store.isWorkTime
    let tint: Color = working ? .orange : .secondary
    let label = working ? "yes" : "no"
    HStack(spacing: 6) {
      Text("Working:")
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
      HStack(spacing: 0) {
        Text(label)
          .font(.system(size: 11, weight: .semibold))
      }
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .foregroundStyle(tint)
      .background(
        Capsule(style: .continuous)
          .fill(tint.opacity(0.15))
      )
      Text("·")
        .font(.system(size: 13))
        .foregroundStyle(.tertiary)
      Text("\(WorkingHours.formatMinute(store.workingHours.startMinute))–\(WorkingHours.formatMinute(store.workingHours.endMinute))")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
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

  @ViewBuilder
  private func rowView(_ row: AvailableThread, deemphasized: Bool) -> some View {
    AvailableRow(item: row, deemphasized: deemphasized) {
      onSelectThread(row.thread.id)
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button(role: .destructive) {
        store.delete(row.thread)
      } label: {
        Label("Delete", systemImage: "trash")
      }
    }
  }
}

private struct AvailableRow: View {
  let item: AvailableThread
  let deemphasized: Bool
  let action: () -> Void

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
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
