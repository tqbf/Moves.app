import SwiftUI

/// "Parking Lot" pane in the main window (INITIAL-PLAN §4.2). Lists every
/// parked thread, with an "Unpark" button per row that flips status back
/// to active and a leading swipe-to-delete affordance.
///
/// Batch 6, item 24 — parked-with-due-date. Each row independently fetches
/// the earliest open-item deadline for its thread, surfacing the orange
/// `DeadlineChip` in its parked variant when present (reduced opacity +
/// "Parked" capsule). A parked thread with a future deadline is still
/// time-sensitive; the reviewer's punch list called this out as a
/// "missing state". `openItemsByThread` only covers active threads, so
/// the row resolves the deadline directly via the item repository on
/// appear.
struct ParkingLotView: View {
  @Environment(AppStore.self) private var store
  var onSelectThread: (String) -> Void

  var body: some View {
    let parked = store.threads(matching: .parked)
    PaneListShell(title: "Parking Lot", count: parked.count) {
      if parked.isEmpty {
        // Batch 8, item 28 — friendly empty state without an action.
        // Parking is intentionally optional per the §2 model (it's the
        // "I'll come back to this later" affordance), so the empty state
        // shouldn't push the user toward filling it.
        ContentUnavailableView(
          "Nothing parked",
          systemImage: "archivebox",
          description: Text("Parked threads show up here. Park anything you want out of the Available list for a while.")
        )
      } else {
        List {
          ForEach(parked) { thread in
            ParkedRow(thread: thread, onOpen: { onSelectThread(thread.id) })
              .listRowSeparator(.hidden)
              .listRowInsets(EdgeInsets(
                top: PaneMetrics.listRowVertical,
                leading: PaneMetrics.listRowLeading,
                bottom: PaneMetrics.listRowVertical,
                trailing: PaneMetrics.listRowTrailing
              ))
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
      }
    }
  }
}

private struct ParkedRow: View {
  let thread: Thread
  let onOpen: () -> Void
  @Environment(AppStore.self) private var store

  /// Earliest open-item deadline for this parked thread, fetched once on
  /// appear. `nil` while loading or when the thread has no deadlined
  /// items. We don't keep a global parked-items cache in the store — the
  /// parking lot is a low-traffic surface and one query per row keeps the
  /// invalidation story simple.
  @State private var earliestDeadline: Date?

  var body: some View {
    TaskRow(
      title: thread.title,
      subtitle: thread.breadcrumb.isEmpty ? nil : "Next: \(thread.breadcrumb)",
      deadline: earliestDeadline,
      isParked: earliestDeadline != nil,
      hoverActions: {
        // Hover-revealed Unpark + Open. Batch 7 moves the parking lot's
        // always-visible buttons onto the hover-reveal pattern so the row
        // resting state matches Available / Deadlines.
        RowHoverActionButton(systemName: "play.fill", help: "Unpark") {
          store.setStatus(thread, to: .active)
        }
        RowHoverActionButton(systemName: "arrow.up.right", help: "Open") {
          onOpen()
        }
      }
    )
    .contextMenu {
      Button("Unpark") { store.setStatus(thread, to: .active) }
      Button("Open Thread") { onOpen() }
      Divider()
      Button("Delete", role: .destructive) { store.delete(thread) }
    }
    .task(id: thread.id) {
      await loadDeadline()
    }
  }

  private func loadDeadline() async {
    do {
      let items = try await store.itemRepository.openForThread(thread.id)
      let earliest = items.compactMap(\.dueAt).min()
      earliestDeadline = earliest.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    } catch {
      earliestDeadline = nil
    }
  }
}
