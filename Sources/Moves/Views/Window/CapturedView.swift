import SwiftUI

/// "Captured" pane in the main window (INITIAL-PLAN §4.2, §13). All
/// captured-status items — the inbox. Processing actions live on each
/// row's context menu / overflow menu (`CapturedRow`).
struct CapturedView: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    PaneShell(title: "Captured", subtitle: "\(store.capturedItems.count) item\(store.capturedItems.count == 1 ? "" : "s")") {
      if store.capturedItems.isEmpty {
        ContentUnavailableView(
          "Inbox is empty",
          systemImage: "tray",
          description: Text("Hit ⌥Space to capture a reminder, task, or note.")
        )
      } else {
        VStack(spacing: 0) {
          ForEach(store.capturedItems) { item in
            CapturedRow(item: item)
            if item.id != store.capturedItems.last?.id {
              Divider().padding(.leading, 12)
            }
          }
        }
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.background.secondary)
        )
      }
    }
  }
}
