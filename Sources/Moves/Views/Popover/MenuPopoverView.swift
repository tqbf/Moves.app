import AppKit
import SwiftUI

/// The Phase-3 menu-bar popover (INITIAL-PLAN §4.1). This is the daily-
/// driver surface for the app — Current / Upcoming / Available / Captured
/// stacked top-to-bottom, with a Capture / Parking Lot / Open App footer.
///
/// The popover hosts the four section views (`CurrentSection`,
/// `UpcomingSection`, `AvailableSection`, `CapturedSection`) and the
/// `now` ticker that drives `HeadroomService`. Modal flows (Stop / Switch
/// / Park) open as separate `Window` scenes because `MenuBarExtra`
/// popovers auto-dismiss on focus loss — a SwiftUI `.sheet` would die
/// with its host.
struct MenuPopoverView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.openWindow) private var openWindow

  /// Updated by the `TimelineView` once a minute so headroom labels stay
  /// fresh while the popover is open. Kept as state-from-timeline so the
  /// rest of the view tree isn't churning on every tick.
  @State private var now: Date = .init()

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      content(at: context.date)
    }
    .frame(width: 320)
    .task { await store.load() }
  }

  // MARK: - Content

  private func content(at now: Date) -> some View {
    let headroom = HeadroomService.resolve(now: now, items: store.upcomingItems)
    return VStack(spacing: 0) {
      header

      Divider()

      // ScrollView removed: inside MenuBarExtra's window popover it
      // proposes unbounded height to its children and the section content
      // collapses to zero. The popover already scrolls itself if total
      // content overflows the OS-imposed max height, so the sections can
      // stack directly in a VStack.
      VStack(spacing: 0) {
        CurrentSection(currentSegment: currentSegmentForCurrentThread)
        Divider().padding(.horizontal, 14)

        UpcomingSection(headroom: headroom)
        Divider().padding(.horizontal, 14)

        AvailableSection()
        Divider().padding(.horizontal, 14)

        CapturedSection()
      }

      Divider()

      footer
    }
  }

  /// Phase 5 wiring: the current thread's active (or first pending) segment,
  /// resolved from the cached `segmentsByThread` so the popover renders the
  /// active segment header line in CurrentSection. CompleteSegmentSheet
  /// updates the cache via `rebuildAvailable`, so the popover follows.
  private var currentSegmentForCurrentThread: Segment? {
    guard let id = store.current.threadId,
          let thread = store.thread(id: id) else { return nil }
    return store.currentSegment(for: thread)
  }

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text("Moves")
        .font(.headline)
      Spacer()
      // Three-state urgency chip mirroring the menubar tint:
      //   .overdue → "•N overdue", red — matches menubar red chip
      //   .near    → "•N soon",    orange — menubar shows tint-only,
      //              but here we have the horizontal room for a count
      //   .none    → no chip
      // Phase 6: gated on the badge-enabled preference via
      // `renderedDeadlineUrgency`. A user who turned the badge off
      // sees neither tint nor chip.
      switch store.renderedDeadlineUrgency {
      case .overdue:
        Text("•\(store.renderedBadgeCount) overdue")
          .font(.caption)
          .fontWeight(.medium)
          .foregroundStyle(.red)
          .accessibilityLabel("\(store.renderedBadgeCount) overdue")
      case .near:
        Text("•\(store.dueSoonHardCount) soon")
          .font(.caption)
          .fontWeight(.medium)
          .foregroundStyle(.orange)
          .accessibilityLabel("\(store.dueSoonHardCount) approaching")
      case .none:
        EmptyView()
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }

  // MARK: - Footer

  private var footer: some View {
    // 320pt-wide popover. "Park" and "Open" (short labels) read as native
    // Mac controls; icon-only versions force hover-tooltip discovery,
    // which isn't how menu-bar popovers usually navigate. Capture stays
    // primary (label + icon + global shortcut hint).
    HStack(spacing: 8) {
      Button {
        CapturePaletteSingleton.shared?.show()
      } label: {
        Label("Capture", systemImage: "plus.circle")
          .labelStyle(.titleAndIcon)
      }
      .buttonStyle(.bordered)
      .keyboardShortcut("k", modifiers: [.command, .shift])
      .help("Open capture palette (⇧⌘K or ⌥Space)")

      Spacer()

      // "Parked" (noun, destination) avoids colliding with CurrentSection's
      // "Park" (verb, action). Reads as "navigate to the parked-threads
      // view", distinct from "park the current thread".
      Button("Parked") {
        openWindow(id: PopoverWindowID.main.rawValue)
        NSApp.activate(ignoringOtherApps: true)
      }
      .buttonStyle(.bordered)
      .keyboardShortcut("p", modifiers: [.command, .shift])
      .help("Parking Lot — view parked threads (⇧⌘P; dedicated pane lands in Phase 4)")

      Button("Open") {
        openWindow(id: PopoverWindowID.main.rawValue)
        NSApp.activate(ignoringOtherApps: true)
      }
      .buttonStyle(.bordered)
      .keyboardShortcut("o", modifiers: [.command, .shift])
      .help("Open the main window (⇧⌘O)")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }
}

/// One-slot stash for the global `CapturePaletteController` so the popover's
/// Capture button can reach it without re-injecting the controller through
/// the SwiftUI environment. `MovesApp.bootstrap()` writes the slot once at
/// startup; reads happen on user click. Single-writer / single-reader on
/// the main actor, so the implicit non-atomic load is fine.
@MainActor
enum CapturePaletteSingleton {
  static weak var shared: CapturePaletteController?
}
