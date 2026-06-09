import SwiftUI

/// "Deadlines" pane in the main window (INITIAL-PLAN §4.2). One list of
/// every item with a `due_at`, sorted ascending. Overdue rows render
/// muted-orange; future rows are neutral. Swipe-left to delete.
///
/// This is the "what's coming up?" view — the popover Upcoming section is
/// scoped to hard-only items; this pane shows everything with a deadline
/// regardless of interruption kind. Click a row → inspector summary.
struct DeadlinesView: View {
  @Environment(AppStore.self) private var store

  @State private var selection: String?
  @SceneStorage("inspector.deadlines.visible") private var inspectorVisible = false

  var body: some View {
    PaneListShell(
      title: "Deadlines",
      count: store.deadlineItems.count,
      accessory: { headerAccessory },
      content: { content },
      inspector: {
        InspectorColumn(isVisible: $inspectorVisible) { inspectorBody }
      }
    )
  }

  @ViewBuilder
  private var headerAccessory: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.18)) { inspectorVisible.toggle() }
    } label: {
      Label("Toggle inspector", systemImage: "sidebar.right")
        .labelStyle(.iconOnly)
    }
    .buttonStyle(.borderless)
    .help(inspectorVisible ? "Hide inspector" : "Show inspector")
  }

  @ViewBuilder
  private var content: some View {
    if store.deadlineItems.isEmpty {
      // Batch 8, item 28 — neutral empty state. Calendar systemImage to
      // match the panel's vocabulary; no action button because the way to
      // get a deadline into Moves is to capture one, which the Captured
      // empty state already surfaces.
      ContentUnavailableView(
        "No upcoming deadlines",
        systemImage: "calendar",
        description: Text("Captures with a date or time show up here.")
      )
    } else {
      List(selection: $selection) {
        ForEach(store.deadlineItems) { item in
          DeadlineRow(
            item: item,
            threadTitle: threadTitle(for: item),
            isSelected: selection == item.id
          )
            .tag(item.id)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
              top: PaneMetrics.listRowVertical,
              leading: PaneMetrics.listRowLeading,
              bottom: PaneMetrics.listRowVertical,
              trailing: PaneMetrics.listRowTrailing
            ))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button(role: .destructive) {
                store.deleteItem(item)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
        }
      }
      .listStyle(.inset)
      .scrollContentBackground(.hidden)
    }
  }

  @ViewBuilder
  private var inspectorBody: some View {
    if let id = selection, let item = store.deadlineItems.first(where: { $0.id == id }) {
      InspectorDetail(
        title: item.title,
        subtitle: threadTitle(for: item),
        metadata: metadataRows(for: item)
      ) {
        Button("Mark done") { Task { await store.markItemDone(item) } }
          .buttonStyle(.borderedProminent)
      }
    } else {
      InspectorEmptyState(
        title: "Nothing selected",
        systemImage: "calendar.badge.clock",
        message: "Pick a deadline to see its details and resolve it.",
        actionLabel: nil,
        action: nil
      )
    }
  }

  private func metadataRows(for item: Item) -> [(label: String, value: String)] {
    var rows: [(String, String)] = []
    if let due = item.dueAt {
      let date = Date(timeIntervalSince1970: TimeInterval(due))
      rows.append(("Due", Self.formatter.string(from: date)))
      let isOverdue = TimeInterval(due) < Date().timeIntervalSince1970
      rows.append(("State", isOverdue ? "Overdue" : "Upcoming"))
    }
    rows.append(("Kind", item.kind.rawValue.capitalized))
    return rows
  }

  private func threadTitle(for item: Item) -> String? {
    guard let threadId = item.threadId else { return nil }
    return store.thread(id: threadId)?.title
  }

  private static let formatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    f.doesRelativeDateFormatting = true
    return f
  }()
}

private struct DeadlineRow: View {
  let item: Item
  let threadTitle: String?
  var isSelected: Bool = false
  @Environment(AppStore.self) private var store

  /// Local sheet for the row-level Edit-due affordance — separate state
  /// per row so two open editors can't fight.
  @State private var editingDueItem: Item?

  var body: some View {
    TaskRow(
      title: item.title,
      subtitle: subtitleLine,
      deadline: deadlineDate,
      threadTag: threadTitle,
      leadingIcon: TaskRowLeadingIcon(
        systemName: icon,
        tint: iconColor,
        accessibilityLabel: iconAccessibilityLabel
      ),
      isSelected: isSelected,
      hoverActions: {
        // Hover affordances: Edit due (calendar.badge.clock) and
        // Mark done (checkmark.circle). Both wire to existing AppStore
        // methods. Edit opens the same sheet the context menu uses.
        RowHoverActionButton(systemName: "calendar.badge.clock", help: "Edit due") {
          editingDueItem = item
        }
        RowHoverActionButton(systemName: "checkmark.circle", help: "Mark done") {
          Task { await store.markItemDone(item) }
        }
      }
    )
    .contextMenu {
      Button("Edit due time…") { editingDueItem = item }
      Button("Mark Done") { Task { await store.markItemDone(item) } }
      Divider()
      Button("Delete", role: .destructive) { store.deleteItem(item) }
    }
    .sheet(item: $editingDueItem) { item in
      EditDueTimeSheet(item: item) { editingDueItem = nil }
    }
  }

  /// Plain "Captured" caption when the item isn't on a thread; otherwise
  /// nil so the row falls back to a single-line layout (the thread tag
  /// already tells the reader where the deadline lives).
  private var subtitleLine: String? {
    threadTitle == nil ? "Captured" : nil
  }

  private var deadlineDate: Date? {
    guard let due = item.dueAt else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(due))
  }

  /// Leading icon encodes interruption kind — overdue is now signalled
  /// by the trailing `DeadlineChip` (red + warning triangle), so we don't
  /// double-encode it on the leading side.
  private var icon: String {
    switch item.interruptionKind {
    case .hard: return "bell.fill"
    case .soft: return "calendar"
    case .none: return "clock"
    }
  }

  private var iconColor: Color {
    switch item.interruptionKind {
    case .hard: return .orange
    case .soft: return .secondary
    case .none: return Color.gray.opacity(0.6)
    }
  }

  private var iconAccessibilityLabel: String {
    switch item.interruptionKind {
    case .hard: return "Hard reminder"
    case .soft: return "Soft reminder"
    case .none: return "Capture"
    }
  }
}
