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
  @Environment(\.openWindow) private var openWindow
  @State private var selection: SidebarDestination? = .available
  /// Watch the onboarding presenter so the RootWindow can open the
  /// onboarding window scene when the bootstrap flips the flag (or the
  /// user clicks "Show onboarding again" in Settings).
  @Bindable private var onboardingPresenter = OnboardingPresenter.shared
  /// Watch the new-thread presenter so Cmd-N from the App-scope menu can
  /// switch the sidebar to `.threadsList`. The flag is cleared by
  /// `ThreadsListView` once it focuses its input — clearing here would
  /// race a not-yet-mounted ThreadsListView and drop the focus signal.
  @Bindable private var newThreadPresenter = NewThreadPresenter.shared

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
    .onChange(of: onboardingPresenter.presentRequested) { _, requested in
      if requested {
        openWindow(id: PopoverWindowID.onboarding.rawValue)
      }
    }
    .onChange(of: newThreadPresenter.requestPending) { _, requested in
      // Switch the sidebar so ThreadsListView mounts; the input focus
      // (and clearing the flag) is owned by ThreadsListView itself.
      if requested {
        selection = .threadsList
      }
    }
    .onAppear {
      // If the bootstrap already flipped the flag before the window
      // mounted, open the onboarding scene now.
      if onboardingPresenter.presentRequested {
        openWindow(id: PopoverWindowID.onboarding.rawValue)
      }
    }
  }

  // MARK: - Sidebar

  private var sidebar: some View {
    List(selection: $selection) {
      Section {
        sidebarRow(.available, "Available", icon: "figure.walk.motion", badge: availableBadgeCount)
        sidebarRow(.current, "Current", icon: "play.circle", badge: store.current.threadId == nil ? 0 : 1)
        sidebarRow(.threadsList, "Threads", icon: "rectangle.stack", badge: store.threads.count)
        sidebarRow(.captured, "Captured", icon: "tray", badge: store.capturedItems.count)
        sidebarRow(.deadlines, "Deadlines", icon: "calendar.badge.clock", badge: store.deadlineItems.count)
        sidebarRow(.parkingLot, "Parking Lot", icon: "pause.circle", badge: store.threads(matching: .parked).count)
      }
      Section {
        // Phase-5 §14 weekly time-log pane. No badge — the weekly view is
        // never "unread" in a way that should pull the user's attention,
        // per the §2.5 "no shame language" rule.
        sidebarRow(.timeLog, "Time Log", icon: "clock.arrow.circlepath", badge: 0)
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom) {
      sidebarFooter
    }
  }

  /// Phase-5: bottom-rail "Import Markdown…" affordance. Opens the
  /// `ImportMarkdownView` window scene where the user can drop a §9 file.
  /// Sits in the sidebar bottom rail (not a destination) because import is
  /// a one-shot action, not a place you navigate to.
  private var sidebarFooter: some View {
    HStack {
      Button {
        openWindow(id: PopoverWindowID.importMarkdown.rawValue)
      } label: {
        Label("Import Markdown…", systemImage: "square.and.arrow.down")
          .font(.system(size: 12))
      }
      .buttonStyle(.borderless)
      .help("Import a regimented thread from a Markdown file (§9 grammar)")
      Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  /// Same projection AvailableView renders, so the sidebar badge count
  /// agrees with what the pane shows. Without this, a thread set to
  /// `hide_during_work` inflated the sidebar badge but vanished from the
  /// pane — user clicks "1" and sees "Nothing available."
  private var availableBadgeCount: Int {
    let filtered = WorkingHoursService.filter(
      available: store.availableThreads,
      isWorkTime: store.isWorkTime,
      hasDeadline: { row in
        (store.openItemsByThread[row.thread.id] ?? []).contains { $0.dueAt != nil }
      }
    )
    return filtered.visible.count + filtered.deemphasized.count
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
    case .timeLog:
      WeeklyView()
    }
  }

  private func routeToThread(_ id: String) {
    selection = .thread(id)
  }
}
