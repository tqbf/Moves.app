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
    PaneListShell {
      VStack(spacing: 0) {
        let filtered = filtered()
        if filtered.visible.isEmpty, filtered.deemphasized.isEmpty {
          ContentUnavailableView(
            "Nothing available",
            systemImage: "figure.walk.motion",
            description: Text("Add a breadcrumb to a thread, or capture a reminder.")
          )
        } else {
          List {
            // Flat top section, no header — the pane itself answers
            // "what is this?", so a section title would be a tautology.
            // The de-emphasized group below DOES need its header because
            // its rows look like they belong with the rest until the
            // header explains the visual demotion.
            ForEach(filtered.visible) { row in
              rowView(row, deemphasized: false)
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
          // 20pt leading matches the inset-list's default row leading on
          // macOS, so the row text aligns with the toolbar's pane title.
          .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        workingStatus
      }
    }
  }

  /// "Working hours: yes/no" footer chip. Lives in a `.safeAreaInset`
  /// at the bottom of the pane so it never fights the List for vertical
  /// space — and so the reader sees the thread list first. "Yes" gets
  /// the orange tint Moves uses for attention/urgency throughout the
  /// app; "no" stays neutral. Footer matches the macOS pattern (Mail's
  /// connection-status footer, Reminders' completion summary).
  @ViewBuilder
  private var workingStatus: some View {
    let working = store.isWorkTime
    let tint: Color = working ? .orange : .secondary
    let label = working ? "yes" : "no"
    HStack(spacing: 6) {
      Text("Working hours:")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(label)
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .foregroundStyle(tint)
        .background(Capsule(style: .continuous).fill(tint.opacity(0.15)))
      Spacer()
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 8)
    .background(.bar)
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
        // Only surface non-default kinds — "Normal" is the implicit
        // baseline and showing it on every row was visual noise.
        if item.thread.kind != .normal {
          Text(item.thread.kind.rawValue.capitalized)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)
            .monospaced()
        }
      }
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
