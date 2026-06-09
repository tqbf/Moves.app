import SwiftUI

/// One row of the Captured pane (INITIAL-PLAN §4.2, §13). The row owns
/// the §13 processing-actions context menu:
///
///   - Attach to thread… (opens a thread picker — only sheet action)
///   - Convert to reminder / task / capture
///   - Mark done
///   - Cancel
///   - Edit due time… (sheet — reuses the capture-edit pattern)
///   - Delete
///
/// Per the Phase-4 plan: every action is inline on the context menu except
/// "attach to thread" (sheet picker) and "edit due time" (sheet, per the
/// open-question decision).
struct CapturedRow: View {
  let item: Item
  /// List-driven selection passed by `CapturedView` so the row paints its
  /// selected background. Defaults false for any caller that doesn't
  /// participate in selection.
  var isSelected: Bool = false
  @Environment(AppStore.self) private var store

  /// Set non-nil to present the attach-to-thread picker for *this* row.
  @State private var attachingPickerItem: Item?
  /// Set non-nil to present the due-time editor for *this* row.
  @State private var editingDueItem: Item?

  var body: some View {
    TaskRow(
      title: item.title,
      subtitle: subtitleLine,
      deadline: deadlineDate,
      leadingIcon: TaskRowLeadingIcon(
        systemName: icon,
        tint: iconColor,
        accessibilityLabel: iconAccessibilityLabel
      ),
      isSelected: isSelected,
      hoverActions: {
        // Hover-revealed shortcut to the same Edit-due sheet the
        // ellipsis menu opens. The ellipsis stays (it owns the larger
        // processing-actions menu); this is an additive shortcut to the
        // most common processing action.
        RowHoverActionButton(systemName: "calendar.badge.clock", help: "Schedule due") {
          editingDueItem = item
        }
      },
      trailing: {
        Menu {
          contextMenuActions
        } label: {
          Image(systemName: "ellipsis.circle")
            .font(.system(size: 14))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Actions for \(item.title)")
      }
    )
    .contextMenu { contextMenuActions }
    .sheet(item: $attachingPickerItem) { item in
      AttachToThreadSheet(item: item) { attachingPickerItem = nil }
    }
    .sheet(item: $editingDueItem) { item in
      EditDueTimeSheet(item: item) { editingDueItem = nil }
    }
  }

  /// Subtitle reads as the captured item's kind ("Reminder" / "Task" /
  /// "Capture") so the reader can scan kind without a separate pill. The
  /// deadline goes to the trailing `DeadlineChip`, not the subtitle —
  /// that keeps the deadline vocabulary consistent with Available and
  /// the Current card.
  private var subtitleLine: String? {
    item.kind.rawValue.capitalized
  }

  private var deadlineDate: Date? {
    guard let due = item.dueAt else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(due))
  }

  private var iconAccessibilityLabel: String {
    switch item.interruptionKind {
    case .hard: return "Hard reminder"
    case .soft: return "Soft reminder"
    case .none: return "Capture"
    }
  }

  // MARK: - Context menu

  @ViewBuilder
  private var contextMenuActions: some View {
    Button("Attach to thread…") { attachingPickerItem = item }
    Menu("Convert") {
      Button("Reminder") { Task { await store.convertItemKind(item, to: .reminder) } }
        .disabled(item.kind == .reminder)
      Button("Task") { Task { await store.convertItemKind(item, to: .task) } }
        .disabled(item.kind == .task)
      Button("Capture") { Task { await store.convertItemKind(item, to: .capture) } }
        .disabled(item.kind == .capture)
    }
    Button("Edit due time…") { editingDueItem = item }
    Divider()
    Button("Mark Done") { Task { await store.markItemDone(item) } }
    Button("Cancel") { Task { await store.cancelItem(item) } }
    Divider()
    Button("Delete", role: .destructive) { store.deleteCapturedItem(item) }
  }

  // MARK: - Icon & labels

  private var icon: String {
    switch item.interruptionKind {
    case .hard: return "bell.fill"
    case .soft: return "calendar"
    case .none: return "tray"
    }
  }

  private var iconColor: Color {
    switch item.interruptionKind {
    case .hard: return .orange
    case .soft: return .secondary
    case .none: return Color.gray.opacity(0.55)
    }
  }

}

// MARK: - Attach picker sheet

/// Small thread-picker sheet. Lists active threads, click one to attach
/// the item and dismiss. No filtering / no search — the threads list is
/// small by design (§2.9 "no taxonomy creep").
private struct AttachToThreadSheet: View {
  let item: Item
  let onClose: () -> Void
  @Environment(AppStore.self) private var store

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Attach to thread")
        .font(.system(size: 16, weight: .semibold))
      Text(item.title)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .lineLimit(2)

      Divider()

      ScrollView {
        VStack(spacing: 0) {
          let actives = store.threads(matching: .active)
          if actives.isEmpty {
            ContentUnavailableView("No active threads", systemImage: "rectangle.stack")
              .frame(maxWidth: .infinity, minHeight: 120)
          } else {
            ForEach(actives) { thread in
              Button {
                Task {
                  await store.attachToThread(thread.id, item: item)
                  onClose()
                }
              } label: {
                HStack {
                  Text(thread.title)
                    .font(.system(size: 13, weight: .medium))
                  Spacer()
                  if !thread.breadcrumb.isEmpty {
                    Text(thread.breadcrumb)
                      .font(.system(size: 11))
                      .foregroundStyle(.tertiary)
                      .lineLimit(1)
                  }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              if thread.id != actives.last?.id {
                Divider().padding(.leading, 12)
              }
            }
          }
        }
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.background.secondary)
        )
      }
      .frame(maxHeight: 280)

      HStack {
        Spacer()
        Button("Cancel", role: .cancel, action: onClose)
          .keyboardShortcut(.cancelAction)
      }
    }
    .padding(20)
    .frame(width: 360)
  }
}

// MARK: - Edit due time sheet

/// Edit-due sheet — promoted from `private` so the Deadlines pane can
/// reuse it for its row-level "Edit due" affordance (batch 7, item 27).
struct EditDueTimeSheet: View {
  let item: Item
  let onClose: () -> Void
  @Environment(AppStore.self) private var store

  @State private var hasDeadline: Bool = false
  @State private var dueDate: Date = Date()
  @State private var includeTime: Bool = true
  /// The user's revised alert-offset selection. Prefilled from the
  /// existing Alert rows on appear (or kind defaults if there are none),
  /// then handed back to `editDueAt(offsetsOverride:)` on save.
  @State private var alertSelection: Set<Int> = []
  /// Tracks an in-flight prefill of `alertSelection` so the sheet doesn't
  /// race the user (`task` modifier runs once on appear).
  @State private var alertsPrefilled = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Edit due time")
        .font(.system(size: 16, weight: .semibold))
      Text(item.title)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .lineLimit(2)

      Divider()

      Toggle("Has deadline", isOn: $hasDeadline)
        .toggleStyle(.switch)

      if hasDeadline {
        Toggle("Include time of day", isOn: $includeTime)
          .toggleStyle(.switch)

        DatePicker(
          "Due",
          selection: $dueDate,
          displayedComponents: includeTime ? [.date, .hourAndMinute] : [.date]
        )
        .datePickerStyle(.compact)

        // Per-item alert plan. Same chip idiom as the capture palette so
        // the user has one mental model for "how far ahead do I want to
        // be pinged" regardless of where they're editing it.
        VStack(alignment: .leading, spacing: 6) {
          Text("Alert me")
            .font(.caption)
            .foregroundStyle(.secondary)
          AlertOffsetChipRow(selection: $alertSelection, leadingLabel: nil)
        }
      }

      HStack {
        Spacer()
        Button("Cancel", role: .cancel, action: onClose)
          .keyboardShortcut(.cancelAction)
        Button("Save", action: save)
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 360)
    .onAppear(perform: prefill)
    .task { await prefillAlerts() }
  }

  private func prefill() {
    if let due = item.dueAt {
      hasDeadline = true
      dueDate = Date(timeIntervalSince1970: TimeInterval(due))
      includeTime = item.dueKind == .datetime
    } else {
      hasDeadline = false
      dueDate = Date()
      includeTime = true
    }
  }

  /// Seed the chip selection from the persisted Alert rows. If there are
  /// none (item never had a deadline / alerts were dropped), fall back to
  /// the kind defaults so the user sees a sensible starting selection.
  private func prefillAlerts() async {
    guard !alertsPrefilled else { return }
    alertsPrefilled = true
    do {
      let existing = try await store.alertRepository.forItem(item.id)
      if existing.isEmpty {
        alertSelection = Set(store.offsetsForCapture(kind: item.kind))
      } else {
        alertSelection = Set(existing.map(\.offsetMinutes))
      }
    } catch {
      alertSelection = Set(store.offsetsForCapture(kind: item.kind))
    }
  }

  private func save() {
    let date: Date? = hasDeadline ? dueDate : nil
    let dueKind: DueKind = !hasDeadline ? .none : (includeTime ? .datetime : .date)
    // Only pass an override when the user kept a deadline — clearing the
    // deadline tears down all alerts, no override needed.
    let offsetsOverride: [Int]? = hasDeadline ? alertSelection.sorted() : nil
    Task {
      await store.editDueAt(
        item,
        dueAt: date,
        dueKind: dueKind,
        offsetsOverride: offsetsOverride
      )
      onClose()
    }
  }
}
