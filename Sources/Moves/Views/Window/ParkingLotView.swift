import SwiftUI

/// "Parking Lot" pane in the main window (INITIAL-PLAN §4.2). Lists every
/// parked thread, with an "Unpark" button per row that flips status back
/// to active and a leading swipe-to-delete affordance.
struct ParkingLotView: View {
  @Environment(AppStore.self) private var store
  var onSelectThread: (String) -> Void

  var body: some View {
    let parked = store.threads(matching: .parked)
    PaneListShell {
      if parked.isEmpty {
        ContentUnavailableView(
          "Nothing parked",
          systemImage: "pause.circle",
          description: Text("Parked threads show up here. Unpark to bring one back to Available.")
        )
      } else {
        List {
          ForEach(parked) { thread in
            ParkedRow(thread: thread, onOpen: { onSelectThread(thread.id) })
              .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                  store.delete(thread)
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
}

private struct ParkedRow: View {
  let thread: Thread
  let onOpen: () -> Void
  @Environment(AppStore.self) private var store

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(thread.title)
          .font(.system(size: 14, weight: .medium))
          .lineLimit(1)
        if !thread.breadcrumb.isEmpty {
          Text("Next: \(thread.breadcrumb)")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer()
      Button("Unpark") { store.setStatus(thread, to: .active) }
        .buttonStyle(.bordered)
      Button("Open") { onOpen() }
        .buttonStyle(.bordered)
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
  }
}
