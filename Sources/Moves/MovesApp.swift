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

  /// BLACK CHESS KNIGHT (U+265E) rendered through NSAttributedString into
  /// a template NSImage. The system tints templates for menu-bar context
  /// automatically (white in dark menu bars, black in light), and a
  /// rendered-image path gets us a thicker, more legible glyph than
  /// SwiftUI's `Text("♞").font(.system(weight: .black))` — chess piece
  /// glyphs in San Francisco are weight-invariant.
  fileprivate static let knightTemplate: NSImage = {
    let glyph = "\u{265E}"
    let pt: CGFloat = 18
    let font = NSFont.systemFont(ofSize: pt, weight: .black)
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: NSColor.black,
    ]
    let attr = NSAttributedString(string: glyph, attributes: attrs)
    let bounds = attr.size()
    let size = NSSize(width: ceil(bounds.width), height: ceil(bounds.height))
    let image = NSImage(size: size)
    image.lockFocus()
    attr.draw(at: .zero)
    image.unlockFocus()
    image.isTemplate = true
    return image
  }()

  init() {
    // SwiftPM (Swift 6.3) generates `Bundle.module` as
    //   Bundle.main.bundleURL.appendingPathComponent("<Name>.bundle")
    // — i.e. looks at the .app root, NOT Contents/Resources/. macOS
    // codesign refuses to seal arbitrary files at the .app root, so we
    // ship the real bundle in Contents/Resources/ and rely on a runtime
    // symlink to satisfy the lookup. This `init` runs before any view
    // (and therefore any `Bundle.module` access) is constructed, so the
    // symlink exists by the time `String.localized.getter` fires.
    //
    // The symlink is created lazily; if it already exists, this is a
    // no-op. Failure is silent — the worst case is the same crash the
    // user already sees.
    let appURL = Bundle.main.bundleURL
    let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
    guard let contents = try? FileManager.default
            .contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil) else { return }
    for url in contents where url.pathExtension == "bundle" {
      let name = url.lastPathComponent
      let linkPath = appURL.appendingPathComponent(name).path
      if !FileManager.default.fileExists(atPath: linkPath) {
        try? FileManager.default.createSymbolicLink(
          atPath: linkPath,
          withDestinationPath: "Contents/Resources/\(name)"
        )
      }
    }
  }

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
      // The menu-bar icon is the BLACK CHESS KNIGHT (U+265E, ♞), drawn
      // through `Text` so the system can template it for light/dark mode.
      // Tint flips to red when there's a due/overdue hard item so a
      // glance at the menu bar conveys urgency without opening the
      // popover — INITIAL-PLAN §16 ("menu-bar icon may show a simple
      // badge"). `renderedBadgeCount` honors the Phase-6 badge-enable
      // preference, so a user who disabled the badge gets the neutral
      // knight even with deadlines approaching.
      HStack(spacing: 2) {
        // Pre-rendered template NSImage of the chess knight glyph. The
        // raw `Text("♞")` rendered too thin at menu-bar size because the
        // glyph doesn't have weighted variants in San Francisco —
        // `.weight(.black)` is a no-op on symbol characters. Rendering
        // through NSImage at 18pt with isTemplate=true lets the menu bar
        // ink it for light/dark mode while keeping the bolder look of a
        // larger-font draw.
        Image(nsImage: Self.knightTemplate)
          .renderingMode(store.renderedBadgeCount > 0 ? .original : .template)
          .foregroundStyle(store.renderedBadgeCount > 0 ? Color.red : .primary)
          .accessibilityLabel("Moves")
        if store.renderedBadgeCount > 0 {
          Text("\(store.renderedBadgeCount)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.red)
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
