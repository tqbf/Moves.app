import SwiftUI

/// "Captured" pane in the main window (INITIAL-PLAN §4.2, §13). All
/// captured-status items — the inbox. Processing actions live on each
/// row's context menu / overflow menu (`CapturedRow`). Swipe-left on a
/// row reveals a destructive Delete button.
struct CapturedView: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    PaneListShell(
      title: "Captured",
      subtitle: "\(store.capturedItems.count) item\(store.capturedItems.count == 1 ? "" : "s")"
    ) {
      if store.capturedItems.isEmpty {
        ContentUnavailableView(
          "Inbox is empty",
          systemImage: "tray",
          description: Text("Hit ⌥Space to capture a reminder, task, or note.")
        )
      } else {
        List {
          ForEach(store.capturedItems) { item in
            CapturedRow(item: item)
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
        // See AvailableView for the focus-ring rationale.
        .focusEffectDisabled()
      }
    }
  }
}
