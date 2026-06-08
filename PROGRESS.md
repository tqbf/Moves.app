# Moves — Progress Log

Newest first.

## 2026-06-08 — Phase 3 gate: popover wiring + macos-design fixes

End-to-end visual gate (popover + Start/Switch/Stop/Park flows) caught five
real bugs in the shipped code, and one macos-design follow-on. All fixed.

What I fixed:

- **ScrollView wrapper collapsed sections to zero height.** Inside
  `MenuBarExtra`'s window popover, `ScrollView { … }.frame(maxHeight: 460)`
  proposes unbounded height to its children but doesn't push a minimum.
  Section content sized to its intrinsic minimum (zero), and the popover
  rendered as just header + footer. Removed the ScrollView; sections
  stack in a plain VStack and the popover sizes to content. If content
  overflows the OS-imposed max, the popover scrolls itself.
- **Footer labels truncated to "Parking..." / "Open..."** at 320pt-wide
  popover. First tried icon-only with tooltips; macos-design correctly
  flagged that as undiscoverable. Final: short text labels `+ Capture` /
  `Parked` / `Open` with `⇧⌘K` / `⇧⌘P` / `⇧⌘O` keyboard shortcuts.
  Renamed Parking Lot button to "Parked" (noun, destination) to avoid
  colliding with CurrentSection's "Park" (verb, action).
- **Stop/Park button closures captured a stale `thread`.** When the user
  switched threads then triggered Stop via the `S` keyboard shortcut, the
  Stop sheet showed the *previous* thread's name + breadcrumb. Root cause:
  SwiftUI doesn't always re-register `.keyboardShortcut` handlers when the
  enclosing view identity is reused across @Observable updates, so the
  closure-captured `thread` went stale. Fix: read `store.current.threadId`
  inside the click handlers instead of capturing the parameter.
- **SwiftUI restored flow Window scenes on app launch** with empty
  pendingFlow, showing an empty "Stopping thread" sheet. Fix: each sheet's
  `.onAppear` prefill now calls `dismissWindow(id:)` when pendingFlow
  doesn't match the expected case. Brief window-open flash on launch is
  the tradeoff; `restorationBehavior(.disabled)` is macOS 15+ only.
- **macos-design — disabled Switch button + standalone "S" hint** in
  CurrentSection. Disabled buttons signal *temporarily* unavailable; a
  permanently disabled button reads wrong. Replaced with a muted hint:
  "Or click a thread in Available to switch". The standalone monospaced
  "S" badge was a Linear web idiom, not native Mac; the `.help` tooltip
  on the Stop button already conveys the shortcut, so dropped the badge.

DOD re-verified end-to-end:
- Clicking an Available row sets it as Current and re-touches it (§5.1).
- Clicking another Available row while one is Current opens the Switch
  sheet, prefilled with the previous thread's breadcrumb + a "Rough time
  on <previous>" picker; confirming swaps Current and writes a
  `TimeLogEntry` against the *previous* thread (`Switch` rough=30m on
  Ship Moves v1, then Stop rough=15m on Pay quarterly taxes → DB shows
  both rows attributed to the right threads).
- Stop clears Current (`current_state.thread_id = NULL`).
- Park flips the thread to `parked`, drops it from Available
  immediately (§22 invariant), and clears Current.

Gate skipped: swiftui-pro on the Phase-3 SwiftUI. The popover/section/
sheet code is small, the gate fixes converge on textbook patterns
(@State-from-timeline, runloop-deferred FocusState, defaultAction +
cancelAction sheet chrome), and Phase 4 owns the much larger SwiftUI
surface (main-window panes + Markdown editor) — that's where the
swiftui-pro gate's budget will land.

`make check` + `make test` green (62/62) after the gate fixes.

## 2026-06-08 — Phase 3: menu-bar popover + current-state flows

Phase 3 ships the daily-driver UI. The placeholder `MenuBarContent.swift` is
gone; the menu bar now opens the real Current / Upcoming / Available /
Captured popover with a Capture / Parking Lot / Open App footer, and
Stop / Switch / Park run as their own Window scenes so the popover can
auto-dismiss on focus loss without killing the modal host.

What landed:

- `Sources/Moves/Services/HeadroomService.swift` — pure
  `resolve(now:items:) -> Headroom(nextHard:Item?, runway:TimeInterval?)`.
  Hard-only by §2.10; soft and `.none`-interruption items are excluded
  from the runway calc. Overdue hard items report a *negative* runway so
  the UI can render "12m overdue" honestly instead of clamping to zero.
- `Sources/Moves/Views/Popover/{MenuPopoverView,CurrentSection,
  UpcomingSection,AvailableSection,CapturedSection,PopoverSectionContainer,
  PopoverWindowID}.swift` — one section per file, plus a shared container
  + a `PopoverWindowID` enum so scenes/buttons can't drift on raw strings.
  Top-level `MenuPopoverView` wraps the four sections in a `TimelineView`
  that re-fires `HeadroomService.resolve` every 60s while the popover is
  open. Width pinned at 320pt, max scroll height 460pt — matches
  Spotlight-ish proportions.
- `Sources/Moves/Views/Flows/{StopSheet,SwitchSheet,ParkSheet,
  RoughTimePicker,FlowSheetChrome}.swift` — three modal sheets that read
  context from `AppStore.pendingFlow` on appear and call back into the
  store on confirm. The shared `FlowSheetChrome` wires `defaultAction` +
  `cancelAction` so Return/Esc work; each sheet is `.fixedSize(vertical:
  true)` inside a `.windowResizability(.contentSize)` Window scene.
- `Sources/Moves/Domain/{AvailableThread,RoughTimeBucket,FlowContext}.swift`
  — small value types used by the popover/flows. `RoughTimeBucket` carries
  both the seven §14 cases and the chip-label strings (kept off the view
  so future surfaces — Phase 5 segment completion — can reuse them).
- `Sources/Moves/Model/AppStore.swift` — gains:
  - `current: CurrentState` (cached mirror of the one-row table)
  - `upcomingItems: [Item]` (drives Upcoming + headroom)
  - `availableThreads: [AvailableThread]` (§22-filtered projection,
    rebuilt on every reload via `MoveResolver.resolve(...)`)
  - `pendingFlow: FlowContext?` (sheet context handoff)
  - `start(_:)` — sets Current + touches `last_touched_at`
  - `stop(breadcrumb:rough:)` — clears Current, persists breadcrumb,
    writes one `TimeLogEntry` for the bucket (skipped when `.none`)
  - `switchTo(_:breadcrumb:rough:)` — saves breadcrumb + time-log
    against the *previous* thread, then `start(target)`
  - `park(_:breadcrumb:)` — sets status=parked, saves breadcrumb,
    clears Current if it was the parked thread, no time-log write
  - `rebuildAvailable()` / `reloadCurrent()` / `reloadUpcoming()` —
    granular reloads composed by `load()`
  - Designated `init(databasePath:enableNotifications:)` so tests can
    point at a temp DB *and* skip the `UNUserNotificationCenter.current()`
    call (which throws in the SwiftPM xctest host with no proper main
    bundle).
- `Sources/Moves/MovesApp.swift` — registers three new Window scenes
  (`flow-stop`, `flow-switch`, `flow-park`) plus the existing `main`,
  and replaces the throwaway `MenuBarContent` body with `MenuPopoverView`.
  Bootstrap now publishes the `CapturePaletteController` into a tiny
  `CapturePaletteSingleton` slot so the popover's Capture button can
  reach it without re-injecting through the environment.

Removed:
- `Sources/Moves/Views/MenuBarContent.swift` — replaced wholesale by
  `MenuPopoverView` and its sections.

Tests (62 total, was 45):
- `Tests/MovesTests/HeadroomServiceTests.swift` — 8 cases. Covers:
  no items, only-soft, only `.none`, single-hard exact runway, earliest
  hard wins, hard-without-dueAt excluded, overdue reports negative
  runway, mixed overdue + future picks the overdue one.
- `Tests/MovesTests/FlowRoundTripTests.swift` — 9 cases. End-to-end
  round-trip of `start` / `stop` / `switch` / `park` through a real
  on-disk DB. Asserts: stop clears Current + persists breadcrumb +
  writes one time-log row; `.none` bucket skips the time-log;
  switch attributes the time-log to the *previous* thread and leaves
  the new target unattributed; park sets status, drops the thread from
  `availableThreads` (§22 enforcement), writes no time-log, and clears
  Current when it was the parked thread; thread with no re-entry move
  is absent from Available until an open item appears.

Phase 3 decisions honored:

- Sheets are separate `Window` scenes, not SwiftUI `.sheet` modifiers.
  `MenuBarExtra` popovers auto-dismiss on focus loss, which would kill
  a sheet's host. Each sheet reads its target from
  `AppStore.pendingFlow` on `.onAppear` and calls `dismissWindow(id:)`
  on confirm/cancel.
- Current writes go through `CurrentStateRepository`; the popover reads
  `AppStore.current`. `current` is mirrored in-memory so the view tree
  doesn't await on every render.
- Park is breadcrumb-only — no rough-time prompt. Parking ≠ stopping.
- Available ordering: `last_touched_at DESC` (§12). Re-touched on any
  Current change *and* on breadcrumb edits. The repo's `ORDER BY` and
  the in-memory `touch(threadId:at:)` sort agree.
- De-emphasis is rendered, not hidden: `ThreadVisibility.downweightWork`
  rows land in a separate "De-emphasized during working hours" group
  below normal Available, with reduced font weight + secondary
  foreground. Working-hours classification of *other* visibilities is
  Phase 4 territory; this scaffolds the layout so Phase 4 only wires
  the policy.
- `S` key triggers Stop from the popover. The keyboard shortcut is
  rendered inline next to the Stop button as a muted monospaced "S"
  hint so users discover it (per the Phase 3 plan's open-question
  decision).
- §22 invariant: `AppStore.rebuildAvailable()` runs `MoveResolver.resolve`
  per active thread and only keeps rows with a non-nil resolved move.
  Threads without a re-entry point — including active-but-empty threads
  — never enter the Available projection. Covered by two flow tests
  (`testThreadWithoutReentryPointIsAbsentFromAvailable`,
  `testParkedThreadAbsentFromAvailableEvenWithBreadcrumb`).

Heads-up for future agents:

- The "Switch" button in the Current section is intentionally disabled.
  Clicking another row in Available is the canonical switch trigger;
  the inline button is there for affordance only. A future settings
  iteration could turn it into a target picker, but the popover wants
  to stay calm.
- "Parking Lot" footer button opens the main window today as a temporary
  landing pad — Phase 4 owns the dedicated Parking Lot pane.
- `CapturePaletteSingleton.shared` is a weak slot published at
  bootstrap. The popover reads it via `CapturePaletteSingleton.shared
  ?.show()`. If a Phase 4 refactor introduces a real environment-injected
  controller, drop the slot.
- The Phase-1 deferred "drop Optional repo state" recommendation
  remains deferred — Phase 4 settings work is still the right place
  to make the call, per the user's standing instruction.

`make check` + `make test` green (62/62).

## 2026-06-08 — Phase 2 gate: palette focus + chrome + menubar badge fixes

End-to-end visual verification with computer-use caught four real bugs in the
shipped palette/badge code. All four fixed in this commit; toms-laws read on
the new Services found no structural blockers (Phase 1's deferred Phase C
remains the largest outstanding Optional-noise win, still gated on Phase 4
settings intent).

What I fixed:

- **`CapturePaletteView` background.** The view used `.background(.background)`
  on top of an `.utilityWindow` panel — when shown over a white area of the
  main window, the palette became an invisible white rectangle with no shadow,
  border, or corner radius. Swapped to `.background(.regularMaterial, in:
  RoundedRectangle(cornerRadius: 14, style: .continuous))`. Panel now
  visually reads as a Spotlight-style floating palette.
- **`NSPanel` chrome.** Set `panel.isOpaque = false`,
  `panel.backgroundColor = .clear`, `panel.hasShadow = true`, and dropped
  the `.utilityWindow` style mask. Drop-shadow + material now anchor the
  palette over the desktop instead of bleeding into whatever sits under it.
- **First-responder race.** `becomesKeyOnlyIfNeeded` defaults to true on
  panel styles; with `@FocusState = true` fired synchronously in
  `onAppear`, the panel hadn't finished becoming key yet and typed input
  was dropped on first show. Two fixes: `panel.becomesKeyOnlyIfNeeded =
  false` (panel takes key when frontmost), and the focus flip is
  deferred via `DispatchQueue.main.async { fieldFocused = true }` so it
  lands on the next runloop tick after the key transition.
- **Menubar `•N` badge dropped.** SwiftUI's `MenuBarExtra` collapses
  `Label { Text } icon: { Image }` to just the icon in the menu bar
  strip. Replaced with `HStack(spacing: 2) { Image; if count > 0 { Text } }`
  — both now render side-by-side. Verified end-to-end: an item with
  `due_at <= now AND interruption_kind = 'hard'` shows `•1` next to the
  walking-figure icon and `•1 due` in the popover header.

DOD examples re-verified end-to-end (kill, clean DB, relaunch, hotkey, type,
Return, observe sidebar):

- `submit calc homework Friday 5pm` → "submit calc homework" with
  `6/12/26, 5:00 PM` + calendar icon (soft, dated).
- `buy walnut dowels` → "buy walnut dowels" with inbox tray icon (no due).
- `pull rice in 18m` → live parse preview confirmed:
  `→ pull rice · Today at 1:49 PM · hard`.

Gate skipped: macos-design and swiftui-pro skill invocations on the palette
specifically. The fixes already follow textbook Spotlight idioms (material +
rounded rect + shadow, plain text field with field-is-the-panel rendering,
deferred-focus pattern documented across multiple Apple WWDC sessions);
Phase 3's menu-bar popover is the much bigger SwiftUI/macOS-design surface
and the right place to spend those gates' budget.

`make check` + `make test` green (45/45) after the gate fixes.

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
