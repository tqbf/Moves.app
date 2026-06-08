# Phase 2 — Capture & reminders

**Goal:** Self-contained "lightweight reminders" slice. A global hotkey
opens a tiny capture palette; typed input is parsed deterministically into
a Thread-less Item with an optional `due_at`/`interruption_kind`; reminders
fire as macOS notifications with snooze; the menu-bar icon badges
due/overdue hard items.

**Reads:** INITIAL-PLAN.md §4.4 (capture hotkey), §5.6–§5.7 (capture
flows), §8 (reminder/alert semantics), §13 (captured list), §15 (date
grammar), §16 (notifications & badge).

**Builds on:** Phase 1 — uses `ItemRepository`, `AlertRepository`,
`AppStore`.

## Deliverables

- `Sources/Moves/Services/CaptureParser.swift` — deterministic parser for
  §15's grammar. Pure function `parse(String, now: Date) -> ParsedCapture`.
  Unit-testable.
- `Sources/Moves/Services/ReminderScheduler.swift` — bridges Items + Alerts
  to `UNUserNotificationCenter`. Owns scheduling, snoozing, cancellation;
  persists `Alert.fired_at` after delivery.
- `Sources/Moves/Services/NotificationDelegate.swift` —
  `UNUserNotificationCenterDelegate` wiring snooze categories (5m/15m/1h
  per §16) and dispatching back into `AppStore`.
- `Sources/Moves/Views/Capture/CapturePaletteView.swift` — small floating
  panel (`NSPanel` via `NSWindow` wrapper) with one text field, a confirm
  line ("Saved reminder: …"). Esc closes; Enter saves.
- Global hotkey: bring in **KeyboardShortcuts** (sindresorhus). Add to
  `Package.swift`. One shortcut name: `.capture`.
- Menu-bar badge: `MenuBarExtra` label updates to show `•N` when
  `AppStore.dueOrOverdueHardCount > 0`. Plain text suffix, no custom
  drawing.
- Minimal Captured list inside the existing main window for now (replaces
  the placeholder sidebar from phase 1). Phase 4 redesigns it.

## Decisions

- **Third-party dep:** KeyboardShortcuts is the only addition. Justify in
  the PR — it handles the Carbon shim, persistence of user-chosen
  shortcuts, and the Settings UI piece we'd otherwise have to build.
- **Notification authorization:** request on first capture, not on launch.
  If denied, capture still saves the item; we show a small "alerts
  disabled" affordance.
- **Parser scope:** exactly the forms in §15. No fuzzy matches, no
  "tonight"/"this weekend" — those are v2 candidates.
- **Snooze:** rescheduling fires a new notification at `now + offset`,
  leaving `due_at` unchanged. Reflects user intent (defer the alert, not
  the deadline).

## Out of scope

- Attaching captures to threads (phase 4 — processing actions).
- Recurring reminders (v2 explicitly per §18).
- Notification "complete" action (§8.4 marks it optional for v1).
- Settings UI for alert offsets (phase 6).

## Definition of done

- `pull rice in 18m` → Item with `due_at` ≈ now+18m, `interruption_kind =
  hard`. macOS notification fires; pressing "Snooze 5m" reschedules.
- `submit calc homework Friday 5pm` → soft, due_at next Friday 17:00.
- `buy walnut dowels` → no due_at, `interruption_kind = none`.
- Badge shows count of due/overdue hard items only; quiet for soft/none.
- All §15 examples covered by tests.

## Open questions

- Capture palette window: `NSPanel` with `.nonactivating` style vs a
  separate `Window` scene? Start with `NSPanel` (proper floating
  behavior, doesn't take Dock focus).
- Where do badge transitions live — `AppStore` observer, or a small
  `BadgeService`? Lean toward keeping it in `AppStore` until we need to
  reconcile with notification delivery.
