import SwiftUI

/// Throwaway phase-1 main window. Phase 4 replaces this with the real
/// Available / Threads / Captured / Deadlines / Parking Lot views.
struct MainView: View {
  @Environment(AppStore.self) private var store
  @State private var selection: Thread.ID?
  @State private var newThreadTitle: String = ""
  @FocusState private var addFieldFocused: Bool

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
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

  private var sidebar: some View {
    VStack(spacing: 0) {
      List(selection: $selection) {
        Section("Threads") {
          ForEach(store.threads) { thread in
            ThreadRow(thread: thread)
              .tag(thread.id)
              .contextMenu {
                Button("Delete", role: .destructive) {
                  store.delete(thread)
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

  @ViewBuilder
  private var detail: some View {
    if let selection, let thread = store.thread(id: selection) {
      ThreadDetail(thread: thread)
    } else if store.threads.isEmpty {
      ContentUnavailableView(
        "No Threads Yet",
        systemImage: "figure.walk.motion",
        description: Text("Add your first thread in the sidebar.")
      )
    } else {
      ContentUnavailableView(
        "Pick a Thread",
        systemImage: "hand.point.up.left",
        description: Text("Select a thread from the sidebar to see its details.")
      )
    }
  }

  private func commitAdd() {
    let trimmed = newThreadTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    store.addThread(title: trimmed)
    newThreadTitle = ""
  }
}
