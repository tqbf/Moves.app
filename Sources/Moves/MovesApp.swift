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
    Window("Moves", id: "main") {
      MainView()
        .environment(store)
        .frame(minWidth: 720, minHeight: 440)
        .task { await bootstrap() }
    }
    .defaultSize(width: 920, height: 600)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("New Thread") { store.addThread(title: "New Thread") }
          .keyboardShortcut("n")
        Button("Capture…") { capturePalette?.show() }
          .keyboardShortcut("k", modifiers: [.command, .shift])
      }
    }

    MenuBarExtra {
      MenuBarContent()
        .environment(store)
    } label: {
      // Plain-text "•N" suffix matches INITIAL-PLAN §16's "menu-bar icon may
      // show a simple badge" — no custom drawing. SwiftUI's MenuBarExtra
      // label renders a `Text` next to the SF Symbol.
      Label {
        if store.dueOrOverdueHardCount > 0 {
          Text(" •\(store.dueOrOverdueHardCount)")
        }
      } icon: {
        Image(systemName: "figure.walk.motion")
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
      capturePalette = CapturePaletteController(store: store)
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
