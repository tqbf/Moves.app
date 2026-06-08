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

      ScrollView {
        VStack(spacing: 0) {
          CurrentSection(currentSegment: nil)
          Divider().padding(.horizontal, 14)

          UpcomingSection(headroom: headroom)
          Divider().padding(.horizontal, 14)

          AvailableSection()
          Divider().padding(.horizontal, 14)

          CapturedSection()
        }
      }
      .frame(maxHeight: 460)

      Divider()

      footer
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text("Moves")
        .font(.system(size: 13, weight: .semibold))
      Spacer()
      if store.dueOrOverdueHardCount > 0 {
        Text("•\(store.dueOrOverdueHardCount) due")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.orange)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }

  // MARK: - Footer

  private var footer: some View {
    HStack(spacing: 8) {
      Button {
        CapturePaletteSingleton.shared?.show()
      } label: {
        Label("Capture", systemImage: "plus.circle")
          .labelStyle(.titleAndIcon)
      }
      .buttonStyle(.bordered)

      Button {
        // Parking Lot has its own pane in Phase 4's main window; until
        // then, open the main window so the user has somewhere to land.
        openWindow(id: PopoverWindowID.main.rawValue)
        NSApp.activate(ignoringOtherApps: true)
      } label: {
        Label("Parking Lot", systemImage: "tray.and.arrow.down")
          .labelStyle(.titleAndIcon)
      }
      .buttonStyle(.bordered)
      .help("Opens the main window — dedicated Parking Lot pane lands in Phase 4")

      Spacer()

      Button {
        openWindow(id: PopoverWindowID.main.rawValue)
        NSApp.activate(ignoringOtherApps: true)
      } label: {
        Label("Open App", systemImage: "macwindow")
          .labelStyle(.titleAndIcon)
      }
      .buttonStyle(.bordered)
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
