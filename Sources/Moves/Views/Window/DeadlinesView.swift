import SwiftUI

/// "Deadlines" pane in the main window (INITIAL-PLAN §4.2). One list of
/// every item with a `due_at`, sorted ascending. Overdue rows render
/// muted-orange; future rows are neutral. Swipe-left to delete.
///
/// This is the "what's coming up?" view — the popover Upcoming section is
/// scoped to hard-only items; this pane shows everything with a deadline
/// regardless of interruption kind.
struct DeadlinesView: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    PaneListShell {
      if store.deadlineItems.isEmpty {
        ContentUnavailableView(
          "No deadlines",
          systemImage: "calendar.badge.clock",
          description: Text("Captures with a date or time show up here.")
        )
      } else {
        List {
          ForEach(store.deadlineItems) { item in
            DeadlineRow(item: item, threadTitle: threadTitle(for: item))
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
        .listRowInsets(EdgeInsets(top: 4, leading: 28, bottom: 4, trailing: 28))
      }
    }
  }

  private func threadTitle(for item: Item) -> String? {
    guard let threadId = item.threadId else { return nil }
    return store.thread(id: threadId)?.title
  }
}

private struct DeadlineRow: View {
  let item: Item
  let threadTitle: String?

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: icon)
        .foregroundStyle(iconColor)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
          .font(.system(size: 14, weight: .medium))
          .lineLimit(1)
        HStack(spacing: 8) {
          if let threadTitle {
            Text(threadTitle)
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
          } else {
            Text("Captured")
              .font(.system(size: 11))
              .foregroundStyle(.tertiary)
          }
          if let dueLabel {
            Text("· \(dueLabel)")
              .font(.system(size: 11))
              .foregroundStyle(isOverdue ? .orange : .secondary)
          }
        }
      }
      Spacer()
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
  }

  private var isOverdue: Bool {
    guard let due = item.dueAt else { return false }
    return TimeInterval(due) < Date().timeIntervalSince1970
  }

  private var icon: String {
    if isOverdue { return "exclamationmark.triangle.fill" }
    switch item.interruptionKind {
    case .hard: return "bell.fill"
    case .soft: return "calendar"
    case .none: return "clock"
    }
  }

  private var iconColor: Color {
    if isOverdue { return .orange }
    switch item.interruptionKind {
    case .hard: return .orange
    case .soft: return .secondary
    case .none: return Color.gray.opacity(0.6)
    }
  }

  private var dueLabel: String? {
    guard let due = item.dueAt else { return nil }
    let date = Date(timeIntervalSince1970: TimeInterval(due))
    return Self.formatter.string(from: date)
  }

  private static let formatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    f.doesRelativeDateFormatting = true
    return f
  }()
}
