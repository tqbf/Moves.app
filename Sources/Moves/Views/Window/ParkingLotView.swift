import SwiftUI

/// "Parking Lot" pane in the main window (INITIAL-PLAN §4.2). Lists every
/// parked thread, with an "Unpark" button per row that flips status back
/// to active.
struct ParkingLotView: View {
  @Environment(AppStore.self) private var store
  var onSelectThread: (String) -> Void

  var body: some View {
    let parked = store.threads(matching: .parked)
    PaneShell(title: "Parking Lot", subtitle: "\(parked.count) parked thread\(parked.count == 1 ? "" : "s")") {
      if parked.isEmpty {
        ContentUnavailableView(
          "Nothing parked",
          systemImage: "pause.circle",
          description: Text("Parked threads show up here. Unpark to bring one back to Available.")
        )
      } else {
        VStack(spacing: 0) {
          ForEach(parked) { thread in
            ParkedRow(thread: thread, onOpen: { onSelectThread(thread.id) })
            if thread.id != parked.last?.id {
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

private struct ParkedRow: View {
  let thread: Thread
  let onOpen: () -> Void
  @Environment(AppStore.self) private var store
  @State private var hovering = false

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
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(hovering ? Color.primary.opacity(0.04) : Color.clear)
    .onHover { hovering = $0 }
  }
}
