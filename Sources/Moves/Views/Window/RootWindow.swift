import SwiftUI

/// The main-window root (INITIAL-PLAN §4.2). A two-column `NavigationSplitView`
/// with the §4.2 destinations in the sidebar and the active destination's
/// detail pane on the right. Replaces the Phase-0/1 throwaway `MainView`.
///
/// Daily-driver work happens in the menu-bar popover (Phase 3); this window
/// is the editing/organizing surface. The sidebar is intentionally a flat
/// list — no nested tree, no per-thread sub-rows — per §2.9's "no taxonomy
/// creep". The Threads destination has its own list view; selecting a
/// thread switches the sidebar selection to a `.thread(id)` case which the
/// detail pane resolves.
struct RootWindow: View {
  @Environment(AppStore.self) private var store
  @State private var selection: SidebarDestination? = .available

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 280)
    } detail: {
      // TimelineView ticks once a minute so `isWorkTime` flips automatically
      // at the start/end of the working-hours window without the user
      // having to interact. The store's `refreshWorkTime` is pure-cheap.
      TimelineView(.periodic(from: .now, by: 60)) { context in
        detail
          .onChange(of: context.date) { _, newDate in
            store.refreshWorkTime(now: newDate)
          }
      }
    }
    .navigationTitle("Moves")
    .task { await store.load() }
  }

  // MARK: - Sidebar

  private var sidebar: some View {
    List(selection: $selection) {
      Section {
        sidebarRow(.available, "Available", icon: "figure.walk.motion", badge: store.availableThreads.count)
        sidebarRow(.current, "Current", icon: "play.circle", badge: store.current.threadId == nil ? 0 : 1)
        sidebarRow(.threadsList, "Threads", icon: "rectangle.stack", badge: store.threads.count)
        sidebarRow(.captured, "Captured", icon: "tray", badge: store.capturedItems.count)
        sidebarRow(.deadlines, "Deadlines", icon: "calendar.badge.clock", badge: store.deadlineItems.count)
        sidebarRow(.parkingLot, "Parking Lot", icon: "pause.circle", badge: store.threads(matching: .parked).count)
      }
      Section {
        sidebarRow(.settings, "Settings", icon: "gearshape", badge: 0)
      }
    }
    .listStyle(.sidebar)
  }

  @ViewBuilder
  private func sidebarRow(_ tag: SidebarDestination, _ title: String, icon: String, badge: Int) -> some View {
    HStack(spacing: 8) {
      Label(title, systemImage: icon)
      Spacer(minLength: 0)
      if badge > 0 {
        Text("\(badge)")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.tertiary)
          .monospacedDigit()
      }
    }
    .tag(tag)
  }

  // MARK: - Detail

  @ViewBuilder
  private var detail: some View {
    switch selection {
    case .available, .none:
      AvailableView(onSelectThread: routeToThread)
    case .current:
      CurrentDetailView(onSelectThread: routeToThread)
    case .threadsList:
      ThreadsListView(onSelectThread: routeToThread)
    case let .thread(id):
      if let thread = store.thread(id: id) {
        ThreadDetailView(thread: thread)
      } else {
        ContentUnavailableView("Thread not found", systemImage: "questionmark.folder")
      }
    case .captured:
      CapturedView()
    case .deadlines:
      DeadlinesView()
    case .parkingLot:
      ParkingLotView(onSelectThread: routeToThread)
    case .settings:
      SettingsView()
    }
  }

  private func routeToThread(_ id: String) {
    selection = .thread(id)
  }
}
