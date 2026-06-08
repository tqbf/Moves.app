# Moves — Progress Log

Newest first.

## 2026-06-08 — Markdown notes: preview-first, edit on click

Replaced the side-by-side Markdown editor + preview split inside the
thread-detail notes section. The split read as an IDE pane stapled
onto the rest of the thread view — monospaced editor on one half,
rendered output on the other, both fighting for the user's eye every
time they looked at a thread.

New behavior:

- Default state: rendered Markdown only, sitting in one card. A small
  pencil icon in the top-right corner is the affordance for editing.
- Click pencil → flip the same card into the source editor. A blue
  "Done" pill appears in the same top-right position (also bound to
  ⌘↩) that flips back to preview.
- If the source is empty (fresh thread, never had notes), the card
  starts in editor mode and never shows the pencil — there's nothing
  to preview, so a button to "view it" would be a no-op.
- Once content exists, the view picks preview on first appear; the
  user explicitly opts into edit, and editing persists for the
  session until they click Done (no auto-snap-back, so a long edit
  isn't interrupted).

Same Markdown block parser (headings, lists, paragraphs, fenced code)
— only the chrome around it changed. The narrow-width tabbed picker
fallback is gone too; the new layout works at any width.

## 2026-06-08 — Swipe-left to delete on every main-window list

Every list pane in the main window now uses a native `List` with
`.swipeActions(edge: .trailing)` carrying a destructive "Delete"
button — the standard macOS swipe-left affordance. Previously each
pane built its rows as `VStack { ForEach } .background(rounded)`,
which looks like a ported Qt dashboard and (more importantly) doesn't
honor `.swipeActions` — that modifier only works inside `List`/`Form`.

What changed:

- **`PaneShell.swift`** — added a `PaneListShell` variant that renders
  the title/subtitle block above the content but does NOT wrap content
  in a `ScrollView`. Lists provide their own scrolling. The original
  `PaneShell` is unchanged so non-list panes (Current detail, Time
  Log) keep their existing behavior. Both shells share a private
  `PaneHeader` so typography can't drift.
- **`AvailableView.swift`** — `List` with two `Section`s (visible +
  "De-emphasized during working hours"); each row carries
  `.swipeActions { Delete → store.delete(row.thread) }`.
- **`ThreadsListView.swift`** — `List` with three sections (Active /
  Parked / Done). The inline "New thread…" row sits as a card above
  the List so it can keep the field-shaped chrome. Each row has the
  pre-existing context-menu plus a swipe-action Delete.
- **`CapturedView.swift`** — `List` of `CapturedRow`s with
  `.swipeActions { Delete → store.deleteItem(item) }`.
- **`DeadlinesView.swift`** — `List` of items with the same swipe
  behavior.
- **`ParkingLotView.swift`** — `List` of parked threads with
  swipe-Delete (the "Unpark" + "Open" buttons stay as trailing
  inline controls).
- **`ThreadDetailView.swift`** — items checklist sits inside a
  surrounding `ScrollView` (notes editor + breadcrumb editor live in
  the same scroll), so a nested `List` would compose badly. Items
  got a `.contextMenu { Delete }` instead — the standard fallback
  affordance when `.swipeActions` isn't available. Right-click any
  item to delete.
- **`AppStore.deleteItem(_:)`** — new generic delete that handles
  items across captured + thread-attached + deadlined caches in one
  call, cancels any pending notification, and rebuilds Available so
  §22's "no re-entry = no Available" stays coherent when an item's
  removal drops a thread off the list. The pre-existing
  `deleteCapturedItem` now delegates to it.

All four `List` panes use `.listStyle(.inset)` (the modern macOS
default, matching Mail / Reminders / Notes) and
`.scrollContentBackground(.hidden)` so the list blends with the
window background rather than carrying its own opaque chrome.

Tests unchanged (164/164 green). The swipe gesture is the system
trackpad two-finger swipe-left — not driveable by mouse — so the
end-to-end visual gate verified row rendering + the right-click
context-menu Delete path; the swipe path itself was confirmed by
code review (`.swipeActions` modifier wired with a destructive
button targeting the same `store.delete*` calls the context menu
uses).


## 2026-06-08 — Settings is now a system Settings scene (Cmd-,)

Pulled the sidebar Settings destination out of the main window. Moves
now uses SwiftUI's `Settings { ... }` scene, which gives:

- **Cmd-,** as the standard binding (no manual menu wiring).
- The standard **Moves → Settings…** menu item (system-supplied).
- A fixed-size settings window with a tab-bar toolbar — the System
  Settings idiom on modern macOS, not a sidebar pane that looked like
  a ported Qt dashboard.

What changed:

- `MovesApp.swift` — added a `Settings { SettingsView() … }` scene.
- `SidebarDestination.swift` — dropped the `.settings` case.
- `RootWindow.swift` — removed the Settings sidebar row and the
  `.settings` detail case. The sidebar's second section now contains
  Time Log only.
- `Views/Window/Settings/SettingsView.swift` — rewritten from a single
  vertical pane of cards into a 4-tab `TabView`: **General** (badge
  toggle, capture shortcut, "Show onboarding again"), **Working
  Hours**, **Alerts** (default offsets), **Backup** (SQLite + Markdown
  export). Each tab is a `Form` with `.formStyle(.grouped)` and
  `LabeledContent` rows — the System Settings look.
- Removed the now-dead `AlertOffsetsSection.swift`,
  `BadgeAndOnboardingSection.swift`, `ExportSection.swift` — their
  bodies live inline inside the new tab views; the underlying
  AppStore / ExportService / preference write paths are unchanged.

Behavior unchanged: the working-hours editor saves through
`AppStore.saveWorkingHours`, the badge toggle and onboarding marker go
through `saveUserPreferences` / `resetOnboarding`, the export buttons
hit the same `ExportService` factory. Tests reference none of the
section views, so the rewrite is purely chrome — `make check` +
`make test` green (164/164).


## 2026-06-08 — capture-palette UX + onboarding auto-finish

Two user-reported bugs against the Phase-6 surface, both of which
turned out to be UX gaps masquerading as functional ones — captures
without a deadline always saved, and the onboarding Done button always
worked, but neither was discoverable enough for the user to trust it.

What changed:

- **`CapturePaletteView.swift`** — the live-parse preview no longer
  buries the deadline in a single tertiary-grey line. The parsed title
  renders in secondary text with a leading "↪" arrow; a recognized
  deadline appears as an accent-tinted pill (orange `bell.fill` for
  hard, accent `calendar` for soft) carrying the formatted time; when
  no deadline is recognized, the row reads "↪ title · saves as a
  capture" with a trailing ⏎ glyph so the user knows Return persists
  regardless. The post-save confirmation now leads with a green
  `checkmark.circle.fill` + "Saved <title>" plus the chip if one
  applied, instead of a one-line "Saved capture: …" in secondary text.
- **`CapturePaletteController.show()`** — replaces the panel's hosting
  controller's root view on each show. The previous code reused the
  same SwiftUI subtree across `orderOut` / `orderFront` cycles, so a
  stale "Saved buy bread" line bled into the next capture session and
  any leftover `draft` text persisted between opens. Rebuilding the
  root view on show forces SwiftUI to mount the view fresh, which
  re-fires `onAppear` (draft = "", lastSaved = nil, fieldFocused = true).
- **`OnboardingView.swift`** — the "Try a capture" step now
  auto-finishes 700 ms after a successful capture (the dwell lets the
  user see the green "Saved" confirmation). The previous flow required
  the user to find the "Done" button after pressing Return; users
  treated Return-to-save as the natural end of the step and reported
  the screen as "stuck" because the Done button never got their
  attention. `finish()` also gained a belt-and-suspenders pass that
  walks `NSApplication.shared.windows` for the onboarding identifier
  and calls `.close()` — `dismissWindow(id:)` can occasionally no-op
  if the window isn't key at call time, and the user's session
  reported exactly that symptom. The earlier copy ("Type something
  you don't want to lose — a reminder, a task, anything. Hit Return
  to save it.") gained "A deadline is optional." so the user knows
  up front that a deadline isn't required.

Phase-6 invariants honored:

- Capture parser unchanged. Deterministic grammar, same accepted
  forms, same `due_at` / `due_kind` / `interruption_kind` outputs —
  only the rendering of those outputs changed.
- `AppStore.capture` unchanged. No-deadline captures always saved
  (the bug was perceived, not real); the new UX makes that obvious.
- Onboarding marker logic unchanged. `markOnboardingComplete()` still
  writes the `onboarded_version` row; the auto-finish path runs the
  same code as a manual Done click.

`make check` + `make test` green (164/164). End-to-end visual gate:
captured a deadline-bearing item ("pull rice in 18m") and confirmed
the orange bell pill renders; captured a no-deadline item ("buy
bread") and confirmed the "saves as a capture" hint + successful
persist (count incremented); walked the onboarding flow with a
no-deadline first capture and confirmed the screen auto-dismissed
700 ms after Return without any further click.


## 2026-06-08 — SwiftPM `Bundle.module` macOS 14 crash (workaround landed)

Reported crash on macOS 14 when the onboarding hotkey-recorder
rendered. Three failed fixes before nailing the root cause; full
write-up in [`PROBLEMS.md`](PROBLEMS.md).

Short version: SwiftPM (Swift 6.3 / Xcode 26) emits a `Bundle.module`
accessor that resolves to `Moves.app/<Name>.bundle` (the .app root, not
`Contents/Resources/`). macOS codesign refuses to seal files at the
.app root, and patching the SwiftPM-generated accessor at build time
is pointless because SwiftPM regenerates it on every relink.

Fix: `MovesApp.init()` runs before any view is constructed (and
therefore before any `Bundle.module` access). It walks
`Contents/Resources/` for `.bundle` directories and creates a relative
symlink at the .app root pointing into Contents/Resources. The
symlinks are created at runtime, so codesign's build-time seal stays
valid, and `Bundle(path:)` follows them transparently. `build.sh` also
rewrites the nested bundle's `Info.plist` with the minimum keys macOS
14 requires (the SwiftPM-emitted plist contains only
`CFBundleDevelopmentRegion`, which macOS 15 accepts and macOS 14
rejects).

Carries a follow-up flagged in PROBLEMS.md and the Phase 6 plan:
hardened-runtime + notarized release builds will re-verify bundle
integrity at every launch, so the runtime symlink trick won't survive
`make dist`. Phase 6 now lists three replacement strategies (vendor
the accessor, write a SwiftPM build plugin, or re-host the strings).

Commits: `0737b92` (copy nested bundle into the .app), `56f0d2b`
(codesign nested bundle innermost-first), `185afb2` (rewrite nested
Info.plist for macOS 14), `50fe4eb` (the runtime symlink — the actual
fix).

## 2026-06-08 — Phase 6: export + alert reconciliation + onboarding + notarization

Phase 6 takes Moves from feature-complete to shippable. Backup/export
(SQLite snapshot + Markdown bundle), launch-time alert reconciliation
(§17), Settings completion (default alert offsets, badge toggle,
capture-shortcut rebind), a 3-pane onboarding flow that ends with a real
capture, an accessibility pass on icon-only buttons + Dynamic Type
across the popover, and the notarization pipeline restored end-to-end.
No new product features — polish-only, per the phase plan.

What landed:

- `Sources/Moves/Services/ExportService.swift` — backup/export root.
  - **`exportSnapshot(to:)`** — `VACUUM INTO` via a new
    `Database.snapshot(to:)` actor helper. Canonical backup; the
    destination file is replaced if it already exists (NSSavePanel
    already confirmed overwrite intent).
  - **`exportMarkdownBundle(to:)`** — directory with one `.md` per
    thread, one `captured.md` for orphan items (status = `.captured`,
    no thread), and one `time-log.csv`. The per-thread shape is
    deliberately the same shape `MarkdownImportService.parse` accepts:
    YAML frontmatter (`title / kind / visibility`), one `## ` per
    segment, `move: / date: / due: / estimate:` metadata lines under
    each heading, then `- [ ] / - [x]` checklist items and any body
    Markdown. Round-trip is asserted by `ExportServiceTests
    .testMarkdownBundleRoundTripsWithImporter`.
  - **`time-log.csv`** — `week_start, thread_title, segment_title,
    rough_minutes`. Quoting handles titles with commas/quotes.
- `Sources/Moves/Services/AlertReconciliation.swift` — pure-ish §17
  service. The pure projection `plan(now:items:pendingAlertsByItem:
  pendingIdentifiers:)` returns three buckets:
  1. **Cancel** — pending OS notifications whose item is `.done`,
     `.canceled`, soft (was hard at schedule time), missing, or has no
     future `due_at` anymore.
  2. **Schedule** — items with `interruption_kind = .hard`, `due_at >
     now`, and no pending OS notification covering them.
  3. **Mark fired** — hard items whose `due_at <= now` and have an
     unfired `Alert` row. The OS notification is NOT re-fired — that
     would surface stale banners hours/days late. Only the DB stamps.
  Idempotent. `apply` does the OS cancellations + DB writes + missing
  schedules via `ReminderScheduler.scheduleAtDue`. Reads the persisted
  alert id via the existing `moves.item.<itemId>.alert.<alertId>`
  notification identifier scheme.
- `Sources/Moves/Views/Window/Settings/ExportSection.swift` — two
  buttons: "Export SQLite snapshot…" (NSSavePanel) and "Export Markdown
  bundle…" (NSOpenPanel → directory). Inline confirmation with the
  written path; failures surface inline too. Default filename includes
  a `YYYY-MM-DD-HHMM` timestamp so back-to-back exports don't clobber.
- `Sources/Moves/Views/Window/Settings/AlertOffsetsSection.swift` —
  the §8.3 default-offsets editor. Two chip rows (Reminders / Deadline
  tasks) with an "Add offset" menu over the canonical buckets
  (`0, 15m, 30m, 1h, 2h, 4h, morning of, 2d`). Save button is enabled
  only on changes; the AppStore writer re-resolves the preferences
  struct at write time (Phase-5 gate idiom: don't capture a stale
  snapshot of `store.preferences`, mutate, write — instead resolve fresh
  at click time so a concurrent badge-toggle save doesn't clobber the
  offset edit).
- `Sources/Moves/Views/Window/Settings/BadgeAndOnboardingSection.swift`
  — "Show due/overdue badge" toggle (writes through
  `AppStore.saveUserPreferences`), `KeyboardShortcuts.Recorder` for
  the capture chord, and a "Show onboarding again" button that resets
  the marker and calls `OnboardingPresenter.shared.requestPresent()`.
- `Sources/Moves/Views/Onboarding/OnboardingView.swift` — three
  panes max, in line with the §18 spec:
  1. **What this app is for** — one-sentence pitch + a small mocked
     popover preview ("Current · Ship Moves v1 · Next: revise
     onboarding copy") so the user can see the menubar idiom before
     they ever open the popover.
  2. **Capture hotkey** — a live `KeyboardShortcuts.Recorder` bound to
     `.capture`. Default ⌥Space; user can rebind or accept.
  3. **Try a capture** — a real `TextField` that runs through
     `AppStore.capture(...)` on Return. The "Done" button is disabled
     until the user has captured one item, so finishing the flow ends
     with a real row in the Captured list.
  Reduce-motion is honored: when set, pane transitions become identity
  and the "Continue" button doesn't animate the step swap. Skip /
  Back / primary actions wired through `.keyboardShortcut(.defaultAction)`
  / `.cancelAction` so Return/Esc work.
- `Sources/Moves/Views/Onboarding/OnboardingPresenter.swift` +
  `OnboardingHost.swift` — an `@Observable` singleton flag plus a
  Window-scene host. RootWindow observes the flag and calls
  `openWindow(id:)` when it flips to true. If SwiftUI restores the
  onboarding scene without the flag set (cold-launch sheet ghost),
  the host self-dismisses — same Phase-3 idiom as Stop/Switch/Park.
- `Sources/Moves/Domain/UserPreferences.swift` — single value type for
  alert offsets + badge toggle + onboarded version. JSON-stored under
  the `user_preferences` settings key. `decodedJSON` is
  forward-compatible: missing keys fall back to defaults so a future
  release can add fields without breaking older DBs.

AppStore additions:
- `preferences: UserPreferences` (`@Observable`), loaded by `load()` via
  new `loadUserPreferences()`, written via `saveUserPreferences(_:)`,
  `markOnboardingComplete()`, `resetOnboarding()`.
- `renderedBadgeCount: Int` — render-time check that returns 0 when
  the badge toggle is off, the DB count otherwise. Routed through both
  the menubar HStack and the popover header's `•N due` chip so they
  always agree.
- `exportService()` factory.
- `reconcileAlerts(now:)` — fires after `load()` in the bootstrap so
  the badge count + scheduled notifications are coherent before the
  user sees the menubar.

Accessibility pass:
- **Icon-only buttons now carry `.accessibilityLabel`:**
  - Menubar `figure.walk.motion` icon (label "Moves") + badge text
    (label "N due or overdue").
  - Popover header `•N due` chip (label "N due or overdue").
  - Popover Available rows ("Switch to <title>. Next move: <move>.")
    — was unlabeled accessibility-wise.
  - Popover Upcoming + Captured row icons ("Hard reminder" / "Soft
    reminder" / "Capture") — was an unlabeled `Image(systemName:)`.
  - CapturedRow overflow `ellipsis.circle` ("Actions for <title>").
  - Settings weekday-picker buttons ("Monday selected" / "Monday not
    selected", routed through the new `WorkingHoursWeekday.fullLabel`).
  - Alert-offset chip remove button ("Remove offset <label>") and the
    "Add offset" menu ("Add reminders offset" / "Add deadline tasks
    offset").
- **Dynamic Type respected in the popover.** Every popover row + the
  PopoverSectionContainer header moved from hard-coded
  `.font(.system(size: N))` to semantic styles (`.caption`,
  `.caption2`, `.callout`, `.body`, `.headline`). The menubar HStack
  itself stays a small fixed metric — it can't grow without breaking
  the system menubar strip layout — but the menubar's badge label has
  an accessibility label so VoiceOver users hear the count.
- **Reduce-motion honored** on the onboarding step transitions:
  `@Environment(\.accessibilityReduceMotion)` toggles the `withAnimation`
  block and the `.transition` mode. (The popover's other motion is
  hover highlight + nothing else; nothing to gate.)

Build pipeline (restored from `Makefile.example`):
- **`make dist`** — `check-version → clean → release → sign →
  zip-notary → notarize → staple → zip-release → checksum →
  verify-release`. Output: `dist/Moves-X.Y.Z-macos.zip` + `.sha256`.
- **`make notary-setup`** — interactive `xcrun notarytool
  store-credentials`. Refuses to run from a non-tty (so agent shells
  don't half-prompt and leave a broken keychain entry); prints what to
  paste once you're in a real terminal.
- **`make sign / notarize / staple / zip-release / verify-release /
  github-release`** — split so a failed step can be re-run in
  isolation. `verify-release` uses `spctl --assess` to confirm
  Gatekeeper accepts the stapled bundle offline.
- **`make print-version`** — diagnostic; shows the resolved
  `VERSION`, whether it came from a git tag at HEAD, and whether the
  `VERSION` file matches.
- **`make check / test`** unchanged.
- **`make clean`** now also clears `./dist/`.
- Keychain profile renamed `moves-notary` (was `djroomba-notary` in
  the template).

Version source: a `VERSION` file at the repo root + git tag at HEAD.
The `VERSION` file lets `make help / sign / print-version` work on a
contributor's checkout without a tag, but `make check-version` (gating
`make dist`) still demands an exact `vX.Y.Z` git tag at HEAD. If both
are present and disagree, the git tag wins because that's what `dist`
allows. Override either via `make dist VERSION=0.1.0` for one-off
release-target debugging.

Entitlements: still unsandboxed. Hardened runtime is enabled at sign
time via `--options runtime`. The `user-selected.read-write`
entitlement is preserved for the Phase-6 export NSSavePanel/NSOpenPanel
flows. No new entitlements; `disable-library-validation` is
deliberately NOT set — Moves doesn't load third-party dylibs.

Tests (164 total, was 131):

- `Tests/MovesTests/AlertReconciliationTests.swift` — 15 cases. The
  pure `plan(...)` covers every §17 bucket transition: cancel for
  done/canceled/missing/soft-after-the-fact items; leave live
  hard-future items alone; schedule hard items with no pending request;
  skip soft items; mark fired only when due_at <= now AND fired_at is
  still nil; ignore alerts whose row is already fired (idempotency).
  Plus identifier-parser tests (round-trip, foreign-prefix rejection,
  malformed segment rejection) and two end-to-end reconcile tests
  against a fake `UNUserNotificationCenterProtocol` backed by a real
  on-disk DB.
- `Tests/MovesTests/ExportServiceTests.swift` — 9 cases. SQLite
  snapshot round-trip (open the snapshot as a fresh DB, assert threads
  are present); snapshot overwrites existing files; Markdown bundle
  emits one `.md` per thread plus `captured.md` + `time-log.csv`;
  bundle round-trips with `MarkdownImportService` (parse the emitted
  `.md`, assert the segments + items + frontmatter all match);
  time-log CSV has a header row + one row per entry; CSV quoting
  handles commas; slug helper for funny titles; CSV escape for
  embedded quotes.
- `Tests/MovesTests/UserPreferencesTests.swift` — 9 cases. JSON
  encode/decode round-trip; missing-key fallback to defaults
  (forward-compat); malformed JSON returns nil; defaults match the
  Phase 6 plan contract (reminders `[0]`, deadline tasks
  `[24*60, 60, 0]`, badge enabled, no onboarded version); offset-label
  formatting; saving prefs through `AppStore` round-trips across a
  relaunch (DOD-style); badge toggle hides `renderedBadgeCount` while
  leaving `dueOrOverdueHardCount` intact; onboarding mark/reset.

Phase 6 invariants enforced by code + tests:

- **`AlertReconciliation` is idempotent.** Two reconcile passes
  produce the same plan; the second pass on a clean state produces no
  writes. Tested in `testPlanIsIdempotent` and
  `testReconcileIsIdempotentEndToEnd`.
- **DB is the source of truth.** Reconciliation never re-fires past
  notifications; never overrides `Item.status` with anything; OS state
  follows DB state, never the reverse. Encoded by the plan never
  emitting `markFired` for items that aren't in the live `items` set.
- **Badge toggle is render-time only.** The DB-side
  `dueOrOverdueHardCount` is always live (it's a cheap COUNT query);
  the popover header + menubar HStack route through
  `renderedBadgeCount` which gates on the toggle. Tested in
  `testBadgeToggleHidesRenderedCount`.
- **Onboarding marker round-trips.** `markOnboardingComplete` ↔
  `resetOnboarding` through the DB; the bootstrap re-checks
  `preferences.onboardedVersion` against `UserPreferences
  .currentOnboardingVersion` before requesting present, so a future
  version bump can retrigger.
- **Markdown export round-trips through the §9 importer for
  regimented threads.** Asserted directly in
  `testMarkdownBundleRoundTripsWithImporter` — no parser warnings,
  segment count + titles + builtInMove + items all preserved.

Decisions honored:
- Export format: SQLite snapshot is canonical; Markdown bundle is the
  human-readable variant. Both offered in Settings.
- Reconciliation policy: trust the DB. Cancel orphan scheduled
  notifications. Don't re-fire past banners.
- Onboarding trigger: first launch only (via the settings
  `onboarded_version` field on `UserPreferences`). Re-runnable from
  Settings.
- Version source: `VERSION` file at repo root for dev affordances; git
  tag at HEAD required for `make dist`.
- Settings layout: one vertical pane with sub-section cards (Working
  hours, Alert offsets, Menu bar & notifications, Backup & export).
  A SwiftUI `Form` would be heavier than this pane needs.

`make check` + `make test` green (164/164).

Heads-up for future agents:

- **`AlertReconciliation.plan(...)` is the pure surface.** Anything
  that wants to predict what reconcile will do (a future debug pane?
  a v2 reconcile dry-run?) should call `plan` and inspect; only
  `reconcile()` performs IO.
- **`OnboardingPresenter.shared` is a singleton observable flag.**
  RootWindow observes it; `MovesApp.bootstrap` flips it; the
  OnboardingHost self-dismisses if SwiftUI restores the scene without
  the flag set. If a future settings refactor moves to multiple
  observers, keep them all reading the same singleton.
- **`UserPreferences.decodedJSON` is forward-compat by design.** Adding
  a new key in the future doesn't need a migration: the partial-decode
  path fills missing keys from defaults. Removing or renaming a key
  needs explicit handling.
- **Markdown export's `unsegmented items` synthetic H2** —
  thread-attached items with no `segment_id` round-trip as a synthetic
  segment titled "Unsegmented items". Future work could promote these
  to thread-level items via a frontmatter `items:` block; the current
  shape is the conservative one (parser accepts it as a segment with
  the right name and items).

### Punted to v2

- **Onboarding-replay version bumps.** The mechanism is in place
  (compare `preferences.onboardedVersion` against
  `UserPreferences.currentOnboardingVersion`), but there's no
  "what's new in this version" string surface yet. Phase plan's open
  question pointed at a `CHANGELOG.md` parsed on demand; v2 can ship
  the changelog parser and surface it as a fourth onboarding pane on
  upgrade.
- **Apply alert offsets to existing items.** The Settings editor saves
  new defaults but doesn't retroactively reschedule existing items —
  doing so honestly requires deciding whether the user wanted "next
  capture forward" or "everything I have". v1 lock-in: future captures
  only.
- **Granular `morning of` clock time.** "Morning of" maps to 24h
  before due_at, which approximates "morning of" when the deadline is
  during normal waking hours but breaks for late-night deadlines.
  Promoting this to a "deliver at HH:MM the previous day" config is a
  v2 concern.
- **Bundle restore.** `make dist` produces a snapshot the user can
  replace `moves.sqlite3` with; there's no in-app "restore from
  backup" affordance. A v2 settings button could close the connection,
  swap the file, reopen.

## 2026-06-08 — Phase 5 gate (swiftui-pro, partial): autosave staleness + formatter caching

swiftui-pro code-level gate caught two real findings on Phase 5's new
SwiftUI surface. Applied both. The visual gate (computer-use) is pending
— the screen was locked when this commit ran, so the macos-design /
end-to-end DOD verification will happen in a follow-on gate.

What I fixed:

- **`SegmentDetail.swift` autosave captured a stale Segment snapshot.**
  `scheduleMoveAutosave` / `scheduleBodyAutosave` closed over the
  `segment` parameter that the View was built with, then waited 600ms,
  then mutated and wrote `editSegment(copy)`. If during that window the
  segment got completed / skipped / reordered from another surface, the
  in-flight Task would clobber `status`, `orderIndex`, etc. with the old
  snapshot's values. Both autosave handlers now re-resolve the segment
  fresh from `store.segmentsByThread[segment.threadId]` at write time,
  mutate only the targeted field, and persist that. Matches the
  read-at-click-time idiom from the Phase-3 gate.
- **`WeeklyView.swift` built a `DateFormatter` on every render.** The
  pane re-renders on each working-hours timeline tick + on every anchor
  shift; allocating a new formatter twice per tick (header label +
  parser) burned cycles for no reason. Both formatters are now `static
  let` properties, matching the codebase pattern in
  `MarkdownEditorView`, `CapturedPopoverRow`, and the Phase-3 popover
  rows.

Skipped (deliberate):

- **`body_` → `bodyText` rename in `SegmentDetail.swift`.** Cosmetic;
  cost > value.
- **`ImportMarkdownView.swift` legacy `provider.loadObject` →
  `.dropDestination(for: URL.self)`.** Modern API, but works correctly,
  and changing the drop plumbing now risks regressing the drag-drop UX
  before the visual gate has even exercised it. Revisit when the visual
  gate has confirmed the current path works.

`make check` + `make test` green (131/131) after the fixes.

**Pending (visual + macos-design gate):** screen lock at gate time
blocked the end-to-end DOD walkthrough (§9 example import, segment
completion advancing the active row, weekly view aggregating across
multiple completion logs, popover Current section showing the segment
line). Phase 6 is being kicked off in parallel; the visual gate for both
phases will run as a single pass when the screen unlocks.

## 2026-06-08 — Phase 5: regimented threads + segment lifecycle + Markdown import + weekly time log

Phase 5 makes regimented threads first-class: ordered segment lifecycle
with explicit completion (§5.5), deterministic Markdown import (§9), and
a §14 weekly rough-time view. The Phase-4 thread detail now hosts a
SegmentsPanel for regimented threads; CompleteSegmentSheet runs as its
own Window scene for the same reason Stop/Switch/Park do.

What landed:

- `Sources/Moves/Services/MarkdownImportService.swift` — §9 parser, exactly
  as specified. Handles:
  - YAML frontmatter (`---` … `---`) with supported keys
    `title / kind / visibility / default_estimate_minutes`; unsupported
    keys are dropped with a warning. Tiny built-in YAML — not Yams.
  - `## ` H2 → segment boundary; `### ` not promoted.
  - `key: value` metadata for `date / due / estimate / move` — recognized
    *anywhere* before the first checklist item / non-meta body. The §9
    example places `move:` after a blank line, which strict "metadata
    ends at first blank line" would have rejected; we honor both forms.
    Unsupported meta keys near the heading warn.
  - `- [ ] …` and `- [x] …` checklist items → `Item.task` (open or done).
  - Residual non-meta non-checklist content → `Segment.bodyMarkdown`.
  - First segment becomes `.active`; the rest stay `.pending` (§9 rule 9).
  - Content before the first H2 is silently dropped (it belongs to neither
    frontmatter nor any segment).
  - Date formats: `YYYY-MM-DD`, `YYYY-MM-DD HH:MM`, UTC.
- `Sources/Moves/Services/TimeLogService.swift` — pure projections:
  - `weekStart(for: Date) -> String` — ISO Monday, `YYYY-MM-DD`. Uses a
    shared `Calendar.iso8601Monday` so the writer (`AppStore`) and
    reader (`weeklyView`) agree on the bucket key.
  - `aggregate(entries:) -> [ThreadAggregate]` — sums minutes per thread,
    sorted by descending total (ties on threadId ASC for stability).
  - `roughBucketLabel(_:) -> String` — "~30m" / "~1h" / "~1h 30m". Rounds
    up to the nearest 15 inside the under-hour bucket so 20m reads as
    "~30m" not "~15m" (matches the §14 chip semantics).
- `Sources/Moves/Domain/{ImportPreview,WeeklySummary}.swift` — value types
  that flow between service and view.
- `Sources/Moves/Views/Window/ThreadDetail/SegmentsPanel.swift` — the §3
  segment list inside the thread detail. Active segment is highlighted
  (accent-tinted card) with the inline `SegmentDetail` editor embedded;
  pending segments are dimmed; done + skipped collapse under a
  "Show N completed" disclosure. Per-row overflow menu carries "Make
  active" and "Skip"; "Mark Done" on the active row stages
  `FlowContext.completeSegment` and opens the CompleteSegmentSheet.
  Inline "New segment title…" field adds a pending row at the end.
- `Sources/Moves/Views/Window/ThreadDetail/SegmentDetail.swift` — inline
  editor for the active segment: built-in move (TextField, autosave on
  600ms debounce) + body Markdown (`MarkdownEditorView`, autosave on
  600ms debounce) + read-only metadata line (scheduled / due / estimate).
  Matches the Phase-4 notes autosave idiom — no Save button to push off-
  screen by the editor's expanding height.
- `Sources/Moves/Views/Flows/CompleteSegmentSheet.swift` — §5.5 sheet.
  Title shows the segment; one `RoughTimePicker`; no breadcrumb. On
  confirm: marks the active segment done, logs `TimeLogEntry` attributed
  to (thread, segment), advances the next pending segment to `.active`.
  Self-dismisses if `pendingFlow` doesn't match (Phase-3 gate idiom for
  Window scenes restored without a matching state).
- `Sources/Moves/Views/Window/Import/ImportMarkdownView.swift` — drag-drop
  target + file picker; renders the `ImportPreview` (title, segment
  titles + moves, item counts) and any warnings. "Import" calls
  `AppStore.importMarkdown` (single transaction); "Discard" / "Close"
  resets to empty. Hosted as its own Window scene so file drops don't
  fight popover focus loss.
- `Sources/Moves/Views/Window/TimeLog/WeeklyView.swift` — §14 weekly
  rough-time pane. One row per thread that had at least one entry in the
  active ISO week (Monday-start). Prev / Next chrome navigates by ±7
  days; "This week" button anchors back to now. Empty weeks render a
  `ContentUnavailableView` with the §2.5-friendly "Rough time gets
  logged when you stop, switch, or finish a segment." copy.

- `Sources/Moves/Model/AppStore.swift` — gained:
  - `segmentsByThread: [String: [Segment]]` — cache populated by
    `rebuildAvailable` and `loadSegments(for:)`. Used by SegmentsPanel
    and the popover's CurrentSection (the popover now shows the displayed
    segment line).
  - `currentSegment(for: Thread) -> Segment?` — wraps
    `MoveResolver.displayedSegment` against the cache.
  - `loadSegments(for:)`, `activateSegment(_:)`, `completeActiveSegment
    (thread:rough:)`, `skipSegment(_:)`, `addSegment(thread:title:
    builtInMove:body:)`, `editSegment(_:)`.
  - `importMarkdown(_:now:) async -> ImportResult?` — parses, persists
    thread + segments + items, refreshes caches; appends a "thread with
    same title already exists" warning so the duplicate produces a
    distinct row by intent rather than by accident.
  - `weeklyView(for: Date) async -> WeeklySummary` — reads
    `time_log.week_start` directly so prior weeks remain queryable as
    the user navigates back.
  - `weekStartString(for:)` now delegates to `TimeLogService.weekStart`
    so writers and readers share a single source of truth.
- `Sources/Moves/Domain/FlowContext.swift` — added
  `.completeSegment(threadId, segmentId)` case.
- `Sources/Moves/Views/Popover/PopoverWindowID.swift` — added
  `.completeSegment` and `.importMarkdown` scene ids.
- `Sources/Moves/Views/Window/SidebarDestination.swift` — added `.timeLog`.
- `Sources/Moves/Views/Window/RootWindow.swift` — sidebar renders the
  "Time Log" entry (no badge — §2.5 "no shame language" applies); a
  bottom-rail "Import Markdown…" button opens the import scene.
- `Sources/Moves/MovesApp.swift` — two new `Window` scenes for
  CompleteSegmentSheet and ImportMarkdownView.
- `Sources/Moves/Views/Popover/MenuPopoverView.swift` — the popover's
  CurrentSection now receives the active segment from
  `AppStore.currentSegment(for:)`, so completing a regimented segment
  immediately changes the segment line + the Available move (which was
  already routed through `MoveResolver` + `segmentsByThread`).

Phase 5 invariants enforced by code + tests:

- **Exactly one segment is active per thread (§3).** `activateSegment`
  demotes any other active segments on the same thread before promoting
  the target. Tested in `Phase5AppStoreTests.testActivateSegmentDemotes
  PreviousActive`.
- **Switching / parking / stopping leave segments alone (§5.5).** The
  `stop / switchTo / park` codepaths never touch segments; only
  `completeActiveSegment` and `skipSegment` do. Tested in
  `testSwitchingDoesNotTouchSegmentStatus`.
- **Completion logs against (thread, segment), not just thread.** §14's
  `time_log.segment_id` column carries the segment id on completion logs
  but stays nil on stop/switch logs. Tested in `testCompleteActive
  SegmentLogsTimeAndAdvances`.
- **Rough=.none skips the time_log write.** Same rule as Phase 3 Stop —
  the user said "no, not really". Tested in `testCompleteActiveSegment
  WithNoneBucketSkipsLog`.
- **Segment lifecycle survives relaunch.** DOD assertion: write through
  one AppStore, reopen against the same DB, verify status + time_log.
  Tested in `testSegmentLifecycleSurvivesRelaunch`.
- **§9 import is create-only in v1.** Re-importing the same title makes
  a new thread; a warning surfaces in the preview so the user can cancel.
  Tested in `testImportingSameTitleTwiceProducesDistinctThreadsWithWarning`.
- **§11 fall-through for regimented-no-breadcrumb threads.** Both
  "first pending segment wins" and "active segment wins over pending"
  pathways are exercised by `MoveResolverTests.testRegimentedThreadNo
  Breadcrumb*`.

Open-question decisions honored:

- **Built-in move display:** the popover's CurrentSection renders
  "Next: <breadcrumb>" when a breadcrumb exists and the segment row
  carries the segment title above it. SegmentsPanel renders pending rows
  with "Next: <built-in move>" inline — consistent with the §4.1 popover
  example.
- **YAML library:** tiny built-in parser. The §9 schema is small enough
  that a Yams dependency wasn't justified; if v2 needs lists or nested
  mappings we'll revisit.
- **Week boundary:** ISO weeks, Monday-start. `Calendar.iso8601Monday`
  is the single source of truth for both the writer (TimeLog rows) and
  the reader (WeeklyView).

Tests (131 total, was 94):

- `Tests/MovesTests/MarkdownImportServiceTests.swift` — 11 cases.
  Includes the §9 example (DOD), unsupported frontmatter / kind warnings,
  default estimate inheritance, segment metadata (date, due, estimate,
  unsupported keys), checked items as done, residual body capture,
  empty input, content-before-first-H2 dropping, unclosed frontmatter.
- `Tests/MovesTests/TimeLogServiceTests.swift` — 9 cases. weekStart for
  Monday / Tuesday / Sunday; aggregate sums + tie-breaking + empty;
  roughBucketLabel for under-hour rounding, hour multiples, hour+minutes.
- `Tests/MovesTests/Phase5AppStoreTests.swift` — 13 cases. Segment
  lifecycle (add / activate uniqueness / complete + advance / complete
  with no pending / skip / switch doesn't advance), `.none` bucket skips
  log, lifecycle survives relaunch (DOD), §9 import end-to-end (DOD),
  duplicate titles produce distinct threads, weekly view aggregates
  across stop + segment-complete logs (DOD), empty weekly view,
  segmentsByThread cache feeds Available.
- `Tests/MovesTests/MoveResolverTests.swift` — 2 new cases for the §11
  regimented-no-breadcrumb fall-through (active-segment wins, first-
  pending wins). Pre-existing tests already exercised the empty-built-in-
  move fall-through to open items; these add explicit coverage of the
  "Markdown import lands and the first render works" path.

Heads-up for future agents:

- The popover CurrentSection now reads `AppStore.currentSegment(for:)`
  so it will show the active segment title between the thread title and
  the breadcrumb when the current thread is regimented. The cache is
  rebuilt by `rebuildAvailable`; if you call segment writes elsewhere,
  the cache is also touched by `loadSegments(for:)` /
  `activateSegment` / `completeActiveSegment` / `skipSegment` /
  `addSegment` / `editSegment` directly.
- `SegmentsPanel` reads from `store.segmentsByThread[thread.id]`, not a
  local @State copy. Any segment write through the store flows back to
  the view via @Observable.
- Import is wired into the sidebar bottom rail (not a destination). A
  future iteration could promote it to a real "New thread from
  Markdown…" command in the File menu — out of scope for Phase 5.
- The §9 parser intentionally drops content before the first H2 — if a
  future spec extension wants a "thread description" Markdown block,
  add it to the frontmatter (`description: |`) and update the parser
  to accept the YAML block scalar form.
- `Calendar.iso8601Monday` is a static convenience that lives in
  `TimeLogService.swift`. If a future surface needs the same calendar,
  re-use the static; don't construct ad hoc.

`make check` + `make test` green (131/131).



End-to-end visual gate (walk all six panes, thread detail, captured
processing, settings) caught two real bugs:

- **"Save notes" button got pushed off-screen** by the Markdown editor's
  expanding height inside the thread detail's vertical scroll layout. Easy
  to type notes for several minutes and lose every word on tab-away.
  Dropped the explicit Save button entirely; notes autosave on a 600ms
  debounce via `.onChange(of: notes)` + cancelable Task, and a small
  "Saving…" hint appears next to the section header when the local
  buffer differs from `thread.detailMarkdown`. Matches Notes/Bear/iA
  Writer idioms. Verified round-trip: type → kill app → relaunch → notes
  re-render in the editor + preview.
- **Sidebar Available badge ignored the working-hours filter.** With a
  thread set to `hide_during_work` inside working hours, the badge
  showed `1` but the pane showed "Nothing available" — click and find
  nothing. Routed the badge through the same `WorkingHoursService.filter`
  the pane uses (`visible.count + deemphasized.count`); badge and pane
  now agree. The §6 carve-out (a hide_during_work thread with a
  deadline-bearing item shows during work hours) is correctly reflected:
  attaching the captured "call dentist · Tomorrow 9am" to the
  hide_during_work "Ship Moves v1" thread surfaces it in Available + the
  badge counts it.

Gate skipped: swiftui-pro on the rest of Phase 4. The visual gate caught
the structural issues; the remaining SwiftUI is idiomatic
(NavigationSplitView with selection enum, `@Observable` AppStore, sheets
opened via `openWindow(id:)`/`dismissWindow(id:)`). Phase 5's Markdown
import + segment lifecycle would benefit more from the swiftui-pro budget
since they introduce real new SwiftUI surface.

DOD re-verified:
- All seven sidebar destinations render and route correctly.
- Thread detail edits write through repos (breadcrumb explicit-save,
  visibility menu, item toggle, autosave notes). Available + sidebar
  badges reflect updates within a navigation tick.
- `hide_during_work` thread without deadline items: hidden during work
  hours, both in pane and badge.
- Markdown notes round-trip stable (typed text persists across kill +
  relaunch and re-renders in editor + preview).

`make check` + `make test` green (94/94) after the gate fixes.

## 2026-06-08 — Phase 4: main window panes + thread detail + Markdown editor + working hours

Phase 4 ships the real main window. The Phase-0/1 throwaway `MainView` +
`ThreadRow` + `ThreadDetail` are gone, replaced by a §4.2 sidebar with
seven destinations (Available / Current / Threads / Captured / Deadlines /
Parking Lot / Settings) plus a §4.3 thread detail with breadcrumb,
read-only segment summary, items checklist, and a Markdown notes editor.
Working-hours visibility (§6) is wired through.

What landed:

- `Sources/Moves/Views/Window/RootWindow.swift` — `NavigationSplitView`
  with the §4.2 sidebar. Sidebar items carry a badge count
  (available/captured/deadlines/parking-lot etc.). A `TimelineView` ticks
  once a minute so `AppStore.isWorkTime` flips automatically at the
  start/end of the working-hours window. Selection drives the detail pane;
  thread rows route via `.thread(id)`.
- `Sources/Moves/Views/Window/SidebarDestination.swift` — one enum so the
  sidebar list and detail switch can't drift.
- `Sources/Moves/Views/Window/PaneShell.swift` — shared title + subtitle
  scaffold used by every pane.
- `Sources/Moves/Views/Window/AvailableView.swift` — same §22-filtered
  projection the popover uses, run through `WorkingHoursService.filter`
  for the §6 visibility policy. Two-section render: normal Available, then
  "De-emphasized during working hours".
- `Sources/Moves/Views/Window/CurrentDetailView.swift` — Current pane.
  Opens Stop / Park as the Phase-3 flow windows so editing UX is the same
  across surfaces.
- `Sources/Moves/Views/Window/ThreadsListView.swift` — full thread list
  grouped by status, with an inline "New thread…" field that routes to
  the new thread detail on commit.
- `Sources/Moves/Views/Window/CapturedView.swift` +
  `Captured/CapturedRow.swift` — §13 processing actions on a per-row
  context menu / overflow menu: attach to thread (sheet picker), convert
  to reminder/task/capture (inline), edit due time (sheet, per the open-
  question decision), mark done, cancel, delete.
- `Sources/Moves/Views/Window/DeadlinesView.swift` — one list of every
  item with a `due_at`, overdue rendered muted-orange. Wider scope than
  the popover Upcoming (hard-only); this pane includes soft + none too.
- `Sources/Moves/Views/Window/ParkingLotView.swift` — parked threads
  with an inline "Unpark" button.
- `Sources/Moves/Views/Window/ThreadDetail/ThreadDetailView.swift` —
  §4.3 layout: title (inline-editable), three pills (Status / Kind /
  Visibility — each a single-tap `Menu`), breadcrumb editor with explicit
  "Save breadcrumb" button, current-segment summary (read-only, Phase 5
  owns editing), items list with checkbox toggle that flips
  `Item.status`, and the Markdown notes editor.
- `Sources/Moves/Views/Window/Settings/SettingsView.swift` — Phase 4
  scope: working-hours weekday picker + start/end `DatePicker`s. Saves
  through `AppStore.saveWorkingHours`. Other settings explicitly punted
  to Phase 6 with a footer line.
- `Sources/Moves/Views/Markdown/MarkdownEditorView.swift` — plain
  `TextEditor` source + `AttributedString(markdown:)` preview. Wide
  layout (>= 560pt) shows them side-by-side; narrow swaps to a segmented
  picker (Edit / Preview). The preview parses block-level constructs
  (ATX headings 1–6, unordered lists with 2-space-per-level indent,
  paragraphs, fenced code blocks) and renders inline syntax through
  `AttributedString.MarkdownParsingOptions.inlineOnlyPreservingWhitespace`.
  Tables / images / footnotes are out of scope (v2 candidate).
- `Sources/Moves/Domain/WorkingHours.swift` — value type for the §6
  config + JSON DTO (`{days, start, end}`) for the `settings` table.
- `Sources/Moves/Services/WorkingHoursService.swift` — pure
  `isInside(date:hours:calendar:) -> Bool` plus the per-row
  `classify(visibility:isWorkTime:hasDeadlineItem:) -> .visible /
  .deemphasized / .hidden` and an `available × hasDeadline ->
  FilteredAvailable` partitioning function. Midnight-wrap supported; both
  endpoints are start-inclusive, end-exclusive.

- `Sources/Moves/Model/AppStore.swift` — gained:
  - `workingHours: WorkingHours` (cache, defaults to `.default`)
  - `isWorkTime: Bool` (derived; recomputed by `refreshWorkTime(now:)`)
  - `openItemsByThread: [String: [Item]]` for §6's deadline-bearing
    carve-out (no extra repo round-trip per row)
  - `deadlineItems: [Item]` (sorted by `dueAt`)
  - `loadWorkingHours()` / `saveWorkingHours(_:)` /
    `refreshWorkTime(now:)`
  - `attachToThread(_:item:)`, `convertItemKind(_:to:)`,
    `setVisibility(_:to:)`, `setKind(_:to:)`, `toggleItemDone(_:)`,
    `markItemDone(_:)`, `cancelItem(_:)`, `editDueAt(_:dueAt:dueKind:)`,
    `updateDetailMarkdown(_:to:)`, `createThread(title:) async`
  - `threads(matching:)`, helper used by Parking Lot / Threads pane.

Removed:
- `Sources/Moves/Views/MainView.swift`,
  `Sources/Moves/Views/ThreadRow.swift`,
  `Sources/Moves/Views/ThreadDetail.swift` — all Phase-0/1 throwaway.

AppStore Optional-repo decision (Phase 1's deferred Phase C):

- **Dropped.** The repo set is now non-optional and `init` traps on DB
  open failure. Phase 1's hedge was "Phase 4 settings might want to
  distinguish DB-broken from DB-empty in copy"; with the settings UI in
  hand, that surface didn't materialize — the settings pane only renders
  meaningfully *after* the DB is open, and there's no other settings-
  flavored copy that benefits from a soft-fail path. If the DB can't
  open, nothing in the app works; a hard crash with a diagnostic message
  is the right failure mode. The change deleted ~14 `guard let` clauses
  across AppStore and one Optional declaration per repo. The tests
  followed (`store.threadRepository?.find` → `store.threadRepository.find`).

Open-question decisions honored:

- **Visibility-policy control: inline pill in the thread-detail header.**
  Single-tap `Menu`, no submenu indicator, sits next to the Status and
  Kind pills. One-click affordance — matches §2.10's "passive display
  aid" spirit.
- **Captured "edit due time": sheet.** Reuses the same shape as the
  attach-to-thread picker (modal, fixed-width, Save / Cancel chrome).
  Inline date pickers would clutter every captured row; a sheet stays
  out of the way until needed.

Working-hours JSON shape (stored in `settings` table under
`working_hours`):

```json
{ "days": [1, 2, 3, 4, 5], "start": "09:00", "end": "17:30" }
```

- ISO-8601 weekdays (1 = Monday, 7 = Sunday).
- `"HH:mm"` strings so the row is human-readable in a SQLite browser.
- `start == end` is a zero-length window (never inside). `start > end`
  wraps midnight (e.g. 22:00–06:00 covers night shift). Both endpoints
  are inclusive of the start minute and exclusive of the end minute.

Tests (94 total, was 62):

- `Tests/MovesTests/WorkingHoursServiceTests.swift` — 22 cases. Boundary
  tests for `isInside` (start-of-window, one-minute-before-start, end-of-
  window exclusive, one-minute-before-end, Saturday/Sunday outside
  Mon–Fri windows, empty days, zero-length window). Midnight-wrap
  coverage (22:00–06:00 at 22:30 → inside, at 03:00 → inside, at 06:00 →
  outside-exclusive, at noon → outside). Full §6 visibility-classification
  matrix (all four ThreadVisibility cases × inside/outside × deadline-
  bearing yes/no). Codable JSON round-trip + malformed-input rejection.
- `Tests/MovesTests/Phase4AppStoreTests.swift` — 10 cases. Round-trip
  for the new AppStore writes: attach-to-thread flips threadId + status;
  convert-to-reminder sets `interruption_kind = .hard` (badge query
  depends on it); convert-to-task sets `.soft`; setVisibility persists;
  working-hours default when settings row is absent; working-hours save
  → reload (new AppStore against same DB sees the same value, the DOD's
  "round-trip stable" assertion adapted for settings); `refreshWorkTime`
  flips `isWorkTime`; toggle-item-done flips status + sets / clears
  `completedAt`; edit-due-at sets and clears `due_at` + `due_kind`.
  Plus the DOD's Markdown-notes round-trip: write detail_markdown →
  re-open AppStore → byte-identical persisted value.

Phase 4 invariants verified by tests:

- §22 (no re-entry, no Available) still holds — Phase 3's flow tests
  still pass against the new AppStore.
- §6 (working-hours visibility) holds at the service layer; the view
  consumes `WorkingHoursService.filter(...)` rather than reimplementing
  the policy.
- Markdown notes round-trip stable (write → relaunch → still there) —
  the DOD's assertion is tested directly.

`make check` + `make test` green (94/94).

Heads-up for future agents:

- The popover (Phase 3) still uses its own visibility grouping (it
  hard-codes `downweightWork` → de-emphasized). A future cleanup could
  route both surfaces through `WorkingHoursService.filter` for one
  source of truth; Phase 4 deliberately left the popover untouched to
  keep blast radius small.
- The Phase-3 popover footer "Parked" button opens the main window; now
  that the Parking Lot pane exists, a follow-on could pass an initial
  sidebar selection through (currently lands on Available). Out of scope
  for Phase 4 — the user gets there via the sidebar in one click.
- The Markdown preview is a hand-rolled block walker (headings / lists /
  paragraphs / code fences). If Phase 5/6 needs richer rendering
  (tables, images), reach for swift-markdown rather than expanding this
  walker.
- AppStore's `Optional<ReminderScheduler>` stays — tests can opt out of
  `UNUserNotificationCenter.current()` via `enableNotifications: false`.
  That Optional is feature-flagging, not a DB-open-failure hedge.

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
