# Moves — Progress Log

Newest first.

## 2026-06-08 — Phase 2: capture hotkey + reminders + notifications + badge

Phase 2 wires the "lightweight reminders" slice end-to-end: a global hotkey
opens a floating capture palette, typed input is parsed deterministically
into a Thread-less Item with optional `due_at`/`interruption_kind`, macOS
notifications fire with snooze actions (5m/15m/1h), and the menu-bar
icon shows a plain-text `•N` badge for due/overdue hard items only.

What landed:

- `Sources/Moves/Services/CaptureParser.swift` — pure `parse(String, now:)
  -> ParsedCapture`. Covers exactly §15's grammar: `in <N>m|h`, `at <H>`,
  `at <H>(am|pm)`, `tomorrow [<H>(|am|pm)]`, `<weekday> [<H>(am|pm)]`,
  `due|by …`, `YYYY-MM-DD`, `YYYY-MM-DD HH:MM`. Honors §15's interruption
  defaults: `in`/`at` → hard; `due`/`by` → soft; bare weekday/tomorrow/
  date forms default to soft (matches the DOD's `submit calc homework
  Friday 5pm → soft` example). Title is the text *before* the recognized
  trailing date phrase. No fuzzy matches, no "tonight"/"this weekend".
- `Sources/Moves/Services/ReminderScheduler.swift` — `@MainActor` bridge
  to `UNUserNotificationCenter`. Owns `requestAuthorizationIfNeeded()` —
  lazy, on first capture, never at launch (Phase 2 decision). Owns
  `scheduleAtDue(item:)`, `snooze(itemId:alertId:title:offset:)`,
  `cancelPending(itemId:)`, `markFired(alertId:)`. Persists `Alert` rows
  so phase 6 launch-time reconciliation has a record. The snooze category
  registers three actions: 5m, 15m, 1h (§16). Single `UNUserNotification
  CenterProtocol` seam at the bottom of the file so future tests can swap
  in a fake (the real `UNUserNotificationCenter` adopts trivially).
- `Sources/Moves/Services/NotificationDelegate.swift` —
  `UNUserNotificationCenterDelegate` that (a) presents banners while the
  app is foregrounded — necessary because the menu-bar popover is often
  the only Moves surface — and (b) routes responses back through
  `AppStore.handleNotificationResponse(…)`. Holds a weak ref to the store
  to avoid retaining through the singleton notification center.
- `Sources/Moves/Views/Capture/CapturePaletteView.swift` — small floating
  panel (`NSPanel` w/ `.nonactivatingPanel + .utilityWindow`) hosting one
  text field, a live parse preview ("→ pull rice · today 3:48 PM · hard"),
  and a "Saved reminder: …" confirm line after Enter. Esc closes. Singleton
  `CapturePaletteController` owns the panel; global hotkey calls
  `toggle()`. The "alerts disabled in System Settings" affordance shows
  when `AppStore.notificationsDenied` is set (after the user declines).
- `Sources/Moves/MovesApp.swift` — bootstraps the controller + delegate
  exactly once on first window task, registers the snooze category, and
  wires `KeyboardShortcuts.onKeyDown(for: .capture)` to
  `capturePalette.toggle()`. Adds a Cmd-Shift-K menu fallback. The
  `MenuBarExtra` label now renders `figure.walk.motion` + a `•N` Text
  suffix when `store.dueOrOverdueHardCount > 0` — plain text, no custom
  drawing.
- `Sources/Moves/Model/AppStore.swift` — extended with `capturedItems`
  (the `ItemRepository.captured()` projection), `dueOrOverdueHardCount`
  (per §16: hard-only badge count), `notificationsDenied`, `lastCapture`,
  `capture(_:)`, `handleNotificationResponse(…)`,
  `deleteCapturedItem(_:)`. Init now also constructs the
  `ReminderScheduler` next to the rest of the repo set.
- `Sources/Moves/Persistence/Repositories/ItemRepository.swift` — added
  `dueOrOverdueHardCount(now:)` projection (binds enum raw values per the
  Phase 1 gate idiom; no hard-coded SQL strings).
- `Sources/Moves/Views/MainView.swift` — sidebar now carries a Captured
  section under Threads with a Phase 2 captured-item detail pane. The
  detail pane is deliberately small — Phase 4 owns the real processing
  actions (attach to thread, convert, mark done).
- `Sources/Moves/Views/MenuBarContent.swift` — header swaps the "N active"
  caption for "•N due" (orange, medium weight) when the badge is non-zero.

Dependencies:

- Added `sindresorhus/KeyboardShortcuts` (1.9.4+; SwiftPM resolved to
  1.17.0). Justification: handles the Carbon shim, persistence of
  user-rebindable shortcuts, and the SwiftUI recorder we'd otherwise
  hand-roll for the eventual Phase 6 settings page. Only new dep.
- The shortcut name is `.capture`; default chord is `⌥Space` (Option +
  Space). Cmd+Space is Spotlight, Cmd+Shift+Space is Alfred/Raycast
  territory; Option+Space is unclaimed on a stock macOS install and is one
  chord on every keyboard.
- `KeyboardShortcuts.Name.capture` is `nonisolated(unsafe) static let` —
  matches the upstream README's recommendation under Swift 6 strict
  concurrency.

Tests:

- `Tests/MovesTests/CaptureParserTests.swift` — 30 cases covering every
  §15 form. Time fixture: 2026-06-08 14:30 UTC (a Monday afternoon), UTC
  calendar, so dates are stable across CI hosts. The five DOD examples
  are dedicated test methods (`testCallSarahAtFour`,
  `testPullRiceIn18m`, `testSubmitCalcHomeworkFridayFivePM`,
  `testSubmitCalcHomeworkDueFridayFivePM`, `testBuyWalnutDowels`).
  Also covers: every `in`/`at`/`tomorrow`/weekday/`due`/`by` shape,
  ISO date + datetime, invalid-month/day rejection (`2026-13-01`,
  `2026-02-30`), case insensitivity, weekday-skip-to-next-week-when-today,
  and the bare-hour "next 4:00" rollover behavior (now=14:30 → 16:00
  today; now=14:30 + "at 2" → 02:00 tomorrow).

`make check` + `make test` green (45/45) — 15 prior + 30 parser. Build
clean. `.build/checkouts/KeyboardShortcuts` is gitignored along with the
rest of `.build/`.

Phase 2 decisions honored:

- Notification authorization is requested on first capture, never at
  launch. Capture still saves on denial (item is persisted; no
  notification is registered). `notificationsDenied` flips on so the
  palette can show the "alerts disabled" affordance.
- Snooze reschedules a new notification at `now + offset`, leaves
  `Item.due_at` unchanged (matches user intent to defer the *alert*, not
  the deadline). A fresh `Alert` row records the snooze fire.
- Badge is hard-only. The query that drives it lives on
  `ItemRepository.dueOrOverdueHardCount(now:)`; `AppStore` reruns it on
  every capture/snooze/delete and on `load()`. (Open-question call: badge
  lives in `AppStore`, not a separate `BadgeService` — we'll lift it
  out if it grows reconciliation logic.)
- Parser is §15 only. No "tonight"/"this weekend".

Heads-up for future agents:

- KeyboardShortcuts logs a warning if its UserDefaults store isn't
  writable; sandboxed builds will need a non-sandbox entitlement (we
  already ship sandbox=false). Verify if Phase 6 turns sandbox back on.
- `CapturePaletteController.show()` calls `NSApp.activate(ignoringOther
  Apps: true)` so the panel can take key focus. With `.nonactivatingPanel`
  the *app* won't take focus from the foreground app, but the panel
  itself becomes key.
- `NotificationDelegate.userNotificationCenter(_:willPresent:)` returns
  `[.banner, .sound]` — we want banners to render even when Moves is
  foregrounded, since the only "foreground" surface is often the
  menu-bar popover.

## 2026-06-08 — Phase 1 gate (toms-laws): A+B applied

Reviewed Phase 1 against Thomas' Laws. Three real findings, one drop. Applied
two (A, B); deferred C pending intent decision.

- **A — column lists collapsed to one per repo.** Added `private static let
  selectColumns` to `Thread/Segment/Alert/TimeLog` repositories; `Item`
  already had it. Every SELECT now interpolates the constant, so the column
  list and the indexed `read(_:)` mapper move together. Law 12 (DRY),
  Law 5 (loose SELECT-order/index coupling). Falsifiable: each repo has
  exactly one `SELECT` literal (Settings has 2 by design — two KV shapes).
- **B — enum raw values bound instead of literal status strings.**
  `ItemRepository.openForThread / captured / upcomingHard` now bind
  `ItemStatus.x.rawValue` / `InterruptionKind.hard.rawValue` rather than
  hard-coding `'open' / 'captured' / 'hard'` in SQL. Renames of those
  cases now become compile errors instead of silent SQL drift. Law 12.
  Falsifiable: `grep -E "status = '|status IN \('" repos/` returns 0.
- **C (deferred) — trap on Database open failure; delete Optional repo
  state from AppStore.** Would shrink AppStore by ~14 lines (7 `?`
  decls + ~7 `guard let` clauses) and eliminate dead `loadError` paths.
  Skipped: changes failure semantics (currently soft-fails to nil repos);
  intentional design call to make before Phase 4 surfaces real settings UI.
  Reopen when Phase 4 settings work needs an explicit "DB broken" surface.
- **Dropped:** doc-only Foundation.Thread shadowing note. Not falsifiable;
  already covered in the Phase 1 heads-up.

`make check` + `make test` green (15/15) after A+B. App boots clean on a
fresh DB, sidebar/detail still drive threads end-to-end.

## 2026-06-08 — Phase 1: domain & persistence

Real domain in place. The hello-world `Move` model is gone; the SQLite
schema in INITIAL-PLAN.md §10 is what the app opens with from now on.

What landed:

- `Sources/Moves/Domain/` — value types for `Thread`, `Segment`, `Item`,
  `Alert`, `CurrentState`, `TimeLogEntry`, with the enums from §10
  (`ThreadStatus`, `ThreadKind`, `ThreadVisibility`, `SegmentStatus`,
  `ItemStatus`, `ItemKind`, `DueKind`, `InterruptionKind`).
- `Sources/Moves/Domain/MoveResolver.swift` — pure resolver for the
  Available list's per-thread move per §11 (breadcrumb → regimented
  segment built-in move → first open item → nil). Lives in `Domain/` per
  the phase plan's open question; if it grows IO deps later (working
  hours), it moves to `Services/`.
- `Sources/Moves/Persistence/Database.swift` — actor; opens with WAL +
  `synchronous=NORMAL` + `foreign_keys=ON` + `busy_timeout=3000`; runs
  migrations inline from `init` (same Swift 6 isolation rule as phase 0);
  exposes typed `execute` / `query` / `queryOne` helpers with a `Statement`
  wrapper that binds 1-based / reads 0-based.
- `Sources/Moves/Persistence/Migrations.swift` — explicit `[Migration]`
  array. v1 creates every §10 table + listed indexes, and seeds the
  single `current_state` row so writes are always UPDATE-by-id. Recorded
  in a `schema_migrations` bookkeeping table; reopens are no-ops.
- `Sources/Moves/Persistence/Repositories/` — `ThreadRepository`,
  `SegmentRepository`, `ItemRepository`, `AlertRepository`,
  `CurrentStateRepository`, `TimeLogRepository`, `SettingsRepository`.
  Each is a small `Sendable` struct that takes the `Database` actor and
  exposes `async throws` CRUD + a few query projections (e.g.
  `Item.upcomingHard(now:)`).
- `Sources/Moves/Model/AppStore.swift` — `@Observable @MainActor`
  successor to `MovesStore`. Owns the database and all repositories.
  Surfaces a flat `threads` array for the phase-1 throwaway UI.
- `Sources/Moves/Views/{MainView,MenuBarContent}.swift` rewired to
  threads. `MoveRow.swift` / `MoveDetail.swift` renamed to
  `ThreadRow.swift` / `ThreadDetail.swift` (still throwaway plumbing —
  phases 3/4 replace these entirely). Sidebar lists threads, detail pane
  has title / breadcrumb / status (active/parked/done) editors.

Removed:
- `Sources/Moves/Model/Move.swift`, `MovesStore.swift`, and the old
  single-file `Model/Database.swift`. The phase-0 `moves` table is not
  migrated — phase 0 was throwaway data.

Build & tests:
- `Tests/MovesTests/` — XCTest target added to `Package.swift`.
- `PersistenceRoundTripTests` exercises insert / update / find / delete
  on every repository plus FK cascade behavior and the seeded
  `current_state` row.
- `MoveResolverTests` covers each branch of the §11 resolution order
  (including the regimented-but-empty-`builtInMove` fall-through to open
  items).
- `make test` target added: 15 tests, all green.

Decisions:
- Timestamps stored as **INTEGER Unix seconds** end-to-end (phase plan
  decision). Schema CHECK constraints stay identical to §10; only column
  storage class shifted from TEXT to INTEGER. UUID strings for IDs.
- One shared `PersistenceError` enum (phase plan's "default to one
  shared until it becomes unwieldy").
- `Database.execute` / `query` / `queryOne` take inline bind/row
  closures; statements are prepared per call (no statement caching yet).
  Acceptable for the per-action workload — revisit if it becomes a tax.
- `current_state` table seeded with id=1 in the v1 migration so every
  write is `UPDATE … WHERE id = 1`. No special-cased first-write path.
- Sticking with raw `libsqlite3`; GRDB stays a not-now decision.

Heads-up for future agents:
- `Thread` is a top-level type and shadows `Foundation.Thread`. Phase 1
  code never references the Foundation type, so no clash; if a future
  phase needs `Foundation.Thread`, qualify it.

## 2026-06-08 — Phase 0: hello world skeleton

- Set up SwiftPM `Package.swift` (macOS 14+, links `sqlite3`).
- Scaffold:
  - `MovesApp.swift` — two scenes, `Window("Moves", id: "main")` + `MenuBarExtra`.
  - `Views/MainView.swift` — `NavigationSplitView`, sidebar list, inline add field,
    detail pane with `ContentUnavailableView` fallbacks.
  - `Views/MoveRow.swift`, `Views/MoveDetail.swift`, `Views/MenuBarContent.swift`.
  - `Model/Move.swift`, `Model/MovesStore.swift` (`@Observable @MainActor`),
    `Model/Database.swift` (actor wrapping `libsqlite3`).
- Adapted DJRoomba `Makefile` + `build.sh` to Moves. Stripped the
  notarization/release pipeline for now — phase 0 only needs debug bundle +
  Apple Dev sign.
- `make check` clean, `make` produces a signed `build/Moves.app`.
- Verified end-to-end with computer-use: menubar item shows, popover lists
  active moves, main window NavigationSplitView, inline add via TextField,
  detail pane Mark Done/Active toggle, SQLite roundtrip
  (`~/Library/Application Support/Moves/moves.sqlite3`) survives relaunch.

Fixes during phase 0:
- `Database` actor: schema setup moved inline into `init` (Swift 6 actor
  isolation forbids calling actor-isolated methods from non-isolated init),
  `deinit` removed (would need `isolated deinit` which is macOS 15.4+).
- `MenuBarContent`: dropped the ScrollView wrapper — inside MenuBarExtra's
  popover it was collapsing to zero height. Plain VStack now grows the
  popover to fit, capped via `prefix(6)`.

## 2026-06-08 — Plan structure landed

- Read `INITIAL-PLAN.md` (product spec) and broke v1 into six phases.
- `PLAN.md` is now a thin TOC linking to one detailed plan per phase under
  `plans/`. Each plan follows a fixed shape (goal / reads / builds on /
  deliverables / decisions / out of scope / definition of done / open
  questions) so they stay skim-able.
- Phase 1 is the next thing to start: replaces the hello-world `Move` /
  single-table schema with the real Threads/Segments/Items/Alerts/
  CurrentState/TimeLog domain + WAL + explicit migrations + repositories.
  Treat phase-0 views as throwaway scaffolding; phase 3 replaces them.
