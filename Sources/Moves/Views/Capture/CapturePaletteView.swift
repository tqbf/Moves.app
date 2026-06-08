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
      // The text field — Spotlight-style: big plain text, no border, the
      // panel itself is the visual chrome.
      TextField("Capture (try \"pull rice in 18m\")", text: $draft)
        .textFieldStyle(.plain)
        .font(.system(size: 22, weight: .regular))
        .focused($fieldFocused)
        .onSubmit(save)

      // Status line. Three states:
      //   • Just saved: green checkmark + "Saved <title>" (briefly visible
      //     before the panel auto-dismisses).
      //   • Typing with a parsed deadline: title preview + an accent-tinted
      //     chip carrying the parsed time. The chip is the visual signal
      //     that a deadline was recognized — captures save with or without
      //     one, but the chip removes any doubt about whether the parser
      //     picked up the time phrase the user typed.
      //   • Typing without a parsed deadline: subtle "Saves as a capture"
      //     hint so the user knows Return will still persist the item.
      Group {
        if let lastSaved {
          savedLine(for: lastSaved)
            .transition(.opacity)
        } else if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
          previewRow(for: CaptureParser.parse(draft, now: Date()))
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
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .frame(width: 540)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .onAppear {
      draft = ""
      lastSaved = nil
      // Defer first-responder assignment one runloop tick: when the host
      // NSPanel finishes becoming key, @FocusState resolves correctly.
      // Setting fieldFocused = true synchronously in onAppear races the
      // panel's key transition and drops typed input on first show.
      DispatchQueue.main.async {
        fieldFocused = true
      }
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

  /// "Saved" confirmation row, shown briefly before the panel dismisses.
  /// Uses a green check + the saved title so the user has clear feedback
  /// that the capture persisted, regardless of whether a deadline was parsed.
  @ViewBuilder
  private func savedLine(for parsed: ParsedCapture) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
      Text("Saved")
        .fontWeight(.medium)
      Text(parsed.title)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      if let due = parsed.dueAt {
        deadlineChip(for: due, kind: parsed.interruptionKind)
      }
    }
    .font(.system(size: 12))
  }

  /// Live preview row while the user is typing. Title on the left, an
  /// accent-tinted deadline chip on the right when one was recognized.
  /// The "no deadline" wording is gone — the absence of a chip is the
  /// signal, and the trailing hint explicitly states the item will save.
  @ViewBuilder
  private func previewRow(for parsed: ParsedCapture) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "arrow.turn.down.right")
        .foregroundStyle(.tertiary)
      Text(parsed.title.isEmpty ? "(enter a title)" : parsed.title)
        .foregroundStyle(parsed.title.isEmpty ? .tertiary : .secondary)
        .lineLimit(1)
      if let due = parsed.dueAt {
        deadlineChip(for: due, kind: parsed.interruptionKind)
      } else {
        Text("· saves as a capture")
          .foregroundStyle(.tertiary)
      }
      Spacer(minLength: 4)
      Text("⏎")
        .foregroundStyle(.tertiary)
    }
    .font(.system(size: 12))
  }

  /// Tinted pill displaying the parsed deadline + interruption kind.
  /// `.hard` uses orange (matches the menubar badge for due/overdue hard
  /// items); `.soft` uses accent. The pill IS the visual indication that
  /// a deadline was recognized — it's the difference between a quiet
  /// "no deadline" line the user can miss and an unmistakable "yes, I
  /// got that the deadline is X" signal.
  @ViewBuilder
  private func deadlineChip(for due: Date, kind: InterruptionKind) -> some View {
    let tint: Color = (kind == .hard) ? .orange : .accentColor
    HStack(spacing: 4) {
      Image(systemName: kind == .hard ? "bell.fill" : "calendar")
        .font(.system(size: 10, weight: .semibold))
      Text(Self.formatter.string(from: due))
        .font(.system(size: 11, weight: .medium))
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 2)
    .foregroundStyle(tint)
    .background(
      Capsule(style: .continuous)
        .fill(tint.opacity(0.15))
    )
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

  /// Show the palette and focus its text field. Replaces the hosting
  /// controller's root view on each show so the palette always opens with
  /// an empty draft and no leftover "Saved …" confirmation. Without this
  /// reset, the view's `@State` survives `orderOut`/`orderFront` cycles
  /// (the SwiftUI subtree never unmounts) and a previous capture's
  /// confirm line bleeds into the next session.
  func show() {
    guard let store else { return }
    let panel = window ?? makeWindow(store: store)
    self.window = panel
    panel.contentViewController = NSHostingController(
      rootView: CapturePaletteView(onDismiss: { [weak self] in self?.close() })
        .environment(store)
    )
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
      contentRect: NSRect(x: 0, y: 0, width: 540, height: 100),
      styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isMovableByWindowBackground = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    // Default for .utilityWindow / panel styles is true — the panel only
    // becomes key when a control "needs" focus. SwiftUI's @FocusState
    // doesn't fire that signal reliably across hosted panels, so typing
    // gets dropped on first show. Force the panel to take key focus when
    // frontmost so the field is immediately editable.
    panel.becomesKeyOnlyIfNeeded = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.contentViewController = hosting
    return panel
  }
}
