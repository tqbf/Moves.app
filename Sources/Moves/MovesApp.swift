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

    // Phase-5 segment-completion sheet (§5.5). Same Window-scene strategy
    // as Stop/Switch/Park; reads `AppStore.pendingFlow` on appear.
    Window("Complete Segment", id: PopoverWindowID.completeSegment.rawValue) {
      CompleteSegmentSheet()
        .environment(store)
    }
    .windowResizability(.contentSize)
    .defaultPosition(.center)

    // Phase-5 Markdown import sheet (§9). Separate scene so file drop +
    // preview don't fight the popover's focus-loss auto-dismiss.
    Window("Import Markdown", id: PopoverWindowID.importMarkdown.rawValue) {
      ImportMarkdownView()
        .environment(store)
    }
    .windowResizability(.contentSize)
    .defaultPosition(.center)

    // Phase-6 onboarding modal. Hosts the OnboardingView and self-opens
    // when `OnboardingPresenter.shared.presentRequested` flips to true.
    Window("Welcome to Moves", id: PopoverWindowID.onboarding.rawValue) {
      OnboardingHost()
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
      //
      // The badge count routes through `renderedBadgeCount` which honors
      // the Phase-6 badge-enable/disable preference. The image always has
      // an accessibility label so VoiceOver users can identify the
      // menubar icon.
      HStack(spacing: 2) {
        Image(systemName: "figure.walk.motion")
          .accessibilityLabel("Moves")
        if store.renderedBadgeCount > 0 {
          Text("•\(store.renderedBadgeCount)")
            .accessibilityLabel("\(store.renderedBadgeCount) due or overdue")
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

    // Phase 6 §17: on app launch, reconcile pending OS notifications with
    // the persisted item state. Cancel orphans, schedule missing futures,
    // mark fired any hard items whose due_at is already past.
    await store.reconcileAlerts()

    // Phase 6: first-launch onboarding. Triggered when no preferences row
    // exists *or* the stored onboarded_version differs from current. The
    // popover surfaces a sheet that walks through capture-hotkey
    // registration and a first capture. Re-runnable from Settings.
    if store.preferences.onboardedVersion != UserPreferences.currentOnboardingVersion {
      OnboardingPresenter.shared.requestPresent()
    }
  }
}
