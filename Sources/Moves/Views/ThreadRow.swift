import SwiftUI

/// Throwaway phase-1 row. Phase 3 replaces this with the real popover row
/// that shows the resolved move + rough estimate.
struct ThreadRow: View {
  let thread: Thread
  @Environment(AppStore.self) private var store

  var body: some View {
    HStack(spacing: 10) {
      Button {
        let next: ThreadStatus = thread.status == .done ? .active : .done
        store.setStatus(thread, to: next)
      } label: {
        Image(systemName: thread.status == .done ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(thread.status == .done ? Color.accentColor : .secondary)
          .symbolEffect(.bounce, value: thread.status)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(thread.status == .done ? "Mark as active" : "Mark as done")

      VStack(alignment: .leading, spacing: 1) {
        Text(thread.title)
          .font(.body)
          .strikethrough(thread.status == .done, color: .secondary)
          .foregroundStyle(thread.status == .done ? .secondary : .primary)
          .lineLimit(1)
        Text(secondaryLine)
          .font(.caption)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 2)
  }

  private var secondaryLine: String {
    if !thread.breadcrumb.isEmpty {
      return thread.breadcrumb
    }
    return thread.status.rawValue.capitalized
  }
}
