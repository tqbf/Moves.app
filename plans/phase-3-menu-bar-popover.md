# Phase 3 — Menu-bar popover & current-state flows

**Goal:** Build the daily-driver popover and the Stop / Switch / Park
flows that turn the app from "list of reminders" into "re-entry surface."

**Reads:** INITIAL-PLAN.md §2.1–§2.10 (design principles), §4.1 (popover
layout), §5.1–§5.5 (flows), §11 (move resolution), §12 (Available
ordering), §14 (rough-time picker), §22 (core invariant).

**Builds on:** Phase 1 (domain + `MoveResolver`), Phase 2 (Captured items
+ Upcoming feed).

## Deliverables

- `Sources/Moves/Views/Popover/MenuPopoverView.swift` — top-level popover
  layout from §4.1. Sections, in order:
  1. **Current** — thread title, current segment (if any), breadcrumb,
     `[Stop] [Switch] [Park]`. Null-current renders "Not working on
     anything" neutrally (§2.6).
  2. **Upcoming** — next hard reminder + runway from `HeadroomService`;
     other hard/soft items below.
  3. **Available** — one row per thread with a resolved move
     (`MoveResolver`); sectioned per §12.
  4. **Captured** — recent Items without a thread.
  5. Footer: `[Capture…] [Parking Lot] [Open App]`.
- `Sources/Moves/Views/Popover/CurrentSection.swift`,
  `UpcomingSection.swift`, `AvailableSection.swift`, `CapturedSection.swift`
  — each owns one section so the parent stays readable.
- `Sources/Moves/Services/HeadroomService.swift` — given current time +
  items, returns `(nextHardItem: Item?, runway: Duration?)`. Pure.
- `Sources/Moves/Views/Flows/StopSheet.swift`,
  `SwitchSheet.swift`, `ParkSheet.swift` — sheet-style modals from
  §5.2/§5.3/§5.4 with prefilled breadcrumb + rough-time chips. Park asks
  for breadcrumb first.
- `Sources/Moves/Views/Flows/RoughTimePicker.swift` — the
  `none / 15m / 30m / 45m / 1h / 2h / 3h+` chip row from §14.
- `AppStore` gains: `current`, `start(_:)`, `stop(breadcrumb:rough:)`,
  `switch(to:breadcrumb:rough:)`, `park(_:breadcrumb:)`.

## Decisions

- **Selection of "current":** writes go through `CurrentStateRepository`
  (one-row `current_state` table from §10). The popover reads
  `AppStore.current` (cached projection).
- **Park flow:** breadcrumb-required modal first, then move thread to
  parked, then collapse out of Available. No rough-time prompt on park
  (parking ≠ stopping).
- **Available ordering:** v1 uses `last_touched_at DESC` per §12; manual
  ordering is a v2 candidate. Persist `last_touched_at` whenever Current
  changes or a thread's breadcrumb is edited.
- **De-emphasis section:** rendered as a separate `Section` with reduced
  font weight + secondary foreground style, not hidden, per §2.10 / §6.

## Out of scope

- Main window editing surfaces (phase 4).
- Markdown editor (phase 4).
- Regimented segment advancement (phase 5) — the popover renders
  `segment.built_in_move` when present, but the flows in this phase
  never advance segments.

## Definition of done

- Clicking an Available row sets it as Current (§5.1) and re-touches it.
- Clicking another Available row while one is Current opens the Switch
  sheet, prefilled (§5.3); confirming swaps Current.
- Stop sheet clears Current; Park sheet moves the thread to parked and
  drops it from Available.
- Threads with no re-entry point (no breadcrumb, no segment with move, no
  open item) **do not** appear in Available (§22 invariant).

## Open questions

- Popover dismissal during a sheet: do sheets present inside the popover
  window, or open a separate window? Decision: separate `Window` scene
  for each flow — `MenuBarExtra` popovers auto-dismiss on focus loss,
  which would close the sheet's host. Validate with computer-use.
- Should "Stop" be reachable by keyboard from the popover? Yes — `S` is
  the natural shortcut; document it inline.
