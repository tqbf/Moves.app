import AppKit
import SwiftUI

/// A floating, non-activating capture palette. One text field, an inline
/// preview of the parsed result, and a confirm line after save. Esc closes;
/// Enter saves. Backed by `NSPanel` so it floats over any focused app and
/// doesn't steal Dock focus — see INITIAL-PLAN §4.4 / §5.6–§5.7.
///
/// Lifetime model: one window/controller for the whole app, owned by
/// `CapturePaletteController` (the global hotkey shows/hides it). The view
/// itself is stateless beyond its own draft string.
struct CapturePaletteView: View {
  @Environment(AppStore.self) private var store

  var onDismiss: () -> Void

  @State private var draft: String = ""
  @State private var lastSaved: ParsedCapture?
  @FocusState private var fieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      // The text field.
      TextField("Capture (try \"pull rice in 18m\")", text: $draft)
        .textFieldStyle(.plain)
        .font(.system(size: 16, weight: .regular))
        .focused($fieldFocused)
        .onSubmit(save)

      // Confirm line + live parse preview. Heaviest visual emphasis is on
      // the last-saved confirm; the live preview is muted.
      Group {
        if let lastSaved {
          Text("Saved \(describe(lastSaved))")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .transition(.opacity)
        } else if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
          let preview = CaptureParser.parse(draft, now: Date())
          Text(previewLine(for: preview))
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.tertiary)
        } else if store.notificationsDenied {
          Label("Alerts disabled in System Settings — captures will still save", systemImage: "bell.slash")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.secondary)
        } else {
          Text("Enter to save · Esc to cancel")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(16)
    .frame(width: 460)
    .background(.background)
    .onAppear {
      draft = ""
      lastSaved = nil
      fieldFocused = true
    }
    .onExitCommand(perform: onDismiss)
    .onKeyPress(.escape) {
      onDismiss()
      return .handled
    }
  }

  // MARK: - Actions

  private func save() {
    let input = draft
    guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    Task {
      if let parsed = await store.capture(input) {
        lastSaved = parsed
        draft = ""
        // Brief dwell so the user sees the confirm, then dismiss.
        try? await Task.sleep(nanoseconds: 700_000_000)
        onDismiss()
      }
    }
  }

  // MARK: - Display helpers

  private func describe(_ parsed: ParsedCapture) -> String {
    if let due = parsed.dueAt {
      return "reminder: \(parsed.title) — \(Self.formatter.string(from: due))"
    }
    return "capture: \(parsed.title)"
  }

  private func previewLine(for parsed: ParsedCapture) -> String {
    if let due = parsed.dueAt {
      let kind = parsed.interruptionKind == .hard ? "hard" : "soft"
      return "→ \(parsed.title) · \(Self.formatter.string(from: due)) · \(kind)"
    }
    return "→ \(parsed.title) · no deadline"
  }

  /// Short relative-style date formatter — "today 4:00 PM", "Fri 5:00 PM",
  /// or the ISO-ish fallback.
  private static let formatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    f.doesRelativeDateFormatting = true
    return f
  }()
}

// MARK: - Window controller

/// Owns the floating `NSPanel` that hosts `CapturePaletteView`. Singleton-
/// per-app; the global capture hotkey calls `toggle()`.
@MainActor
final class CapturePaletteController {
  private weak var store: AppStore?
  private var window: NSPanel?

  init(store: AppStore) {
    self.store = store
  }

  /// Show the palette (centered, key) or close it if already visible.
  func toggle() {
    if let window, window.isVisible {
      close()
      return
    }
    show()
  }

  /// Show the palette and focus its text field.
  func show() {
    guard let store else { return }
    let panel = window ?? makeWindow(store: store)
    self.window = panel
    panel.center()
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  /// Close the palette and clear any leftover confirm state.
  func close() {
    store?.clearLastCapture()
    window?.orderOut(nil)
  }

  // MARK: - Build

  private func makeWindow(store: AppStore) -> NSPanel {
    let hosting = NSHostingController(
      rootView: CapturePaletteView(onDismiss: { [weak self] in self?.close() })
        .environment(store)
    )

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 110),
      styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
      backing: .buffered,
      defer: false
    )
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isMovableByWindowBackground = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.contentViewController = hosting
    return panel
  }
}
