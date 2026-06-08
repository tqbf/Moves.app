import KeyboardShortcuts
import SwiftUI
import UserNotifications

/// Single shortcut name for the global capture hotkey. Default is
/// `Option + Space` — chosen because (a) Cmd+Space is Spotlight and Cmd-
/// Shift-Space is Alfred/Raycast territory, (b) Option+Space doesn't clash
/// with any system shortcut on a stock macOS install, (c) it's still one
/// chord on every keyboard. Users can rebind via Settings later (Phase 6).
extension KeyboardShortcuts.Name {
  // KeyboardShortcuts.Name is non-Sendable but the library reads it from
  // its own MainActor-bound API; this declaration is only ever touched on
  // the main actor in practice. `nonisolated(unsafe)` matches the upstream
  // README's recommendation for Swift 6 strict-concurrency mode.
  nonisolated(unsafe) static let capture = Self(
    "capture",
    default: .init(.space, modifiers: [.option])
  )
}

@main
struct MovesApp: App {
  @State private var store = AppStore()
  @State private var capturePalette: CapturePaletteController?
  @State private var notificationDelegate: NotificationDelegate?

  var body: some Scene {
    Window("Moves", id: PopoverWindowID.main.rawValue) {
      RootWindow()
        .environment(store)
        .frame(minWidth: 760, minHeight: 480)
        .task { await bootstrap() }
    }
    .defaultSize(width: 980, height: 640)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("New Thread") { store.addThread(title: "New Thread") }
          .keyboardShortcut("n")
        Button("Capture…") { capturePalette?.show() }
          .keyboardShortcut("k", modifiers: [.command, .shift])
      }
    }

    // Phase-3 flow windows. Each runs as its own SwiftUI `Window` scene
    // because `MenuBarExtra`'s popover auto-dismisses on focus loss —
    // a SwiftUI `.sheet` modifier would die with its host. The scenes
    // read their context from `AppStore.pendingFlow`, which the popover
    // stages before calling `openWindow(id:)`.
    Window("Stop", id: PopoverWindowID.stop.rawValue) {
      StopSheet()
        .environment(store)
    }
    .windowResizability(.contentSize)
    .defaultPosition(.center)

    Window("Switch", id: PopoverWindowID.switchFlow.rawValue) {
      SwitchSheet()
        .environment(store)
    }
    .windowResizability(.contentSize)
    .defaultPosition(.center)

    Window("Park", id: PopoverWindowID.park.rawValue) {
      ParkSheet()
        .environment(store)
    }
    .windowResizability(.contentSize)
    .defaultPosition(.center)

    MenuBarExtra {
      MenuPopoverView()
        .environment(store)
    } label: {
      // Plain-text "•N" suffix matches INITIAL-PLAN §16's "menu-bar icon may
      // show a simple badge". SwiftUI's MenuBarExtra label renders the icon
      // and any sibling Text views in the bar — but Label { Text } icon:
      // { Image } collapses to just the icon. An HStack keeps both visible.
      HStack(spacing: 2) {
        Image(systemName: "figure.walk.motion")
        if store.dueOrOverdueHardCount > 0 {
          Text("•\(store.dueOrOverdueHardCount)")
        }
      }
    }
    .menuBarExtraStyle(.window)
  }

  // MARK: - Bootstrap

  /// One-shot startup. Wires the global hotkey, registers the notification
  /// category + delegate, and loads initial data. Safe to call repeatedly —
  /// each side effect is idempotent.
  private func bootstrap() async {
    // Install the controller + delegate exactly once.
    if capturePalette == nil {
      let controller = CapturePaletteController(store: store)
      capturePalette = controller
      // Publish the singleton slot so the popover's Capture button can
      // reach it without re-injecting through the SwiftUI environment.
      CapturePaletteSingleton.shared = controller
    }
    if notificationDelegate == nil {
      let delegate = NotificationDelegate(store: store)
      notificationDelegate = delegate
      UNUserNotificationCenter.current().delegate = delegate
    }

    // Register the snooze category + global hotkey. Notification
    // authorization is intentionally NOT requested here — Phase 2 decision:
    // ask on first capture, not on launch.
    store.reminderScheduler?.registerCategories()
    KeyboardShortcuts.onKeyDown(for: .capture) { [capturePalette] in
      capturePalette?.toggle()
    }

    await store.load()
  }
}
