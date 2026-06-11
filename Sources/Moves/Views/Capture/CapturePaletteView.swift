import AppKit
import SwiftUI

/// A floating, non-activating capture palette. One text field, an inline
/// preview of the parsed result, and a confirm line after save. Esc closes;
/// Enter saves. Backed by `NSPanel` so it floats over any focused app and
/// doesn't steal Dock focus — see INITIAL-PLAN §4.4 / §5.6–§5.7.
///
/// Lifetime model: one window/controller for the whole app, owned by
/// `CapturePaletteController` (the global hotkey shows/hides it). The view
/// itself is stateless beyond its own draft string and a small set of
/// transient overlay flags (manual due override, alert-selection seed).
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
  /// Manual deadline override set by the chip's date-picker popover. While
  /// non-nil, this wins over whatever the parser finds in the current
  /// draft — the user has explicitly picked a time, and subsequent
  /// keystrokes on the title shouldn't clobber it. Cleared via the chip's
  /// X button, which also re-allows parser-driven recognition.
  @State private var manualDueAt: Date?
  /// Whether the chip-tap popover is currently presented. Local @State so
  /// SwiftUI owns the dismiss-on-outside-tap behavior; the panel itself
  /// keeps key focus (NSPanel.becomesKeyOnlyIfNeeded = false) so the
  /// popover overlay doesn't shut the palette.
  @State private var datePickerOpen: Bool = false
  /// Scratch value the popover's DatePicker binds to. Committed to
  /// `manualDueAt` only when the user presses "Set" — letting the picker
  /// surface ephemeral exploration without clobbering the current
  /// override on every spinner click.
  @State private var pickerDraftDate: Date = Date()
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
      //   • Typing with parser content: cleaned title + parsed/manual due
      //     chip + destination capsule, each with its own visual slot so
      //     the user can read the parse at a glance.
      //   • Typing with no draft yet: subtle keyboard-hint line.
      Group {
        if let lastSaved {
          savedLine(for: lastSaved)
            .transition(.opacity)
        } else if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
          previewRow(for: currentParse ?? CaptureParser.parse(draft, now: Date()))
        } else if store.notificationsDenied {
          Label("Alerts disabled in System Settings — captures will still save", systemImage: "bell.slash")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.secondary)
        } else {
          Text("Start typing to capture")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      // Per-item alert-offset chips. Only visible when the user has an
      // effective deadline (parsed OR manual). When there's no due date,
      // the row would add cognitive load with nothing to act on — gate it
      // behind `effectiveDueAt != nil`.
      if lastSaved == nil, effectiveDueAt != nil {
        AlertOffsetChipRow(selection: $alertSelection)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }

      // Footer: trailing Create button (stronger affordance than the
      // hooked-Return glyph) + an "esc to dismiss" key-cap hint at the
      // trailing edge of the overlay.
      if lastSaved == nil {
        footer
      }
    }
    // Pair the `.transition` above with a `value:`-bound animation so the
    // chip row actually fades in when the parse first recognizes a
    // deadline. Without this binding `.transition` is dormant — SwiftUI
    // only animates state changes when the surrounding context declares
    // an animation.
    .animation(.easeOut(duration: 0.18), value: chipRowVisible)
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .frame(width: 620)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .onChange(of: draft) { _, _ in seedAlertSelectionIfNeeded() }
    .onChange(of: manualDueAt) { _, _ in seedAlertSelectionIfNeeded() }
    .onAppear {
      draft = ""
      lastSaved = nil
      alertSelection = []
      lastSeededKind = nil
      manualDueAt = nil
      datePickerOpen = false
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

  /// The deadline currently in effect for the in-flight draft — the
  /// manual override if the user picked one, otherwise the parser result.
  /// Drives both the chip rendering and the alert-row visibility.
  private var effectiveDueAt: Date? {
    if let manualDueAt { return manualDueAt }
    return currentParse?.dueAt
  }

  /// Whether the chip row should be on screen right now. Derived so the
  /// `.animation(_:value:)` modifier on the enclosing VStack has a stable
  /// `Equatable` value to watch for the `.transition` to fire.
  private var chipRowVisible: Bool {
    lastSaved == nil && effectiveDueAt != nil
  }

  /// Mirror of `AppStore.capture`'s parsed-kind → ItemKind mapping so the
  /// chip row seeds from the matching `offsetsForCapture(kind:)`. A manual
  /// override is treated as `.reminder` (hard deadline) — the picker is
  /// reserved for deadlines that matter.
  private func inferredKind(for parsed: ParsedCapture?) -> ItemKind {
    if manualDueAt != nil { return .reminder }
    guard let parsed else { return .capture }
    switch parsed.interruptionKind {
    case .hard: return .reminder
    case .soft: return .task
    case .none: return .capture
    }
  }

  /// Seed (or re-seed) `alertSelection` from the kind defaults when the
  /// effective-deadline state transitions into "deadline available" or when
  /// the inferred kind changes. We deliberately do NOT overwrite the user's
  /// selection while the inferred kind stays the same — once they've
  /// toggled chips, keystroke noise on the title shouldn't undo their
  /// choices.
  private func seedAlertSelectionIfNeeded() {
    guard effectiveDueAt != nil else {
      // Deadline gone → reset so a fresh recognition re-seeds.
      alertSelection = []
      lastSeededKind = nil
      return
    }
    let kind = inferredKind(for: currentParse)
    if lastSeededKind != kind {
      alertSelection = Set(store.offsetsForCapture(kind: kind))
      lastSeededKind = kind
    }
  }

  // MARK: - Actions

  private func save() {
    let input = draft
    guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    let parseAtSubmit = CaptureParser.parse(input, now: Date())
    // Snapshot the chip selection at submit time. `nil` when there's no
    // effective deadline so the kind defaults still apply (the chip row was
    // hidden — the user never expressed an opinion either way).
    let hasDeadlineAtSubmit = (manualDueAt != nil) || (parseAtSubmit.dueAt != nil)
    let offsetsOverride: [Int]? = hasDeadlineAtSubmit ? alertSelection.sorted() : nil
    let dueOverride: DueOverride? = manualDueAt.map { DueOverride(dueAt: $0) }
    Task {
      if let parsed = await store.capture(
        input,
        offsetsOverride: offsetsOverride,
        dueAtOverride: dueOverride
      ) {
        lastSaved = parsed
        draft = ""
        manualDueAt = nil
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
        DeadlineChip(dueAt: due, size: .compact)
      }
    }
    .font(.system(size: 12))
  }

  /// Live preview row while the user is typing. Three visual slots:
  ///
  ///   1. cleaned title (primary text, semibold),
  ///   2. orange `DeadlineChip` (parsed or manual, tappable to edit,
  ///      with X to clear),
  ///   3. monochrome destination capsule ("Ready" / "Deadlines").
  ///
  /// The destination capsule is `.secondary`-tinted so it doesn't compete
  /// with the orange deadline vocabulary — orange means "this has time
  /// pressure", grey means "this is where the item will land".
  @ViewBuilder
  private func previewRow(for parsed: ParsedCapture) -> some View {
    let due = effectiveDueAt
    let lowConfidence = (manualDueAt == nil) && parsed.lowConfidence
    HStack(spacing: 8) {
      Text(parsed.title.isEmpty ? "(enter a title)" : parsed.title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(parsed.title.isEmpty ? .tertiary : .primary)
        .lineLimit(1)
      if let due {
        DeadlineChip(
          dueAt: due,
          size: .compact,
          lowConfidence: lowConfidence,
          onTap: openDatePicker,
          onClear: clearDeadline
        )
        .popover(isPresented: $datePickerOpen, arrowEdge: .top) {
          dueDatePicker
        }
      }
      DestinationCapsule(destination: destination(forDue: due))
      Spacer(minLength: 4)
    }
  }

  /// Destination string for the parsed/effective state. `Ready` is the
  /// catch-all "captured, no time pressure"; `Deadlines` is "lands on the
  /// Deadlines pane because there's a due date". A `Thread` destination
  /// would land here once we surface thread-attach in the overlay, which
  /// is out of scope for this batch.
  private func destination(forDue due: Date?) -> String {
    due == nil ? "Ready" : "Deadlines"
  }

  // MARK: - Date picker popover

  /// Open the chip's date-picker. Seeds `pickerDraftDate` with whichever
  /// deadline is currently in effect so the picker opens at the right
  /// time, not midnight today.
  private func openDatePicker() {
    pickerDraftDate = effectiveDueAt ?? defaultPickerSeed()
    datePickerOpen = true
  }

  /// Clear the manual deadline (if any) AND blank the parsed phrase from
  /// the draft so the parser doesn't immediately re-add the same deadline
  /// on the next keystroke. We trim the trailing parser-consumed tokens
  /// to keep the user's typed title intact.
  private func clearDeadline() {
    manualDueAt = nil
    if let parsed = currentParse, parsed.dueAt != nil {
      // The parser owns the title-stripping logic; the cleaned title
      // already excludes the temporal phrase. Replace the draft with
      // just that, so subsequent typing doesn't re-trigger recognition.
      draft = parsed.title
    }
  }

  /// Reasonable default seed when there's no current deadline at all.
  /// Rounds up to the next hour so the spinner doesn't open at a weird
  /// 02:37-ish point.
  private func defaultPickerSeed() -> Date {
    let now = Date()
    let cal = Calendar.current
    let next = cal.date(byAdding: .hour, value: 1, to: now) ?? now
    let comps = cal.dateComponents([.year, .month, .day, .hour], from: next)
    return cal.date(from: comps) ?? next
  }

  /// The popover body: a graphical date+time picker with a row of common
  /// presets above it ("In 1h", "Tomorrow 9am", "Friday 5pm") and a
  /// Set/Cancel pair below. Compact width — the overlay stays narrow.
  @ViewBuilder
  private var dueDatePicker: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Edit deadline")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)

      HStack(spacing: 6) {
        ForEach(DueDatePreset.presets, id: \.label) { preset in
          Button(preset.label) {
            pickerDraftDate = preset.date(from: Date())
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }

      DatePicker(
        "Deadline",
        selection: $pickerDraftDate,
        displayedComponents: [.date, .hourAndMinute]
      )
      .labelsHidden()
      .datePickerStyle(.graphical)
      .frame(maxWidth: 280)

      HStack {
        Spacer()
        Button("Cancel") { datePickerOpen = false }
          .keyboardShortcut(.cancelAction)
        Button("Set") {
          manualDueAt = pickerDraftDate
          datePickerOpen = false
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(16)
    .frame(width: 320)
  }

  // MARK: - Footer

  /// The overlay footer: a `.borderedProminent` Create button on the
  /// trailing edge (strong affordance for Return-to-create), plus an
  /// "esc to dismiss" key-cap hint that surfaces the escape gesture.
  /// Both live in a `.caption2 .secondary` row so they don't fight the
  /// title for vertical real estate.
  @ViewBuilder
  private var footer: some View {
    HStack(spacing: 8) {
      HStack(spacing: 4) {
        KeyCapGlyph(label: "esc")
        Text("to dismiss")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 6)
      Button("Create") {
        save()
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.regular)
      .keyboardShortcut(.defaultAction)
      .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
    }
  }
}

// MARK: - Subviews

/// Small monochrome capsule shown next to the deadline chip in the capture
/// overlay. Says where the item lands ("Ready" / "Deadlines"). Uses
/// `.secondary`-toned chrome so it doesn't fight the orange deadline chip
/// for attention — orange = time pressure, grey = destination.
private struct DestinationCapsule: View {
  let destination: String

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: iconName)
        .font(.system(size: 10, weight: .semibold))
      Text(destination)
        .font(.system(size: 11, weight: .medium))
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 2)
    .foregroundStyle(.secondary)
    .background(
      Capsule(style: .continuous)
        .fill(Color.secondary.opacity(0.15))
    )
    .accessibilityLabel("Destination \(destination)")
  }

  private var iconName: String {
    switch destination {
    case "Deadlines": return "bell"
    case "Thread": return "list.bullet.rectangle"
    default: return "tray"
    }
  }
}

/// Rounded-rect, monospaced glyph that reads as a keyboard key. Used in
/// the overlay footer to surface the "esc to dismiss" gesture without
/// claiming the visual weight of a button.
private struct KeyCapGlyph: View {
  let label: String

  var body: some View {
    Text(label)
      .font(.system(size: 10, weight: .medium, design: .monospaced))
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .foregroundStyle(.secondary)
      .background(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(Color.secondary.opacity(0.12))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
      )
      .accessibilityHidden(true)
  }
}

// MARK: - Date presets

/// Common deadline presets surfaced as a one-click row inside the chip's
/// date-picker popover. Each preset returns an absolute date computed from
/// the supplied `now` so the popover stays pure (no clock reads inside
/// the view).
private struct DueDatePreset: Sendable {
  let label: String
  let compute: @Sendable (Date) -> Date

  func date(from now: Date) -> Date { compute(now) }

  static let presets: [DueDatePreset] = [
    DueDatePreset(label: "In 1h") { now in
      now.addingTimeInterval(3600)
    },
    DueDatePreset(label: "Tomorrow 9am") { now in
      let cal = Calendar.current
      let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
      var comps = cal.dateComponents([.year, .month, .day], from: startOfTomorrow)
      comps.hour = 9
      comps.minute = 0
      return cal.date(from: comps) ?? startOfTomorrow
    },
    DueDatePreset(label: "Friday 5pm") { now in
      let cal = Calendar.current
      let today = cal.component(.weekday, from: now) // 1 = Sunday
      var delta = (6 - today + 7) % 7 // 6 = Friday
      if delta == 0 { delta = 7 }
      let day = cal.date(byAdding: .day, value: delta, to: cal.startOfDay(for: now)) ?? now
      var comps = cal.dateComponents([.year, .month, .day], from: day)
      comps.hour = 17
      comps.minute = 0
      return cal.date(from: comps) ?? day
    },
  ]
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
