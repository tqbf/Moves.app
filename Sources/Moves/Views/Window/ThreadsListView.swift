import SwiftUI

/// "Threads" pane in the main window (INITIAL-PLAN §4.2). All threads,
/// grouped by status, with an inline "New thread…" field at the top.
/// Selecting a row routes to the thread detail. Swipe-left on a row to
/// delete the thread.
///
/// This is the editing/organizing entry point — the popover is for daily-
/// driver flow, this pane is for "give me the whole list".
struct ThreadsListView: View {
  @Environment(AppStore.self) private var store
  var onSelectThread: (String) -> Void

  @State private var newTitle: String = ""
  @FocusState private var addFocused: Bool

  var body: some View {
    PaneListShell(
      title: "Threads",
      subtitle: "\(store.threads.count) total · \(store.activeCount) active"
    ) {
      VStack(spacing: 0) {
        newRow
          .padding(.horizontal, 28)
          .padding(.bottom, 6)
        List {
          section("Active", threads: store.threads(matching: .active))
          section("Parked", threads: store.threads(matching: .parked))
          section("Done", threads: store.threads(matching: .done))
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
      }
    }
  }

  // MARK: - New row

  private var newRow: some View {
    HStack(spacing: 8) {
      Image(systemName: "plus.circle.fill")
        .foregroundStyle(.tint)
      TextField("New thread…", text: $newTitle)
        .textFieldStyle(.plain)
        .focused($addFocused)
        .onSubmit(commitNew)
      if !newTitle.isEmpty {
        Button("Add", action: commitNew)
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(.background.secondary)
    )
  }

  private func commitNew() {
    let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    newTitle = ""
    Task {
      if let id = await store.createThread(title: trimmed) {
        onSelectThread(id)
      }
    }
  }

  // MARK: - Sections

  @ViewBuilder
  private func section(_ title: String, threads: [Thread]) -> some View {
    if !threads.isEmpty {
      Section(title) {
        ForEach(threads) { thread in
          ThreadRowSummary(thread: thread, action: { onSelectThread(thread.id) })
            .contextMenu {
              Button("Open") { onSelectThread(thread.id) }
              Divider()
              Button("Mark Active") { store.setStatus(thread, to: .active) }
                .disabled(thread.status == .active)
              Button("Park") { store.setStatus(thread, to: .parked) }
                .disabled(thread.status == .parked)
              Button("Mark Done") { store.setStatus(thread, to: .done) }
                .disabled(thread.status == .done)
              Divider()
              Button("Delete", role: .destructive) { store.delete(thread) }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button(role: .destructive) {
                store.delete(thread)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
        }
      }
    }
  }
}

private struct ThreadRowSummary: View {
  let thread: Thread
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(thread.title)
            .font(.system(size: 14, weight: .medium))
            .lineLimit(1)
          Text(secondaryLine)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        Text(thread.kind.rawValue.capitalized)
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

  private var secondaryLine: String {
    if !thread.breadcrumb.isEmpty { return thread.breadcrumb }
    return thread.status.rawValue.capitalized
  }
}
