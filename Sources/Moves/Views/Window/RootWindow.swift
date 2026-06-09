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
  /// Cross-scope signal bus. Two flags matter here:
  ///   - `presentOnboarding`: bootstrap or Settings flips it; this view
  ///     opens the onboarding window scene on the true transition.
  ///   - `requestNewThread`: Cmd-N flips it; this view switches the
  ///     sidebar to `.threadsList`. `ThreadsListView` clears it once the
  ///     input is focused — clearing here would race a not-yet-mounted
  ///     ThreadsListView and drop the focus signal.
  @Bindable private var signals = AppSignals.shared

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
    // No navigationTitle — the window title bar is already "Moves" and
    // every pane's PaneShell renders its own large title. Setting one
    // here just adds a redundant secondary heading inside the detail
    // toolbar.
    .navigationTitle("")
    .toolbar { toolbarItems }
    .task { await store.load() }
    .onChange(of: signals.presentOnboarding) { _, requested in
      if requested {
        openWindow(id: PopoverWindowID.onboarding.rawValue)
      }
    }
    .onChange(of: signals.requestNewThread) { _, requested in
      // Switch the sidebar so ThreadsListView mounts; the input focus
      // (and clearing the flag) is owned by ThreadsListView itself.
      if requested {
        selection = .threadsList
      }
    }
    .onAppear {
      // If the bootstrap already flipped the flag before the window
      // mounted, open the onboarding scene now.
      if signals.presentOnboarding {
        openWindow(id: PopoverWindowID.onboarding.rawValue)
      }
    }
    // Publish a "back" action to the focused-scene bus while the user is
    // on a thread detail pane. The App-scope View → "Back to Threads"
    // command (Cmd-[) reads this and disables itself when nil — i.e. on
    // any other top-level destination. No generic browser-history stack:
    // the only meaningful "back" relationship is thread detail → list.
    .focusedSceneValue(\.backFromThread, backAction)
  }

  // MARK: - Toolbar

  /// Top-of-window toolbar strip. Previously empty (wasted real estate
  /// flagged in `plans/ui-glowup.md` item 7). Now hosts:
  ///   - Quick-capture button (opens the global capture palette via the
  ///     same singleton the menu-bar popover uses).
  ///   - Working-status indicator (echoes the Available footer pill but
  ///     in the toolbar so the user knows the state from any pane).
  ///   - A search field stub. Search isn't wired in this batch — the
  ///     field is intentionally a `.disabled` placeholder so the toolbar
  ///     layout is right for batch-7 work, but no fake results can come
  ///     out of it. See TODO below.
  @ToolbarContentBuilder
  private var toolbarItems: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      // TODO: Wire search backend (batch 7). Field is rendered disabled
      // so the layout slot is real and the placeholder reads
      // intentionally "coming soon" rather than broken.
      Spacer()
      WorkingStatusIndicator(isWorkTime: store.isWorkTime)
      Button {
        CapturePaletteSingleton.shared?.show()
      } label: {
        Label("Quick capture", systemImage: "plus.circle")
      }
      .help("Open the capture palette (⌥Space)")
    }
  }

  /// Only non-nil when a thread is currently selected; the App-scope
  /// menu command keys off nil-ness to disable the shortcut everywhere
  /// else (Available, Current, Captured, …) where "back" doesn't mean
  /// anything.
  private var backAction: BackAction? {
    guard case .thread = selection else { return nil }
    return BackAction { selection = .threadsList }
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
      CurrentDetailView(
        onSelectThread: routeToThread,
        onGoAvailable: { selection = .available }
      )
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

/// Compact "Working hours" indicator surfaced in the window toolbar. The
/// state matters everywhere (it changes how Available sorts; in §12 it
/// also gates deemphasis) — but the existing Available footer pill is
/// only visible on that pane. Mirroring it in the toolbar means the user
/// always sees the bit without it competing for content space.
private struct WorkingStatusIndicator: View {
  let isWorkTime: Bool

  var body: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(isWorkTime ? Color.orange : Color.secondary.opacity(0.5))
        .frame(width: 6, height: 6)
      Text(isWorkTime ? "Working" : "Off hours")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(Capsule(style: .continuous).fill(.quaternary))
    .help(isWorkTime ? "Inside the configured working-hours window" : "Outside the configured working-hours window")
  }
}
