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
  /// User's current per-item alert-offset selection. Seeded from
  /// `AppStore.offsetsForCapture(kind:)` the first time the live parse
  /// recognizes a deadline; the user can then toggle chips before Return.
  /// Cleared when the deadline disappears so a subsequent re-recognition
  /// re-seeds from the (possibly-different) inferred kind.
  @State private var alertSelection: Set<Int> = []
  /// Sentinel so we re-seed `alertSelection` only when the deadline state
  /// transitions from "no deadline parsed" → "deadline parsed", or when the
  /// inferred kind changes (e.g. user types "due" mid-edit and flips the
  /// item from .capture to .task defaults).
  @State private var lastSeededKind: ItemKind?
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

      // Per-item alert-offset chips. Only visible when the live parse
      // recognized a deadline AND we're not on the brief post-save dwell.
      // The chip row owns its own line under the deadline preview so the
      // palette stays tight when no deadline is parsed.
      if lastSaved == nil, let parsed = currentParse, parsed.dueAt != nil {
        AlertOffsetChipRow(selection: $alertSelection)
          .transition(.opacity)
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .frame(width: 620)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .onChange(of: draft) { _, _ in seedAlertSelectionIfNeeded() }
    .onAppear {
      draft = ""
      lastSaved = nil
      alertSelection = []
      lastSeededKind = nil
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

  // MARK: - Live parse

  /// Cheap re-parse of the current draft used by both the preview row and
  /// the chip-row visibility check. `CaptureParser.parse` is pure / fast;
  /// re-computing per body invocation is simpler than caching.
  private var currentParse: ParsedCapture? {
    let trimmed = draft.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    return CaptureParser.parse(draft, now: Date())
  }

  /// Mirror of `AppStore.capture`'s parsed-kind → ItemKind mapping so the
  /// chip row seeds from the matching `offsetsForCapture(kind:)`.
  private func inferredKind(for parsed: ParsedCapture) -> ItemKind {
    switch parsed.interruptionKind {
    case .hard: return .reminder
    case .soft: return .task
    case .none: return .capture
    }
  }

  /// Seed (or re-seed) `alertSelection` from the kind defaults when the
  /// parse transitions into "deadline recognized" or when the inferred
  /// kind changes. We deliberately do NOT overwrite the user's selection
  /// while the inferred kind stays the same — once they've toggled chips,
  /// keystroke noise on the title shouldn't undo their choices.
  private func seedAlertSelectionIfNeeded() {
    guard let parsed = currentParse, parsed.dueAt != nil else {
      // Deadline gone → reset so a fresh recognition re-seeds.
      alertSelection = []
      lastSeededKind = nil
      return
    }
    let kind = inferredKind(for: parsed)
    if lastSeededKind != kind {
      alertSelection = Set(store.offsetsForCapture(kind: kind))
      lastSeededKind = kind
    }
  }

  // MARK: - Actions

  private func save() {
    let input = draft
    guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    // Snapshot the chip selection at submit time. `nil` when there's no
    // parsed deadline so the kind defaults still apply (the chip row was
    // hidden — the user never expressed an opinion either way).
    let parseAtSubmit = CaptureParser.parse(input, now: Date())
    let offsetsOverride: [Int]? = (parseAtSubmit.dueAt != nil)
      ? alertSelection.sorted()
      : nil
    Task {
      if let parsed = await store.capture(input, offsetsOverride: offsetsOverride) {
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
    let hosting = NSHostingController(
      rootView: CapturePaletteView(onDismiss: { [weak self] in self?.close() })
        .environment(store)
    )
    // Let the hosting controller drive the panel's content size from the
    // SwiftUI layout. Without this, the panel keeps the contentRect height
    // set at init (100pt) and the chip row that appears below the deadline
    // preview gets clipped out of view.
    hosting.sizingOptions = [.preferredContentSize]
    panel.contentViewController = hosting
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
    // The chip row that appears below the deadline preview pushes the
    // intrinsic content size; give the hosting controller leave to
    // re-broadcast it so the panel resizes.
    hosting.sizingOptions = [.preferredContentSize]

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 100),
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
