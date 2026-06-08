import SwiftUI

/// Throwaway phase-1/2 main window. Phase 4 replaces this with the real
/// Available / Threads / Captured / Deadlines / Parking Lot views.
///
/// Phase 2 added a minimal Captured section to the sidebar so the global
/// hotkey + parser pipeline has somewhere visible to land. The detail pane
/// still only renders Thread details — captured-item processing actions
/// (attach, convert, mark done) are Phase 4.
struct MainView: View {
  @Environment(AppStore.self) private var store
  @State private var selection: SidebarSelection?
  @State private var newThreadTitle: String = ""
  @FocusState private var addFieldFocused: Bool

  /// Sidebar selection model — captured items and threads share one list.
  /// `Hashable` so it can drive `List(selection:)`.
  enum SidebarSelection: Hashable {
    case thread(String)
    case item(String)
  }

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
    } detail: {
      detail
    }
    .navigationTitle("Moves")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("New Thread", systemImage: "plus") {
          addFieldFocused = true
        }
        .help("Focus the new-thread field")
      }
    }
  }

  // MARK: - Sidebar

  private var sidebar: some View {
    VStack(spacing: 0) {
      List(selection: $selection) {
        Section("Threads") {
          ForEach(store.threads) { thread in
            ThreadRow(thread: thread)
              .tag(SidebarSelection.thread(thread.id))
              .contextMenu {
                Button("Delete", role: .destructive) {
                  store.delete(thread)
                }
              }
          }
        }

        Section("Captured") {
          if store.capturedItems.isEmpty {
            Text("No captures yet")
              .font(.callout)
              .foregroundStyle(.tertiary)
          } else {
            ForEach(store.capturedItems) { item in
              CapturedRow(item: item)
                .tag(SidebarSelection.item(item.id))
                .contextMenu {
                  Button("Delete", role: .destructive) {
                    store.deleteCapturedItem(item)
                  }
                }
            }
          }
        }
      }
      .listStyle(.sidebar)

      Divider()

      HStack(spacing: 8) {
        Image(systemName: "plus.circle.fill")
          .foregroundStyle(.tint)
        TextField("Add a thread…", text: $newThreadTitle)
          .textFieldStyle(.plain)
          .focused($addFieldFocused)
          .onSubmit(commitAdd)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(.background.secondary)
    }
  }

  // MARK: - Detail

  @ViewBuilder
  private var detail: some View {
    switch selection {
    case let .thread(id):
      if let thread = store.thread(id: id) {
        ThreadDetail(thread: thread)
      } else {
        emptyState
      }
    case let .item(id):
      if let item = store.capturedItems.first(where: { $0.id == id }) {
        CapturedDetail(item: item)
      } else {
        emptyState
      }
    case .none:
      emptyState
    }
  }

  @ViewBuilder
  private var emptyState: some View {
    if store.threads.isEmpty, store.capturedItems.isEmpty {
      ContentUnavailableView(
        "Nothing yet",
        systemImage: "figure.walk.motion",
        description: Text("Add a thread in the sidebar — or hit ⌥Space to capture a reminder.")
      )
    } else {
      ContentUnavailableView(
        "Pick something",
        systemImage: "hand.point.up.left",
        description: Text("Select a thread or capture from the sidebar.")
      )
    }
  }

  // MARK: - Actions

  private func commitAdd() {
    let trimmed = newThreadTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    store.addThread(title: trimmed)
    newThreadTitle = ""
  }
}

// MARK: - Captured sidebar row

private struct CapturedRow: View {
  let item: Item

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .foregroundStyle(iconColor)
      VStack(alignment: .leading, spacing: 1) {
        Text(item.title)
          .lineLimit(1)
        if let due = dueLabel {
          Text(due)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
    }
  }

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

  private var dueLabel: String? {
    guard let due = item.dueAt else { return nil }
    let date = Date(timeIntervalSince1970: TimeInterval(due))
    return Self.formatter.string(from: date)
  }

  private static let formatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    f.timeStyle = .short
    f.doesRelativeDateFormatting = true
    return f
  }()
}

// MARK: - Captured detail

/// Throwaway Phase-2 captured-item detail. Phase 4 adds the processing
/// actions (attach to thread, convert, mark done).
private struct CapturedDetail: View {
  let item: Item

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title)
          .font(.system(size: 22, weight: .semibold))
        if let due = dueLine {
          Text(due)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }

      Divider()

      HStack(spacing: 12) {
        labeled("Kind", value: item.kind.rawValue.capitalized)
        labeled("Interruption", value: item.interruptionKind.rawValue.capitalized)
        labeled("Due", value: item.dueKind.rawValue.capitalized)
      }

      Spacer()

      Text("Captured-item processing actions (attach to thread, convert, mark done) are coming in Phase 4.")
        .font(.footnote)
        .foregroundStyle(.tertiary)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var dueLine: String? {
    guard let due = item.dueAt else { return nil }
    let date = Date(timeIntervalSince1970: TimeInterval(due))
    let f = DateFormatter()
    f.dateStyle = .full
    f.timeStyle = .short
    f.doesRelativeDateFormatting = true
    return "Due " + f.string(from: date)
  }

  private func labeled(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.tertiary)
      Text(value)
        .font(.system(size: 13, weight: .medium))
    }
  }
}
