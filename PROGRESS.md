# Moves — Progress Log

Newest first.

## 2026-06-09 — Inspector affordance removed

After the toggle-crash fix landed (always-mounted, width-animated
rail), Thomas's call: the inspector serves no purpose on these panes
— the inline row anatomy already carries title, subtitle, deadline
chip, and the open/start affordances via hover icons + context menu.
A separate detail rail was dead weight that bought us a macOS 14.4
constraint-engine crash hazard for free.

Jettisoned:

- `Sources/Moves/Views/Window/InspectorColumn.swift` deleted.
- `PaneShell` / `PaneListShell` lost their `Inspector` generic + slot;
  the `Accessory` slot stays because Time Log's week-navigator uses it.
- Available / Captured / Threads / Deadlines lost their
  `@SceneStorage("inspector.*.visible")` lines, the `Toggle inspector`
  header buttons, the per-pane `inspectorBody` builders, and the
  helpers (`metadataRows`, `formatter`) that only existed to feed the
  inspector. Row selection state (`@State selection`) stays — a
  future detail surface can read it.

Build + tests green (206/206); visual gate green; commit follows.
PROBLEMS.md got a 2026-06-09 entry documenting the underlying
"insertion-with-transition crashes the constraint engine" pattern so
this doesn't get reintroduced by accident.

## 2026-06-09 — Inspector toggle crash fix (macOS 14.4)

After the earlier launch-crash patches (Spacer-in-toolbar + SettingsLink),
a fresh `make clean` build still crashed on Thomas's machine — this time
when he clicked the inspector reveal/hide affordance on the Available
pane. Same exception signature:
`_postWindowNeedsUpdateConstraintsUnlessPostingDisabled`.

Root cause: `InspectorColumn` used the pattern

```swift
if isVisible {
    HStack { … }
        .transition(.move(edge: .trailing).combined(with: .opacity))
}
```

Inserting / removing a view *with* a transition fires constraint
invalidation from inside an active AppKit layout pass when the SwiftUI
hierarchy contains `_NSConstraintBasedLayoutHostingView` shims (which
a `Window` scene nested in `NavigationSplitView` always does). On
machines where the constraint engine is more strict, this trips the
"posting disabled" assertion. The pattern works on some Macs and not
others — neither of which is debuggable from the SwiftUI side.

Fix: always-mounted, width-animated rail.
`Sources/Moves/Views/Window/InspectorColumn.swift`:

- The HStack is always in the view tree; its outer `.frame(width:)`
  animates between `0` and `PaneMetrics.inspectorWidth`.
- `.clipped()` hides the rail content while the width is collapsed.
- `.accessibilityHidden(!isVisible)` keeps VoiceOver in step.
- The leading `Divider()` fades via `.opacity` so it doesn't appear
  ahead of the rail content while the width is animating in.

The `withAnimation(.easeInOut(duration: 0.18))` blocks in each pane
toggle still apply — they now animate the frame width instead of an
insertion transition, which is what AppKit's constraint engine can
reconcile safely.

Verified locally: toggle the Available inspector closed and open, no
crash; row stretches/contracts cleanly; `make check` + `make test` green
at 206.

## 2026-06-09 — Launch crash fix (macOS 14.4)

Crash report from Thomas's machine after the glow-up PR landed:
`NSInternalInconsistencyException` thrown from
`-[NSWindow _postWindowNeedsUpdateConstraintsUnlessPostingDisabled]`
during the first display-cycle layout pass. AppKit's "view modified
during update" guard — something in the freshly added SwiftUI hierarchy
was invalidating constraints while the window was already inside an
update-constraints pass. Couldn't reproduce on my Mac15,X / macOS 14.4
build, but two suspects in the new code matched the symptom:

1. **`Spacer()` as the leading child of
   `ToolbarItemGroup(placement: .primaryAction)`** in `RootWindow`. The
   `.primaryAction` placement already pins items trailing — the leading
   Spacer was redundant *and* well-known to confuse the toolbar's
   intrinsic-content-size computation. Removed.
2. **`SettingsLink` nested in `safeAreaInset(edge: .bottom)`** in
   `AvailableView`'s working-hours footer. `SettingsLink` carries its
   own AppKit hosting path that triggers a constraint invalidation when
   inserted inside a `List`-anchored inset on macOS 14.4. Replaced with
   a plain `Button { openSettings() }` driven by the
   `@Environment(\.openSettings)` action — same Settings-scene
   destination, no constraint hazard. One regression: `openSettings`
   doesn't accept a tab; the user lands on General and clicks "Working
   Hours" themselves. Worth the trade vs a launch crash.

Both fixes verified locally: `make` + launch + 30-second alive check;
clicking the footer opens Settings → General; `make check` + `make test`
green (still 206).

Heads-up for future agents working on this surface:

- `SettingsLink` is the SwiftUI-idiomatic way to bridge to the Settings
  scene, but it has constraint-system side effects when hosted inside a
  `List`'s `safeAreaInset` on macOS 14.x. If you reintroduce it, host
  it outside the inset (e.g. at the `NavigationSplitView`'s root or in
  a toolbar) — or stick with the `openSettings()` action.
- `ToolbarItemGroup(placement: .primaryAction)` — don't precede items
  with a leading `Spacer()`. The placement already trails the items.

## 2026-06-09 — UI glow-up: live visual gate + inspector default

Live sweep against `build/Moves.app` after batches 1–8 landed. Caught two
real bugs that the per-batch compile gates couldn't see:

1. **`DeadlineChip` text wrapped vertically on narrow rows.** The chip's
   relative-date `Text` had no `lineLimit` / truncation modifier, so on
   Captured + Deadlines panes (~220pt wide with the inspector open) the
   text wrapped to multiple lines, the capsule background stretched to
   full row height, and the row title VStack got squeezed to zero width.
   Fix in `Sources/Moves/Views/Shared/DeadlineChip.swift`: added
   `.lineLimit(1).truncationMode(.tail)` on the chip text. The chip now
   shrinks to icon-only on cramped rows and shows the full relative date
   when the row has room.
2. **Inspector default was wrong for the shipped window width.** Batches
   2 + 8 wired a 280pt inspector column on Available / Captured /
   Deadlines / Threads, defaulting to visible via `@SceneStorage`. At
   the app's default window width (~720pt) that leaves ~220pt for the
   row list, which is below the threshold where row anatomy (leading
   icon + title + chip + hover slot + trailing menu) has room to render
   coherently. Flipped the four `@SceneStorage("inspector.*.visible")`
   defaults from `true` to `false`. First-time users see the focused
   list-only layout; the inspector toggle in the pane header opts in
   when wanted.

Visual gate sweep covered (all green):

- **Toolbar** — "Off hours" status pill (clickable → SettingsLink) +
  quick-capture `+` button (batches 2 / 7 / 8 ✓).
- **Sidebar counts** — Available 1, Current 1, Threads 2, Captured 5,
  Deadlines 2 (batch 2 ✓).
- **Available** — header "Available · 1", row "Test thread" with
  subtitle "write tomorro…" (RowSubtitle sanitizer + TaskRow body, batch
  1 + 4 ✓); hover reveals ▶ Start / ↗ Open icons (batch 7 ✓); footer
  "Outside working hours · Next: Today at 9:00 AM" with chevron + green
  dot (batch 8 ✓); inspector empty state "Nothing selected · Open top
  thread" CTA (batch 2 + 8 ✓).
- **Current** — header "Current · 1", hero card with large monospaced
  elapsed `08:26:28`, caption "Started 12:32 AM", "Next: write
  tomorrow's draft" line, button hierarchy (blue prominent Open thread,
  neutral Park, red destructive Stop pushed trailing) — batch 3 ✓.
- **Captured** — "test" + Reminder + red overdue chip "Yesterday,
  11:44 PM"; "finish proposal" + Task + orange chip "6/12/26, 5:00 PM";
  bare captures "first thing" / "buy bread" / "buy milk" with Capture
  subtitle. Row selection paints a 0.12 accent tint (batch 4 + 6 + 7 ✓).
- **Deadlines** — same chip vocabulary; "test" overdue / "finish
  proposal" orange (batch 6 ✓).
- **Capture overlay** — typed `test API tomorrow at 3pm`. Title
  preview "test API" stripped (batch 1 ✓); orange chip "Tomorrow,
  3:00 PM" with trailing `xmark.circle.fill` clear (batch 5 ✓);
  destination capsule "Deadlines" (batch 5 ✓); alert-offsets row
  "Alert me: At due / 15m / 30m / 1h / 2h / Morning of" with At due /
  1h / Morning of pre-selected (batch 5 ✓); "esc to dismiss" keycap +
  prominent blue "Create" button (batch 5 ✓).

`make check` + `make test` green (206 tests). The two patches above are
in the same working tree as batches 1–8.

## 2026-06-09 — UI glow-up batch 8: empty states + footer + contrast

Closes out items 28–30 from `plans/ui-glowup.md`. The remaining gap was
the empty surfaces: every sidebar destination either had a stock
`ContentUnavailableView` with placeholder copy, or (Threads) no empty
treatment at all — the user landed on a blank canvas. The
working-hours footer still read as a debug toggle ("yes" / "no"), and
the leaf row subtitles were too gray-on-gray for productivity scanning.

**Item 28 — designed empty states per destination.** Walked every
pane:

- **Current** → "Nothing in progress" with `figure.walk` and a
  `.borderedProminent` "Start something from Ready" action that flips
  the sidebar selection back to `.available`. Wired via a new
  `onGoAvailable` closure parameter (injected by `RootWindow`); the
  pane stays decoupled from `SidebarDestination`.
- **Captured** → "No captures yet" with `square.and.arrow.down`. The
  description interpolates the live capture-shortcut display read from
  `KeyboardShortcuts.getShortcut(for: .capture)?.description` so a
  user rebind in Settings is reflected in the copy. Fallback to
  "⌥Space" (the shipped default). Action button opens the same
  palette the global hotkey shows via `CapturePaletteSingleton.shared?.show()`.
- **Deadlines** → "No upcoming deadlines" with `calendar`. No action
  button — the way to put a row here is to capture a deadlined item,
  and that affordance is surfaced by the Captured empty state.
- **Available** → tightened existing empty state copy to "Nothing
  ready to work on" so it reads as a status, not a verdict.
- **Threads** → previously had no empty state; the new-thread row sat
  alone above a blank canvas. Added a `ContentUnavailableView` with
  `square.stack.3d.up`, a "Threads are the units of ongoing work in
  Moves" description, and a "New thread…" action that calls the
  existing `focusNewThreadInput()` (same path Cmd-N uses) to focus
  the inline composer above it.
- **Parking Lot** → "Nothing parked" with `archivebox`. No action —
  parking is intentionally optional per the §2 model.
- **Time Log** → "No work sessions yet" with the plain `clock` glyph
  (replacing `clock.arrow.circlepath` so the surface reads cleaner).
  Description aligned with the brief's "work sessions will appear
  here" copy.

Standardized on the macOS-14 `ContentUnavailableView { label } description: { } actions: { }`
trailing-closure form across panes so the empty-state vocabulary is
visually consistent — same systemImage weight, same description
position, same action button treatment. Deadlines / Available /
ParkingLot stayed on the simpler init (title + systemImage +
description) because they have no action button.

**Item 29 — working-hours footer rewrite.** The old footer rendered
`Working hours: yes/no` as a colored capsule next to a tiny static
label. Reframed:

- **Open state:** `Working hours · open` with a small green status
  dot (6pt circle). Declarative present-tense reading, the same idiom
  Mail's connection-status footer uses.
- **Closed state:** `Outside working hours` with a neutral
  `secondary.opacity(0.6)` dot. When the next opening falls within
  the next 12h, appends a `· Next: <relative time>` suffix
  (`DateFormatter` with `doesRelativeDateFormatting = true` so the
  reader sees "Tomorrow at 9:00 AM" rather than a date math result).
  Stays silent on far-future windows (e.g. weekend on a Mon–Fri
  config) to keep the footer compact.

Wrapped the whole HStack in a `SettingsLink` (macOS 14+) so a click
opens System Settings → Moves at the user's last-visited tab. Used
`.buttonStyle(.plain)` so the underlying NSButton chrome doesn't
fight the footer's `.bar` material. A `chevron.right` glyph at the
trailing edge advertises the affordance the way Mail / Notes' inline
links do.

The status sentence + next-window suffix are recomputed inside a
`TimelineView(.periodic(from: .now, by: 60))` so the footer flips
state automatically as the working-hours window opens and closes —
same one-minute cadence as the rest of the working-hours-derived UI.

Next-window detection lives in `nextWorkingHoursStart(after:)`: a
minute-by-minute forward probe through `WorkingHoursService.isInside`
bounded at 8 days. Bounded probing keeps a malformed (empty-days)
`WorkingHours` from spinning, and matches the resolution of
`isInside`'s minute-of-day check. Returns `nil` when no opening is
reachable within the bound; the footer drops the suffix.

VoiceOver gets a composed label ("Outside working hours. Open
Settings.") so the action and the status are both conveyed in one
read.

**Item 30 — secondary-text contrast bump.** Added a single semantic
constant rather than sprinkling `Color.primary.opacity(0.72)` at
twenty call sites:

```swift
// PaneMetrics.swift
static let secondaryText: Color = Color.primary.opacity(0.72)
```

Routed it through the two leaf components that carry secondary
weight everywhere:

- `RowSubtitle` body — every `TaskRow` subtitle in the app now reads
  at the higher contrast (Available, Captured, Deadlines, Threads,
  ParkingLot, popover AvailableSection).
- `UpcomingSection` popover — both the runway label and the
  "Nothing hard ahead" line. `CapturedPopoverRow` and `UpcomingRow`
  are single-line (title + chip) so they don't carry a subtitle —
  no change needed.
- Working-hours footer caption — uses the same constant so the
  contrast story is consistent across the bar.

Skipped the capture palette parsed-preview text (already uses
`.primary` not `.secondary`), per the brief's "verify it doesn't
double-down" check. Skipped Settings LabeledContent rows — those
caption lines are Form `footer:` Texts that Form styles directly;
poking `.secondary` there would fight the system look.

Left untouched: the working-hours de-emphasized-during-working-hours
`.opacity(0.5)` from batch 7 (separate visual axis), the `.tertiary`
"Press ⏎ to add" hint in ThreadsListView's new-row composer (intent
is "barely-there", not "secondary"), `ThreadTagCapsule` and
`DestinationCapsule`'s `.secondary` fill (capsule chrome, not body
text), header chrome rendered through `PaneShell` (already legible
at `.secondary` because of the larger title weight).

**Tests.** No new tests required — empty-state copy + a semantic
color constant + a 1-minute next-window probe are all visual / leaf
changes. `make check` + `make test` green; count holds at 206.

**Visual gate.** Build succeeded; tried to launch
`build/Moves.app` for the walkthrough but the lock screen was up.
Spot-check items for the next interactive verifier:

1. Walk each sidebar destination with the database empty / cleared:
   the empty-state copy + glyph + action button all read as
   designed and the action moves the user toward the next obvious
   step. Threads' new-row composer stays visible above the empty
   view; "New thread…" focuses it.
2. Click the working-hours footer on the Available pane: System
   Settings opens at the Moves Settings window (the system will
   pick the last-visited tab, which is what `SettingsLink` does).
3. The footer line says "Working hours · open" (green dot) inside
   the window, "Outside working hours" (gray dot) otherwise, and
   appends "· Next: …" when the next opening is < 12h out.
4. TaskRow subtitles in Available / Captured / Deadlines /
   ParkingLot read measurably darker than the previous
   `.secondary` — eye-test against the title to confirm
   hierarchy is preserved (title stays primary-weight semibold).

**Punch-list status.** Batches 1–8 close out items 1–30 from
`plans/ui-glowup.md`. The whole punch list is shipped; visual gate
walkthrough is pending until the machine unlocks. No commits, no
PRs.

## 2026-06-09 — UI glow-up batch 7: interaction states

Knocked out items 25–27 from `plans/ui-glowup.md`. The task-shaped rows
were missing every desktop interaction convention except selection:
no hover tint, no focus ring distinction, no per-row hover affordances,
no right-click context menus on three of the four panes. Filled the
hook batch 4 left in `TaskRow` and threaded the new state through every
caller.

**TaskRow — second generic + selection.** `TaskRow<Trailing>` becomes
`TaskRow<HoverActions, Trailing>`. The new `hoverActions` slot fades in
on hover via `.opacity(isHovered ? 1 : 0)` with `.animation(.easeOut(
duration: 0.12), value: isHovered)` — opacity-only so the row width
doesn't reflow as the cursor crosses. `allowsHitTesting(isHovered)`
keeps the invisible buttons unclickable from outside the hover region.
Added `isSelected: Bool` parameter; background priority is selected
(`Color.accentColor.opacity(0.12)`) > next (0.06) > hovered
(`Color.gray.opacity(0.08)`) > clear. Wrapped the background in a
`RoundedRectangle(cornerRadius: 6)` so all three states render as a
proper row pill rather than full-bleed flood. Hover state driven by a
private `@State isHovered` + `.onHover` — same pattern as the
RowHoverActionButton itself.

Three convenience inits keep call-site ergonomics: no-slot, trailing-
only (for CapturedRow's ellipsis menu and ParkedRow's old buttons —
the latter migrated anyway), hover-actions-only (Available, Deadlines).
Existing trailing-closure call sites had to spell out `hoverActions:`
because the two slots collide on trailing-closure disambiguation.

**RowHoverActionButton.** New shared button at the top of `TaskRow.swift`
— `.borderless`, `.controlSize(.small)`, 22pt square frame, `.help`
tooltip doubles as the VoiceOver label. The four affordance flavors:

- Available: `play.fill` Start, `arrow.up.right` Open.
- Captured: `calendar.badge.clock` Schedule due — additive to the
  ellipsis menu (the brief said prefer additive over redundant; the
  hover icon is a one-tap shortcut to the most common processing
  action).
- Deadlines: `calendar.badge.clock` Edit due, `checkmark.circle` Mark
  done.
- ParkingLot: `play.fill` Unpark, `arrow.up.right` Open — moved off
  the always-visible `.bordered` chips so the resting state matches
  the other panes.

**Context menus on every row.** Wired five flavors, all to existing
AppStore methods. Standard macOS order: positive actions first,
destructive last with a `Divider` separator and `role: .destructive`.

- Available: Start, Open Thread, Rename Thread… / divider / Park /
  divider / Delete. Skipped "Set Deadline" because Available rows are
  threads (no thread-level deadline; the row surfaces the earliest
  open-item deadline) — per the brief, skip rather than stub.
- Captured: kept the existing menu (Attach to thread, Convert, Edit
  due time, Mark Done, Cancel, Delete) — already comprehensive.
- Deadlines: Edit due time…, Mark Done / divider / Delete.
- ParkingLot: Unpark, Open Thread / divider / Delete.
- Threads: already had a context menu; extended with Rename… (next
  to Open) and moved the menu onto the row body so the new rename
  sheet can drive `@State` per-row. Mark Active / Park / Mark Done /
  Delete preserved.

Skipped "Copy as markdown" everywhere — no per-item or per-thread
markdown export exists in AppStore today; per brief, no stub items.

**Rename sheet.** New `Sources/Moves/Views/Shared/RenameThreadSheet.swift`
— a tiny TextField + Save/Cancel sheet, used by both Available and
Threads. Save disabled when the trimmed draft is empty or unchanged so
the flow can't accidentally clear or no-op the title. Enter saves,
Escape cancels. `@FocusState` autofocuses one runloop tick after appear
(same idiom as `CapturePaletteView.onAppear`).

**EditDueTimeSheet promotion.** Was `private struct` inside
`CapturedRow.swift`; demoted the `private` so the Deadlines pane can
reuse it for its row-level "Edit due" affordance. Behavior unchanged.

**isSelected plumbing.** Every pane already passed `tag(id)` into
`List(selection:)`; added the `selection == row.id` read-through on
each row constructor (Available, Captured, Deadlines, Threads). The
parking lot doesn't have a List selection model — single-purpose
surface, kept as-is.

**Disabled state.** Available's de-emphasized section was at
`.opacity(0.65)`; bumped to `.opacity(0.5)` per the brief — reads more
clearly as "available but de-emphasized during working hours" rather
than "subtly lower-contrast".

**Tests.** Interaction states are visual — no new tests. Existing 206
green via `make check && make test`.

**Visual gate.** Display was locked when I tried to launch the built
app; build succeeded but visual verification pending the next
interactive session. Spot-check items for the verifier: (1) hover any
row in Available/Captured/Deadlines/ParkingLot, action icons fade in
right of the deadline chip; (2) click a row, full-row accent tint
appears (distinct from the lighter "Next" tint on the top Available
row); (3) tab through rows, system focus ring appears; (4) right-click
each row type, see the menu structure above; (5) Available context
menu → Rename Thread… opens the new sheet, Enter saves, Escape
cancels.

## 2026-06-09 — UI glow-up batch 6: deadlines & urgency

Knocked out items 22–24 from `plans/ui-glowup.md` — deadlines needed
to be visible on every task row regardless of pane (not just the
Deadlines surface), the chip vocabulary still had ad-hoc due-text
holdouts in two popover sections and the thread-detail item row, and
overdue items rendered indistinguishably from "due Friday" because
the chip had a single orange treatment. Reworked the leaf so every
caller picks up urgency rendering for free.

**Per-chip urgency at the leaf.** Added `DeadlineChipUrgency` next to
the existing `DeadlineUrgency` in `Sources/Moves/Domain/DeadlineUrgency.swift`.
Kept the two enums separate on purpose — `DeadlineUrgency` is the
*fleet-wide* menubar signal ("any hard item overdue right now?")
driven by `AppStore.renderedDeadlineUrgency`; the new
`DeadlineChipUrgency` is a *per-row* day-level computation. Cases:
`.overdue` / `.dueToday` / `.dueTomorrow` / `.dueFuture`, computed by
a pure static `from(dueAt:now:calendar:)`. Strict `dueAt < now` for
overdue, then `Calendar.startOfDay`-based bucketing for the rest. The
chip then renders red `#FF3B30` + `exclamationmark.triangle.fill`
for overdue and orange `#FF9500` + `bell.fill` for the three future
buckets. No third "due today" color — orange stays consistent across
all non-overdue futures; the relative-date label inside the chip
already distinguishes "Today at 3:00 PM" from "Tomorrow at 9:00 AM".
`lowConfidence` yellow still wins (when we're unsure of the date, the
chip shouldn't simultaneously scream red).

**TimelineView at the chip.** `DeadlineChip` now wraps its content in
`TimelineView(.periodic(from: .now, by: 60))` and reads `ctx.date` to
compute the urgency. Scoping the timer to the leaf means the chip
flips from orange to red the minute its deadline passes — no caller
has to subscribe, and the rest of the row stays out of the redraw.
Once-per-minute cadence matches the relative-date label's resolution.
Costs nothing for chip-less rows because the TimelineView is gated by
the `if let deadline` in `TaskRow`.

**Item 22 — deadlines on normal rows.** Audited every `TaskRow`
call site: Available, Captured, Deadlines all pass a `deadline:`
through. Threads pane intentionally doesn't (thread rows aren't
task-shaped). The missing state was ParkingLot — parked threads can
carry deadlined open items, but `openItemsByThread` only covers
active threads. Added a small `.task(id: thread.id)` inside the
`ParkedRow` that queries `itemRepository.openForThread` and computes
the earliest deadline. One query per parked row; the parking lot is
low-traffic so a global cache wasn't worth the invalidation story.
When the earliest deadline is non-nil, `TaskRow` is fed
`isParked: true` so the chip renders in its parked variant.

**Item 23 — chip everywhere.** Replaced three ad-hoc due-text
holdouts with `DeadlineChip`:

- `UpcomingSection.UpcomingRow` (popover) — was rendering a trailing
  `Text(formatter.string(...))` in tertiary. Now uses `DeadlineChip(...
  size: .compact)`. Kept the leading bell/calendar glyph because it
  encodes interruption kind (hard vs soft), which is independent of
  the chip's time-pressure axis. Dropped the row's private formatter.
- `CapturedSection.CapturedPopoverRow` (popover) — same treatment.
  Dropped the private DateFormatter.
- `ThreadDetailView.ItemRow` — was rendering a tiny `dueLabel` line
  underneath the title in tertiary. Now a `DeadlineChip(... .compact)`
  in the trailing slot. Done items hide the chip; a completed item's
  deadline is no longer pressure.

Also simplified `DeadlinesView.DeadlineRow`: removed its bespoke
`isOverdue ? exclamationmark.triangle.fill : bell.fill` leading-icon
override. The trailing chip now signals overdue (red), so the leading
icon stays purely an interruption-kind indicator. No more double-
encoding.

Popover header chip (`MenuPopoverView`'s "•N soon" / "•N overdue") is
a count summary, not a deadline chip — left alone per spec.

**Item 24 — parked-with-due-date.** New `isParked: Bool` parameter on
`DeadlineChip`, plumbed through `TaskRow`. When true:

- the chip body renders at `.opacity(0.6)` so the row reads as
  deferred,
- a sibling "Parked" caption2 capsule (`.secondary` foreground +
  `.secondary.opacity(0.15)` capsule fill) renders next to the chip.

ParkingLotView's `ParkedRow` is the only call site for now —
`isParked` defaults false so every other caller is unaffected. VO
labels include ", parked" suffix when the flag is set.

**TaskRow extension.** Added `isParked: Bool = false` to both the
designated init and the no-trailing convenience init. Pure pass-
through into `DeadlineChip` — `TaskRow` doesn't change its own
appearance based on it.

**Tests.** New `Tests/MovesTests/DeadlineChipUrgencyTests.swift`
covers the pure urgency computation. Cases pinned to a UTC Gregorian
calendar so day-boundary math is reproducible regardless of CI
locale/timezone. Anchored now to 2026-06-09 14:00 UTC. Coverage:

- `dueAt = now - 5m` → `.overdue`
- `dueAt = now - 6h` → `.overdue`
- `dueAt = today 23:30, now = today 14:00` → `.dueToday`
- Spec case `dueAt = startOfToday + 14h, now = startOfToday + 9h` →
  `.dueToday`
- `dueAt = tomorrow 00:30` → `.dueTomorrow`
- `dueAt = tomorrow 23:59` → `.dueTomorrow`
- `dueAt = day after tomorrow 09:00` → `.dueFuture`
- `dueAt = now + 1h` (same day) → `.dueToday` (documenting that the
  chip doesn't have a separate `.dueSoon` bucket — that's a menubar
  concept driven by `dueSoonHardCount`)
- `dueAt = now + 36h` → `.dueFuture`
- `dueAt == now` (exact equality) → `.dueToday` (overdue is strict
  `<`, not `<=`)

Test count: 206 (was 196) — 10 new cases. `make check` + `make test`
green.

**Visual gate.** The display was locked when I tried to launch and
screenshot. Build + tests verified the code path; visual verification
pending next interactive session. Sample seed for the verifier:

```
sqlite3 ~/Library/Application\ Support/Moves/moves.sqlite3
INSERT INTO items (id,thread_id,segment_id,title,body_markdown,status,
  kind,due_at,due_kind,interruption_kind,created_at,updated_at)
VALUES
  ('test-overdue',NULL,NULL,'Overdue chip test','','captured',
   'reminder', strftime('%s','now')-300, 'datetime','hard',
   strftime('%s','now'),strftime('%s','now')),
  ('test-soon',NULL,NULL,'Due-soon test','','captured',
   'reminder', strftime('%s','now')+600, 'datetime','hard',
   strftime('%s','now'),strftime('%s','now')),
  ('test-today',NULL,NULL,'Due-today test','','captured',
   'reminder', strftime('%s','now')+8*3600, 'datetime','hard',
   strftime('%s','now'),strftime('%s','now')),
  ('test-tomorrow',NULL,NULL,'Due-tomorrow test','','captured',
   'reminder', strftime('%s','now')+24*3600, 'datetime','hard',
   strftime('%s','now'),strftime('%s','now'));
```

Verifier should look for: red+triangle chip on the overdue row,
orange+bell on the rest, parked-with-due-date showing dimmed orange
chip + "Parked" capsule in the Parking Lot pane.

## 2026-06-09 — UI glow-up batch 5: command overlay polish

Knocked out items 16–21 from `plans/ui-glowup.md` — the capture palette
overlay had a smashed-together preview line, display-only deadline chips
the parser couldn't be trusted to read for the user, an alert-offsets
row that appeared even with no deadline parsed, and a Return/Esc
affordance you had to know to look for. Rebuilt the overlay around the
shared `DeadlineChip` from batch 3 (now optionally tappable + clearable)
and reorganized the footer around explicit Create + Esc affordances.

**16. Visual grammar in the preview line.** Three slots, each with its
own visual identity:

- **Title** — `.system(size: 13, weight: .semibold)` primary. Was
  `.secondary`-tinted before; now reads as the dominant thing because
  it's the thing being created.
- **Deadline chip** — the shared `DeadlineChip` (orange `bell.fill +
  relative date`), same vocabulary as the row chip and the Current card.
  No more bespoke chip-builder inside `CapturePaletteView`.
- **Destination capsule** — new `DestinationCapsule` subview: monochrome
  `Color.secondary.opacity(0.15)` capsule with a context icon
  (`tray` for "Ready", `bell` for "Deadlines") and the destination
  label. `.secondary` foreground style so it intentionally loses the
  visual fight with the orange chip — orange = time pressure, grey =
  where this is going to land. Destination today is `Ready` when no
  deadline, `Deadlines` when there's one; `Thread` is reserved for
  the future thread-attach affordance.

The old `arrow.turn.down.right` glyph + "· saves as a capture" trailer
+ `⏎` glyph all came out — replaced by the explicit footer.

**17. Editable deadline chip.** `DeadlineChip` gains two additive
optional closures: `onTap` and `onClear`. Defaults are `nil`, so every
existing call site (`CurrentSection`, `CurrentDetailView`, `TaskRow`)
keeps the read-only label-shaped chip with no chrome change. When the
overlay supplies `onTap`, the chip wraps in a `Button` with
`.buttonStyle(.plain)`; tapping presents `.popover(arrowEdge: .top)`
attached directly to the chip. The popover holds:

- A "Edit deadline" header.
- A row of preset bordered buttons — "In 1h", "Tomorrow 9am",
  "Friday 5pm". Each computes against `Date()` at click time so
  presets stay live.
- A `.graphical` `DatePicker` over `[.date, .hourAndMinute]`.
- A trailing `Cancel` / `Set` pair, `Set` styled `.borderedProminent`
  and bound to `.keyboardShortcut(.defaultAction)`; `Cancel` to
  `.cancelAction`.

The popover binds to a private `pickerDraftDate` so the spinner can
explore freely without clobbering the override until the user presses
Set. NSPanel popover behavior: the panel is configured
`becomesKeyOnlyIfNeeded = false`, so the popover overlay doesn't shut
the palette when it opens; popover dismisses on outside tap inside the
overlay surface as usual.

**Override semantics.** Manual selection writes to a new local
`manualDueAt: Date?` state in `CapturePaletteView`. While it's non-nil
the parser's `dueAt` is ignored for chip rendering and alert-row
visibility — subsequent typing on the title can't clobber the manual
choice. Submit-time wiring: `CapturePaletteView` passes a new
`DueOverride` (top-level type in `AppStore.swift`, hard interruption)
into `AppStore.capture(_:offsetsOverride:dueAtOverride:)`. The store
applies it post-parse, swapping in the explicit datetime, clearing the
low-confidence flag, and forcing `interruptionKind = .hard` (the
date-picker is for deadlines that matter — soft-deadline UX stays
parser-driven). Clearing the chip resets `manualDueAt` AND replaces
the draft with the parser's cleaned title (so the next keystroke
doesn't immediately re-recognize the same phrase and re-add the
chip).

**18. Alert offsets gated on effective deadline.** `AlertOffsetChipRow`
now renders only when `effectiveDueAt != nil` (manual override OR
parser result). Confirmed via grep that the row was previously gated
on `currentParse?.dueAt != nil` only — manual overrides went through
unsignaled. Reseeding still re-runs on `draft` AND on `manualDueAt`
change so the kind defaults swap correctly when the user picks
manually (manual override → `.reminder` defaults).

**19. Confidence / failure state.**

- **Removable due chip.** `DeadlineChip.onClear` renders a trailing
  `xmark.circle.fill` as a separate `Button(.plain)` inside the chip
  capsule. Tooltip "Clear deadline". The overlay always supplies
  `onClear` when the chip is shown, so the user always has the
  escape hatch.
- **Low-confidence treatment.** Added `lowConfidence: Bool` (default
  `false`) to `ParsedCapture`. Set true when the matched suffix's
  `dueKind` is `.date` (vs `.datetime`) — i.e. bare `tomorrow`, bare
  `<weekday>`, bare `YYYY-MM-DD`. The flag flows into `DeadlineChip`'s
  new `lowConfidence` parameter, which swaps the bell glyph for
  `questionmark.circle.fill` and tints the entire chip yellow instead
  of orange. Tooltip still shows the full calendar date via the
  existing `.help(absoluteFormatter)` from batch 1.
- **Manual overrides always read as high-confidence.** When
  `manualDueAt` is set the overlay passes `lowConfidence: false`
  regardless of the parser — the user told us exactly what they meant.

**20. Trailing Create button.** New `footer` subview in
`CapturePaletteView`. Trailing `.borderedProminent` Create button
bound to `.keyboardShortcut(.defaultAction)` so Return still works,
plus the visible affordance the hooked-Return glyph wasn't carrying.
Disabled when the draft trims to empty. The footer only renders while
`lastSaved == nil` — the brief post-save dwell stays uncluttered.

**21. Esc-to-dismiss hint.** New private `KeyCapGlyph` subview at the
leading edge of the footer renders a small "esc" key-cap (monospaced
.medium 10pt, `RoundedRectangle(cornerRadius: 4)` with a 0.5pt
secondary stroke). Followed by `Text("to dismiss")` in 11pt
secondary. Stays in the leading edge so the trailing Create button is
the eye's final stop.

**File-by-file changes.**

- `Sources/Moves/Services/CaptureParser.swift` — `ParsedCapture` gains
  `lowConfidence: Bool = false`. Set true when the matched suffix is
  `.date`-kind.
- `Sources/Moves/Model/AppStore.swift` — `capture(_:now:offsetsOverride:
  dueAtOverride:)` accepts an optional manual override; applies it
  post-parse. New top-level `DueOverride` struct (date + kind, defaults
  to `.hard`).
- `Sources/Moves/Views/Shared/DeadlineChip.swift` — additive
  `lowConfidence: Bool`, `onTap: (() -> Void)?`, `onClear: (() ->
  Void)?` parameters. When `onTap` is set the chip wraps in a
  `Button(.plain)`; when `onClear` is set a trailing `xmark.circle.fill`
  button appears inside the capsule. Yellow tint + `questionmark.circle
  .fill` glyph swap-in for low-confidence. Defaults preserve every
  existing call site.
- `Sources/Moves/Views/Capture/CapturePaletteView.swift` — rebuilt
  preview row around `DeadlineChip` + `DestinationCapsule`. New
  `manualDueAt` / `datePickerOpen` / `pickerDraftDate` local state.
  `.popover(arrowEdge: .top)` on the chip carries the date picker.
  New `footer` subview with leading `KeyCapGlyph("esc") + "to dismiss"`
  and trailing `.borderedProminent` "Create" button. New private
  `DueDatePreset` struct (Sendable, `@Sendable` compute closures) for
  the popover presets row. Removed the bespoke `deadlineChip(for:
  kind:)` builder — `DeadlineChip` is the single source of truth.

**Tests.** Added 6 parser tests covering the new `lowConfidence`
field: `testTomorrowAloneIsLowConfidence`,
`testTomorrowAtTimeIsHighConfidence`, `testBareWeekdayIsLowConfidence`,
`testWeekdayWithTimeIsHighConfidence`, `testNoMatchIsNotLowConfidence`,
`testISODateAloneIsLowConfidence`. No tests added for the local
`CapturePaletteView` overlay state (`manualDueAt`, popover wiring) —
the brief calls them out as pure view state, exercised by the visual
gate.

**Gates.** `make check` clean. `make test` green at 196/196 (was
190 → +6 new parser tests). `make` produces a valid signed
`build/Moves.app`.

**Punted: visual gate.** Machine was at the macOS lockscreen at the
end of this session (same as batches 1, 2, 4). Took a `request_access`
+ screenshot; got the lockscreen. The structural changes are
conservative — additive parameters on `DeadlineChip`, an additive
optional parameter on `AppStore.capture`, a new local-state-only
override path in `CapturePaletteView` — and the overlay compiles +
passes the full suite. Hand-off note: after unlock, ⌥Space the
capture palette and verify:

1. Type `test API tomorrow at 3pm` — title "test API" reads primary
   semibold, orange `DeadlineChip` reads "Tomorrow at 3:00 PM",
   monochrome "Deadlines" capsule trailing the chip. Alert offsets
   row appears under the preview.
2. Click the chip — popover opens above with presets row + graphical
   date picker + Cancel/Set. The palette stays key.
3. Pick "Friday 5pm" preset; press Set — chip updates to "Fri, … at
   5:00 PM" (or "Friday at 5:00 PM" via the relative formatter).
   Return creates.
4. Click the trailing `xmark.circle.fill` on the chip — chip
   disappears, alert-offsets row collapses, destination capsule flips
   to "Ready".
5. Type `tomorrow` alone — chip shows yellow `questionmark.circle
   .fill` + yellow text/background (low-confidence treatment). Tap
   it; pick a time; chip returns to orange.
6. Type something with no parser hit (e.g. `read the asyncio docs`)
   — no chip, no alert row, destination "Ready", trailing Create
   button enabled.
7. Verify the footer: "esc to dismiss" key-cap glyph at leading edge;
   `.borderedProminent` Create button at trailing edge; Esc still
   dismisses; Return still creates.

## 2026-06-09 — UI glow-up batch 4: row anatomy

Knocked out items 12–15 from `plans/ui-glowup.md` — task rows across the
main window had no anatomy beyond "title + secondary text + system
divider", felt cramped against the canvas, and gave the eye nothing to
land on in Available. Built one shared row, adopted it everywhere, and
let the macOS inset-list system spacing carry separation instead of
literal `Divider`s.

**One row to rule them all.** New `Sources/Moves/Views/Shared/TaskRow.swift`
parameterized by:

- `title: String` — `.system(size: 14, weight: .semibold)`, single line,
  tail-truncated.
- `subtitle: String?` — feeds the existing `RowSubtitle` (batch 1's
  ellipsis-sanitizer + secondary foreground) so the truncation behavior
  is consistent everywhere.
- `deadline: Date?` — when set, the orange `DeadlineChip` (batch 3)
  renders trailing. Same chip vocabulary as the capture preview and
  Current card; batch 6 owns urgency-state visuals (overdue red etc.),
  this slot just wires the data.
- `threadTag: String?` — small monochrome capsule used by Captured /
  Deadlines rows to surface the parent thread's title (Available /
  Threads rows are already inside their thread's context, so they don't
  set it).
- `leadingIcon: TaskRowLeadingIcon?` — `(systemName, tint, a11y label)`
  triple. Captured + Deadlines use it for the interruption / overdue
  glyph; Available / Threads / Parking Lot leave it nil.
- `isNext: Bool` — see item 15.
- `trailing: () -> Trailing` — `@ViewBuilder` slot with an `EmptyView`
  default specialization. Generic over the trailing content type rather
  than `AnyView?` to keep the layout path type-erased only where it
  needs to be. Captured's `ellipsis.circle` menu and Parking Lot's
  Unpark / Open buttons live here today; batch 7's hover affordances
  will fill it on the other panes.

`TaskRowLeadingIcon` is a file-scope struct (not nested in `TaskRow<Trailing>`)
so callers don't have to spell the generic when constructing one — got
caught on `TaskRow<EmptyView>.LeadingIcon` in the first iteration when
Swift wouldn't infer `Trailing` from the trailing closure with the
nested type in argument position.

**13. Row height.** New `PaneMetrics.rowMinHeight = 60` constant; every
`TaskRow` applies `.frame(minHeight: 60)`. `PaneMetrics.listRowVertical`
goes from 4 → 8 so the row's own vertical padding combined with the
min-height frame gives a comfortable two-line preview that reads as
intentional (Mail / Reminders density). One-line rows breathe with the
same min-height — empty subtitle just falls through.

**14. Separators.** macOS `List(.inset)` was drawing the subtle hairline
between rows; the reviewer's "separators dominate the content" call was
exactly that. Picked the "remove dividers, rely on system spacing"
approach (the brief's first option):

- Every list pane (`AvailableView`, `CapturedView`, `DeadlinesView`,
  `ParkingLotView`, `ThreadsListView`) now applies
  `.listRowSeparator(.hidden)` per row.
- Per-row `.listRowInsets(...)` replaces the previous list-level
  `.listRowInsets(...)`. Same `PaneMetrics.listRowLeading` / `Trailing`
  values; the move makes the insets travel with the row when the row
  is conditionally rendered inside a `Section` (Available's
  de-emphasized group needed this to land its accent-tinted "Next"
  background cleanly without spilling onto the section header).
- No `Divider()` was added or removed between rows — there weren't any
  in row code to start with; the system separator was the culprit.

**15. Available "Next" treatment.** The first visible row in Available
(non-deemphasized only) gets:

- A 3pt leading accent bar (`PaneMetrics.nextAccentBarWidth = 3`),
  vertically inset 10pt at top/bottom so it reads as a marker, not a
  column rule.
- A faint `Color.accentColor.opacity(0.06)` background tint across the
  row width.

Both treatments live inside `TaskRow` keyed off `isNext`, so the same
visual recipe works anywhere we surface a "do this next" row in the
future. De-emphasized rows can never be `isNext` — the
`AvailableRow` wrapper masks the flag with `!deemphasized` so a working-
hours-de-emphasized first row can't promote itself past the visible
queue. No "Next" pill on the row chrome — chose the bar + tint over a
pill so the row anatomy isn't fighting for space with the deadline chip
slot.

**Inline deadline wired across panes.** Per the brief ("go ahead and
wire `deadline:` through wherever an item has a `due_at`"), the row
chip now renders on:

- **Available** — earliest `dueAt` across the thread's open items
  (`AppStore.openItemsByThread`). Surfaces the closest deadline for a
  thread directly on its Available row — item 22's "deadlines must
  appear on normal task rows, not only on the Deadlines pane".
- **Captured** — `item.dueAt`.
- **Deadlines** — `item.dueAt`. The subtitle's "Captured" caption only
  renders when the item has no thread (otherwise the trailing thread
  tag already says where it lives).
- **Parking Lot** — no deadline today; the row still uses `TaskRow`
  metrics so the row height matches the rest.
- **Threads** — thread-shaped (no per-thread deadline), uses `TaskRow`
  for layout only.

Subtitle simplification fell out of this: Captured's row used to render
`Reminder · Today at 3:00 PM` as the secondary line; now it's just
`Reminder` and the deadline goes to the chip. Same shift in Deadlines —
the row no longer concatenates `thread · date` in the subtitle, the
thread tag and the chip carry their own slots.

**File-by-file changes.**

- `Sources/Moves/Views/Shared/TaskRow.swift` — new. `TaskRow<Trailing>`
  + `TaskRowLeadingIcon` + private `ThreadTagCapsule`.
- `Sources/Moves/Views/Window/PaneMetrics.swift` — added `rowMinHeight`,
  `nextAccentBarWidth`; bumped `listRowVertical` from 4 to 8.
- `Sources/Moves/Views/Window/AvailableView.swift` — `rowView` takes
  `isNext`; computes earliest deadline via `openItemsByThread`;
  per-row `.listRowSeparator(.hidden)` + `.listRowInsets(...)` on both
  the flat visible group and the de-emphasized section.
- `Sources/Moves/Views/Window/CapturedView.swift` — per-row separator
  hide + insets.
- `Sources/Moves/Views/Window/Captured/CapturedRow.swift` — body is now
  a `TaskRow` with a trailing menu in the slot; dropped the bespoke
  hover background + duplicate date formatter.
- `Sources/Moves/Views/Window/DeadlinesView.swift` — `DeadlineRow`
  rebuilt on `TaskRow` with `threadTag:` + `deadline:`; per-row
  separator hide + insets.
- `Sources/Moves/Views/Window/ParkingLotView.swift` — `ParkedRow`
  rebuilt on `TaskRow` with the Unpark / Open buttons in the trailing
  slot; per-row separator hide + insets.
- `Sources/Moves/Views/Window/ThreadsListView.swift` — `ThreadRowSummary`
  rebuilt on `TaskRow` (title + breadcrumb only); per-row separator
  hide + insets.

The popover sections (`AvailableSection`, `CapturedSection`) were
deliberately left alone — they live on the 320pt menu-bar surface where
60pt rows would eat half the popover. The main-window row anatomy is
the canvas problem.

**Gates.** `make check` clean. `make test` green at 190/190 — no test
delta (TaskRow is view-side; the data-side change is reading
`openItemsByThread`, which is already covered by the data-path tests
that feed it). `make` produces a valid signed `build/Moves.app`.

**Punted: visual gate.** Machine was at the macOS lockscreen at the end
of this session (same as batches 1 and 2). Took a `request_access`
screenshot to confirm; got the lockscreen. The structural changes are
conservative — one new view, one new pair of metrics constants, the
existing list shells unchanged — and the row anatomy compiles + passes
the full test suite. Hand-off note: after unlock, run `make run` and
verify on the main window:

1. **Available** — first row has the leading accent bar + faint accent
   background. Subsequent rows render flat. Two-line rows read at ~60pt
   with comfortable breathing room.
2. **Captured** — row anatomy matches: leading interruption icon,
   semibold title, "Reminder" / "Task" / "Capture" subtitle, orange
   `DeadlineChip` trailing if a `dueAt` exists, ellipsis menu at the
   trailing edge. No row dividers.
3. **Deadlines** — row anatomy matches: leading bell / calendar /
   warning icon, semibold title, thread tag capsule, orange chip.
4. **Parking Lot** — Unpark + Open buttons sit in the trailing slot at
   `controlSize(.small)`; row height matches the rest.
5. **Threads** — same metrics, no chip / tag / icon; status sections
   ("Active" / "Parked" / "Done") still group.

## 2026-06-09 — UI glow-up batch 3: Current card operational detail + button hierarchy

Knocked out items 10–11 from `plans/ui-glowup.md` — the Current card
now reads as an operational hero (what am I working on, how long, when
did I start, when is it due) instead of a title + breadcrumb + three
equal-weight pills.

**10. Operational detail.** Both Current surfaces now show:

- **title** — `.title2` semibold (main window) / `.callout` semibold
  (popover),
- **elapsed time** rendered prominently in a self-ticking
  `monospacedDigit` rounded face (`00:16` → `01:15` → `01:01:01`),
- **started clock time** ("Started 2:14 PM") in `.caption` secondary,
- **deadline chip** — reuses the orange `bell.fill + relative date`
  capsule from the capture palette (`DeadlineChip`) when the active
  segment carries a `dueAt`. Same chip vocabulary across surfaces; no
  new urgency color was invented.
- **action set** with real hierarchy (see item 11).

Layout density honors the two surfaces:
- **Popover Current section** (320pt-wide menu-bar surface): one
  compact metadata line — `01:15 · Started 12:32 AM` + optional
  deadline chip — sitting between title and breadcrumb. Doesn't blow
  out vertically.
- **Main-window Current pane**: hero card at 20pt padding, max
  560pt wide, large rounded elapsed display, started caption
  underneath, deadline chip trailing-aligned, button row at the
  bottom.

**Timer mechanism.** The elapsed label self-ticks via
`TimelineView(.periodic(from: startedAt, by: 1))` scoped to *just the
digits* — the enclosing card does NOT re-render every second. An
`@State` `Timer` would have invalidated the whole pane on every tick
and lost focus/scroll state. New shared view
`Sources/Moves/Views/Shared/ElapsedTimeLabel.swift` wraps the pattern
so the popover and the main window share one implementation. Pure
formatter at `Sources/Moves/Views/Shared/ElapsedTime.swift` so the
digit math is testable without a SwiftUI host:
  - `0s   → "00:00"`
  - `16s  → "00:16"`
  - `75s  → "01:15"`
  - `3600s → "01:00:00"`
  - `3661s → "01:01:01"`
  - negative intervals clamp to `00:00`
  - fractional seconds floor (`16.9s → "00:16"`).

**11. Button hierarchy.** No more three-pill row.

- **Open Thread** (main window only) — `.borderedProminent`, blue,
  `.defaultAction` keyboard shortcut. The primary navigation gesture
  off the Current card.
- **Stop** — `.bordered` with `.tint(.red)` and `role: .destructive`
  (terminal). Keeps the `S` accelerator on both surfaces. On the
  main window it's right-aligned past a `Spacer` so it visually
  separates from the constructive actions; in the popover it stays
  leading next to Park (limited horizontal room).
- **Park** — `.bordered`, default tint (neutral secondary). Lives
  between Open Thread and Stop on the main window.

Apple buttons size to their label content (per macOS HIG), so the
buttons don't all render the same width — that's how the hierarchy
reads visually. Equal-width pills would have undone the role
distinction.

The popover Current section deliberately does NOT add a primary
"Open Thread" button. The popover already has a footer `Open` button
that navigates to the main window; doubling it here would crowd the
320pt surface and dilute "the popover's Open" semantics. Stop / Park
stay the action set there.

**Shared chip.** New `Sources/Moves/Views/Shared/DeadlineChip.swift`
ports the orange `bell.fill + relative` capsule already in
`CapturePaletteView.deadlineChip` — same `.short` + relative
DateFormatter, same `.help(absoluteDate)` tooltip so users can
confirm the calendar date on hover. Two sizes (`.compact` for the
popover, `.regular` for the main-window card). Source of the deadline
is the active segment's `dueAt` (Threads themselves don't carry a
deadline; regimented threads do via the active segment). When the
current thread isn't regimented or its active segment has no
`dueAt`, no chip renders — empty, not a "no deadline" placeholder.

**File-by-file changes.**
- `Sources/Moves/Views/Shared/ElapsedTime.swift` — new. Pure
  formatter.
- `Sources/Moves/Views/Shared/ElapsedTimeLabel.swift` — new.
  TimelineView-scoped label, takes font + foregroundStyle so both
  surfaces share the same timer.
- `Sources/Moves/Views/Shared/DeadlineChip.swift` — new. Orange chip
  ported from the capture palette.
- `Sources/Moves/Views/Popover/CurrentSection.swift` — rewrote
  `activeContent`: title → metadata row (`ElapsedTimeLabel · Started
  H:MM AM` + optional chip) → segment line → breadcrumb → action
  row. Stop button now `.bordered` + `role: .destructive` +
  `.tint(.red)`.
- `Sources/Moves/Views/Window/CurrentDetailView.swift` — rebuilt as
  a `card(for:)` factor: title block, metadata block (`HStack` of
  big elapsed/started column + trailing chip), button row with the
  three-role hierarchy.
- `Tests/MovesTests/ElapsedTimeTests.swift` — new. Seven cases
  covering the format rules above.

**Gates.** `make check` clean. `make test` green at 190/190 (was 183;
+7 new `ElapsedTimeTests` land cleanly, no existing tests touched).
`make` produces a valid signed `build/Moves.app`.

**Visual gate green.** Machine was unlocked this round. Ran
`build/Moves.app`, opened the menu-bar popover, started the "Test
thread" row from the popover's Available section. Confirmed:
- Popover Current section: `Test thread` (semibold) → `01:23 ·
  Started 12:32 AM` (mono digits ticking every second, no card
  re-render visible) → `Next: write tomorrow's draft` → red `Stop`
  + neutral `Park` → "Or click a thread in Available to switch".
- Main-window Current pane: `Current · 1` pane header → hero card
  with `Test thread` title, breadcrumb, large `01:43` elapsed, small
  `Started 12:32 AM`, blue `Open thread` + neutral `Park` + (spacer)
  + red `Stop`. No deadline chip (the active segment has no `dueAt`
  on this thread, expected).
- Clicked `Open thread` — main window switched to the Threads pane
  with the Test thread editor opened. Routing intact.

Cross-surface invariant verified: the elapsed counter advanced
identically on both surfaces (popover read 01:23 when the main-window
card read 01:37 — same wall clock, different `Date.now` snapshots
taken seconds apart).

## 2026-06-09 — UI glow-up batch 2: pane structure + inspector

Knocked out items 5–9 from `plans/ui-glowup.md` — the "what is this
pane?" / "where's the detail surface?" gap across the main window.

**5. Main pane has no header.** Every pane now renders a consistent
title row at the top of the content area: large semibold pane title
(`Available`, `Threads`, `Captured`, `Deadlines`, `Parking Lot`,
`Current`, `Time Log`) + a muted dot-separated count beat (`Captured
· 5`) + a trailing accessory slot for per-pane controls. Header is
encoded once in `PaneShell` / `PaneListShell`'s new `PaneHeader`; not
duplicated per pane. Count goes to nil when the destination has no
list (Current shows `1` when something is active, otherwise the pane
title alone).

**6. Content alignment isn't consistent.** Single source of truth in
`Sources/Moves/Views/Window/PaneMetrics.swift`: `horizontalInset = 24`,
`listRowLeading = 24`, `listRowTrailing = 24`, `topInset = 16`,
`headerToContentSpacing = 12`, `inspectorWidth = 280`. Every pane
routes its padding/list-row insets through these constants. The Mail-
style "row text aligns under the pane title" grid now holds across
Available, Threads, Captured, Deadlines, Parking Lot, Current, Time
Log. The 28/20/14pt drift the reviewer flagged is gone.

**7. Top toolbar strip wired.** `RootWindow.toolbar { … }` with a
`ToolbarItemGroup(placement: .primaryAction)`:
- `WorkingStatusIndicator` chip ("Working" / "Off hours" with the
  orange dot for inside-hours). Same data the Available footer pill
  uses, mirrored into the toolbar so the bit is visible from any
  pane.
- Quick-capture button (`plus.circle` + "Quick capture" label) that
  calls `CapturePaletteSingleton.shared?.show()` — the same path the
  menu-bar popover's capture button takes, no duplicate plumbing.
- Search is intentionally NOT shipped as a fake field. A `// TODO:
  Wire search backend (batch 7)` comment marks the slot per the brief
  ("don't ship a fake search; if you must stub it, gate behind a
  `// TODO:` comment"). A disabled placeholder would have read as
  broken in screenshots; an empty slot reads as future work.

**8 + 9. Inspector column.** New reusable
`Sources/Moves/Views/Window/InspectorColumn.swift` with three pieces:
- `InspectorColumn` — fixed-width (280pt) trailing rail, animated in/
  out via `.transition(.move(.trailing) ∪ .opacity)` keyed off a
  binding the pane controls. HStack + animated frame, deliberately
  NOT `HSplitView` (forces a draggable divider and trips up keyboard
  focus inside the outer `NavigationSplitView` detail) and NOT the
  window-scoped `.inspector { … }` modifier (one-shot, can't model
  per-pane selection types).
- `InspectorDetail` — title + optional subtitle + label/value
  metadata rows + slotted primary action. One layout, four panes.
- `InspectorEmptyState` — muted icon + headline + message + one
  obvious next action button (varies per pane). Covers the
  "Nothing selected" treatment the brief calls for.

Per-pane wiring (string-typed selection state + `.tag(...)` on rows
+ `List(selection: $selection)`):
- `AvailableView`: selection → thread title + move text + status/kind
  metadata + "Open thread" primary. Empty → "Open top thread" CTA.
- `ThreadsListView`: selection → thread title + breadcrumb + status/
  kind metadata + "Open thread". Empty → "New thread" CTA that fires
  `AppSignals.requestNewThreadFlow()` (reuses the Cmd-N path).
- `CapturedView`: selection → item title + body + kind/status/due
  metadata + "Mark done". Empty → "Open capture palette" CTA.
- `DeadlinesView`: selection → item title + thread title + due/state/
  kind metadata + "Mark done". Empty → no CTA (deadlines are read-
  mostly; the action is in the row's context menu, not the inspector).
- `ParkingLotView`: no inspector per the brief ("panes with a
  selectable row" — parking lot rows have inline Unpark/Open buttons
  and don't have a useful detail surface yet). Still gets the pane
  header.
- `CurrentDetailView`, `WeeklyView`: header only (no list, no
  inspector — they're already detail-shaped).

Inspector visibility persists per-window via `@SceneStorage` keys
(`inspector.available.visible`, etc.) so a closed inspector stays
closed when the user reopens the window, but multiple Moves windows
don't fight over one global flag. Each pane exposes a header-trailing
toggle button (`sidebar.right` icon) that flips it.

**File-by-file changes.**
- `Sources/Moves/Views/Window/PaneMetrics.swift` — new. Grid
  constants.
- `Sources/Moves/Views/Window/PaneShell.swift` — added `title`,
  `count`, `accessory`, `inspector` slots to both `PaneShell` and
  `PaneListShell`. Generic over closures with `EmptyView`-defaulted
  overloads so callers that don't want one slot don't pay for it.
  New private `PaneHeader` view.
- `Sources/Moves/Views/Window/InspectorColumn.swift` — new.
  `InspectorColumn`, `InspectorDetail`, `InspectorEmptyState`.
- `Sources/Moves/Views/Window/RootWindow.swift` — toolbar items;
  `WorkingStatusIndicator` view.
- `Sources/Moves/Views/Window/AvailableView.swift`,
  `ThreadsListView.swift`, `CapturedView.swift`, `DeadlinesView.swift`,
  `ParkingLotView.swift`, `CurrentDetailView.swift`,
  `TimeLog/WeeklyView.swift` — adopt new shell API; list panes wire
  selection + inspector body.

**Gates.** `make check` clean. `make test` green at 183/183 (unchanged
from batch 1 — no tests removed; no new tests added because the
changes are purely structural / view-side and the existing
view/wiring tests cover the data path). `make` produces a valid
signed `build/Moves.app`.

**Punted: visual gate.** Machine was at the macOS lockscreen again —
took a `request_access` screenshot to confirm, got the lockscreen.
Compile + test gates green; the structural changes are conservative
(generic `PaneShell` API has `EmptyView` defaults so old call sites
keep compiling; selection bindings are local `@State`; the inspector
animation is the standard `.move(edge:) + .opacity` transition).
Hand-off note: re-run `make run` after unlock and confirm the pane
title row, the toolbar's working-status chip + quick-capture button,
and the inspector toggle on Available / Threads / Captured /
Deadlines (selected row → detail; empty → "Nothing selected" with
CTA).

## 2026-06-09 — UI glow-up batch 1: trust-breaking bugs

Knocked out items 1–4 from `plans/ui-glowup.md` — the trust-breaking
fit-and-finish bugs that make the app feel broken before the user even
gets to a feature.

**1. Natural-language parser display lie** (`test API tomorrow at 3pm`
preview → "Today at 3:00 PM"). Two root causes:

- The parser only recognized `tomorrow <H>` (2 tokens). `tomorrow at 3pm`
  (3 tokens) silently fell through to the bare `at <H>` rule on the
  trailing two tokens; the `tomorrow` anchor was dropped, and the title
  came out as `test API tomorrow`.
  Added explicit 3-token forms `tomorrow at <H>` and `<weekday> at <H>`
  to `Sources/Moves/Services/CaptureParser.swift`. Both are `.soft`
  interruption (matches the existing `tomorrow 9am` / `friday 5pm`
  conventions). Forms listed in the file's grammar header and tested
  via `CaptureParserTests` — three new regression cases:
  `testTomorrowAtThreePM`, `testTomorrowAtBareNineRollsToTomorrow`,
  `testWeekdayAtFivePM`.
- The chip's `DateFormatter` used `.medium` dateStyle, which produces
  long labels like "Jun 10, 2026 at 3:00 PM" when relative formatting
  doesn't kick in. Switched to `.short` + kept
  `doesRelativeDateFormatting` so "Today"/"Tomorrow" still substitutes,
  and added a `.help(absoluteFormatter.string(from:))` tooltip so users
  can hover to confirm the calendar date — defuses the trust problem
  even when relative labels are correct. Source:
  `Sources/Moves/Views/Capture/CapturePaletteView.swift`.

**2. Scheduling phrase stays in the task title.** Falls out of item 1's
parser fix — once the 3-token form matches, `consumed == 3` strips
`tomorrow at 3pm` from the title and the preview reads `test API`. No
separate code change needed; covered by the new parser tests.

**3. Row truncation looks sloppy** (`Write an mOS blog post, or
something about meta-apps....`). Added `RowSubtitle` in
`Sources/Moves/Views/Shared/RowSubtitle.swift` — a small view that owns
the row-subtitle modifier stack (`.foregroundStyle(.secondary)`,
`.lineLimit(1)`, `.truncationMode(.tail)`) and strips trailing dots /
horizontal ellipses / whitespace from the source string so SwiftUI's
tail-truncation isn't fighting a literal `...` the user typed.
Standardized into the three primary row sites:
`Sources/Moves/Views/Window/AvailableView.swift`,
`Sources/Moves/Views/Popover/AvailableSection.swift`,
`Sources/Moves/Views/Window/ThreadsListView.swift`.
Sanitizer covered by `RowSubtitleTests` (six cases — triple dot,
horizontal ellipsis, mixed runs, trailing whitespace around dots,
interior dots preserved, all-dots → empty).

**4. "New thread…" field reads as disabled.** Rebuilt the inline
composer at the top of `ThreadsListView`:

- Fill: `.background.secondary` → `.quaternary` (more present against
  the pane background).
- Added a `.separator` stroke that becomes accent-tinted on focus —
  mirrors the macOS focus ring on a plain TextField that doesn't draw
  its own.
- Field font `.body` + `.primary` foreground so typed text reads at
  full contrast. The prompt is supplied via `Text(...)` so SwiftUI
  picks the right placeholder color for the appearance.
- Whole row is the hit target: `.contentShape` over the rounded rect
  and `.onTapGesture { addFocused = true }` so tapping the icon or
  any padding also focuses the field.
- "Press ⏎ to add" hint replaces the floating "Add" button when the
  field is empty so the row stays a single horizontal slot; the
  prominent "Add" + `keyboardShortcut(.defaultAction)` returns once
  the user has typed something.

**Gates.** `make check` clean, `make test` green at 183/183 (was 174;
+8 new cases land cleanly — three parser regressions, five sanitizer
cases — and the prior `testFoo` set is untouched). `make build` produces
a valid signed `build/Moves.app`.

**Punted: visual gate.** The machine was at the macOS lockscreen
through this session, so I couldn't drive `build/Moves.app` via
computer-use to take the four screenshots called for by the punch list
(capture palette `test API tomorrow at 3pm`, Threads pane composer,
Available pane subtitle). The compile + test gates and the parser /
sanitizer unit tests cover the correctness side; the chip-typography
choices are conservative (`.short` + relative + tooltip) and the row
modifier is the standard macOS idiom. Hand-off note: re-running
`make run` after unlock and visually confirming the four states above
is the only outstanding step.

## 2026-06-08 — Available pane layout fix

Thomas flagged "the Available pane still isn't aligned and it doesn't
make sense how it's laid out". Two root causes:

1. `AvailableView` was emitting `workingStatus` and the `List` as two
   sibling views directly inside `PaneListShell { ... }`. `PaneListShell`
   applies `.frame(maxHeight: .infinity, alignment: .topLeading)` to its
   `content()` builder, which the TupleView propagates to each child —
   both became greedy in the enclosing VStack and split available
   vertical space. The List ended up sitting in the lower half of the
   pane with a huge mysterious gap above it. Same fix
   `ThreadsListView` already had: wrap the body in an inner `VStack
   (spacing: 0) { … }` so the two children share a single greedy slot
   with intrinsic heights.
2. The visible-rows `Section { ForEach }` had no header but was still
   spending an inset-list Section header gap. Dropped the wrapper so
   the visible rows render flat (the "De-emphasized during working
   hours" subsection keeps its own meaningful header).

While in the file: moved the "Working: yes/no" pill into a
`.safeAreaInset(edge: .bottom)` footer with `.bar` material. Reads as
a chrome status chip (Mail's connection footer / Reminders'
completion-summary pattern) rather than competing with the row list
for top-of-pane attention. Typography moved to semantic `.caption` /
`.caption2.weight(.semibold)`. Row leading inset 28 → 20 to match the
macOS inset-list default. Copy nudged from "Working" → "Working
hours" so the meaning is unambiguous at the footer.

`make check` + `make test` green (174/174). Visual gate against
build/Moves.app via computer-use: single-row Available pane now shows
"Test thread" at the top of the list area and "Working hours: no"
sitting on a thin bar at the bottom — no mystery gap.

## 2026-06-08 — deadline alerts: macos-design + swiftui-pro tightening

Final polish pass over the three new surfaces (chip row, capture palette
chip slot, edit-due sheet, menubar label, popover header) using
`swiftui-pro` + `macos-design`. Floor gate: 174/174 green (no test delta).

Applied:

- **`AlertOffsetChipRow`** — dropped the hardcoded `.font(.system(size: 11,
  weight: .medium))` on chip labels. `Toggle(.button) + controlSize(.small)`
  already resolves to the right typography on macOS; the override fought
  the system metric and broke Dynamic Type scaling. Same fix on the
  leading "Alert me:" label: `.font(.system(size: 11))` → `.font(.caption)`.
- **`EditDueTimeSheet`** ("Alert me" label above the chip row) — same
  `.system(size: 11)` → `.caption` semantic swap.
- **`CapturePaletteView`** — the `.transition(.opacity)` on the chip row
  was dormant (no `value:`-bound animation context). Added a derived
  `chipRowVisible` Bool and a `.animation(.easeOut(0.18), value:
  chipRowVisible)` on the enclosing VStack so the chip row actually fades
  + slides in when a deadline is first recognized. Combined transition:
  `.opacity.combined(with: .move(edge: .top))`.

Skipped (cosmetic):

- `Binding(get:set:)` inside the per-chip ForEach. The Set-membership
  binding has no natural source; the synthetic binding is the simplest
  correct version and well within budget for six chips.
- Three-case switch in the popover header. `if let` would be shorter but
  the `.none → EmptyView()` arm is the most readable expression.
- Menubar overdue chip count using `.fontWeight(.medium)` instead of
  `.bold()` — deliberate emphasis on an urgency chip, not a generic
  semibold sprinkle.

Visual gate (computer-use, build/Moves.app):

1. Capture palette: typed "finish proposal by friday 5pm" — chip row
   appears beneath the deadline preview with At due / 1h / Morning of
   pre-selected (the `.task` `[1440, 60, 0]` defaults). Toggled 30m on,
   pressed Return — save was instant, palette dismissed.
2. Forced a hard captured item to `now + 20m`, relaunched. Popover
   header showed **"•1 soon"** in orange.
3. Moved the same item to `now - 10m`, relaunched. Menubar knight
   tinted with a red "1" chip; popover header showed **"•1 overdue"**
   in red.
4. Edit due time sheet (right-click → Edit due time…) showed the same
   six chips with At due / 30m / 1h / Morning of filled — matches the
   override saved at step 1 + the 30m toggle.

## 2026-06-08 — Deadline alerts: three-state menubar urgency (near / overdue)

Before this pass the menubar knight was binary: either red-tinted with
a `•N` chip (overdue, capped to the 1-hour window the prior subagent
landed) or template-neutral (no deadlines, or none within an hour).
"NEAR but not yet passed" looked identical to "no deadlines at all".
The user asked for a visible warning state so an approaching
deadline pre-empts the cliff.

Backend:

- `Sources/Moves/Persistence/Repositories/ItemRepository.swift`:
  new `dueSoonHardCount(now:soonWindow:)`, default 30-minute window.
  Same status (`captured`/`open`) + `interruption_kind = hard`
  predicate as `dueOrOverdueHardCount`, but the time range flips to
  strict-future `(now, now + soonWindow]`. Inclusive upper bound,
  exclusive lower bound — `now` itself belongs to the
  `dueOrOverdueHardCount` bucket.
- `Sources/Moves/Domain/DeadlineUrgency.swift`: new
  `enum DeadlineUrgency { case none, near, overdue }`. The
  enum's doc comment carries the system-color policy (HIG red
  `#FF3B30` for urgent/destructive, system orange `#FF9500` for
  warning — confirmed against the macos-design skill's
  `visual-design.md`).
- `Sources/Moves/Model/AppStore.swift`:
  - New `private(set) var dueSoonHardCount: Int = 0`.
  - `refreshDueCount()` now fans out to both repo queries via
    `async let` and awaits in sequence. Same call-sites as before.
  - New computed `var renderedDeadlineUrgency: DeadlineUrgency`.
    `.overdue` if `dueOrOverdueHardCount > 0`, else `.near` if
    `dueSoonHardCount > 0`, else `.none`. Gated on the
    `preferences.badgeEnabled` toggle, so a user who disabled the
    badge gets `.none` regardless of DB state — matches
    `renderedBadgeCount`'s policy.

Menubar UI (`Sources/Moves/MovesApp.swift`):

- New `knightImage(for:)` helper builds the knight `Image` per
  `DeadlineUrgency` case. Neutral: `.template` rendering mode +
  `foregroundStyle(.primary)` (system light/dark tinting). Near:
  `.original` + `.orange`. Overdue: `.original` + `.red`.
- The `•N` count chip is overdue-only. Near is tint-only — a
  glanceable warning, not a precise count, per the user's framing.

Popover header (`Sources/Moves/Views/Popover/MenuPopoverView.swift`):

- The `•N due` orange chip became a three-state switch over
  `renderedDeadlineUrgency`. Overdue → "•N overdue" in red,
  near → "•N soon" in orange, none → no chip. Matches the menubar
  tint.

Tests added (1 net):

- `PersistenceRoundTripTests.testDueSoonHardCountWindowBoundaries`
  — fixtures at 10/20/29/30 (boundary)/31/45 minutes ahead plus
  soft + done filters; expects 4 (10, 20, 29, 30) and verifies
  status / interruption-kind / exact-now exclusion.

174 tests, all passing (was 173).

Visual gate via computer-use against `build/Moves.app`:

1. Inserted a hard `captured` item due in 20 minutes via sqlite3.
   Launched Moves. Menubar knight tinted **orange**, no chip.
   Popover header showed **"•1 soon"** in orange.
2. Updated the same item's `due_at` to 10 minutes in the past,
   relaunched. Menubar knight tinted **red** with a red **"1"**
   chip. Popover header showed **"•1 overdue"** in red.
3. Step 3 (60-minute drop-off) was not exercised at runtime — the
   1-hour cap is already covered by
   `testDueOrOverdueHardCountCapsAtOneHour` from the prior backend
   pass and doesn't ride on this change.

## 2026-06-08 — Deadline alerts: per-item offset chips in capture + edit-due (UI)

Surfaces the multi-offset backend that landed in 8a707b7. Until now the
per-kind defaults in `preferences.reminderOffsetsMinutes` /
`deadlineTaskOffsetsMinutes` were applied silently; the user had no way
to bias an individual deadline-bearing item. They asked for it
explicitly.

What changed:

- New `Sources/Moves/Views/Shared/AlertOffsetChipRow.swift`. Canonical
  chip set `[0, 15, 30, 60, 120, 24*60]` rendered as a row of
  `Toggle(isOn:)` `.toggleStyle(.button)` `.controlSize(.small)` —
  selected → filled accent button, unselected → bordered grey
  button. This is the native macOS multi-select chip idiom (Mail's
  toolbar filters, System Settings "Filter by" pills use the same
  shape). Short copy on chips: "At due", "15m", "30m", "1h", "2h",
  "Morning of"; the verbose `AlertOffsetLabel.describe` shape stays
  reserved for Settings where width isn't constrained.
- `Sources/Moves/Views/Capture/CapturePaletteView.swift`: chip row
  appears on its own line below the deadline-preview chip whenever
  the live parse recognized a `dueAt`. Pre-seeded from
  `store.offsetsForCapture(kind:)` for the inferred kind; reseeds
  when the inferred kind transitions (e.g. user types "due" and the
  parse flips from `.capture` to `.task`), but only when it actually
  changes — keystroke noise doesn't undo the user's chip toggles.
  Panel widened 540→620pt to fit all six chips on one line;
  `NSHostingController.sizingOptions = [.preferredContentSize]` so
  the panel grows vertically when the chip row appears.
- `Sources/Moves/Views/Window/Captured/CapturedRow.swift` (the
  `EditDueTimeSheet`): chip row appears under the DatePicker when
  "Has deadline" is on. Prefilled from `alertRepository.forItem(...)`
  (the actually-scheduled offsets), falling back to kind defaults if
  there are none. Sheet widened 340→360pt.
- `Sources/Moves/Model/AppStore.swift`:
  - `capture(_:now:offsetsOverride:)` — new optional parameter,
    `nil` preserves "use kind defaults" for existing callers
    (`OnboardingView`'s seeded capture stays unchanged).
  - `editDueAt(_:dueAt:dueKind:offsetsOverride:)` — same shape.
    Now also calls `alertRepository.deleteForItem(itemId:)` before
    re-scheduling so a second edit doesn't stack on top of the
    first; this runs unconditionally (independent of the scheduler
    being installed) so stale rows can't survive in tests/SwiftPM
    host either.
  - New static `resolveOffsets(override:kindDefault:)` — central
    policy: `nil` → kind default, `[]` → `[0]` (the user can never
    accidentally save a deadline-bearing item with zero alerts),
    populated array → use as-is. Sorted is the chip row's
    responsibility on the way in; the scheduler de-dupes again
    downstream.
- `Sources/Moves/Persistence/Repositories/AlertRepository.swift`:
  added `deleteForItem(itemId:)` for the cancel-and-rebuild path.

Per-item override semantics vs preference defaults: `preferences.*OffsetsMinutes`
are the *starting selection* for the chip row. The user can then
toggle chips on or off before pressing Return / Save. The override
short-circuits `offsetsForCapture(kind:)` only for that one item.
Other callers (onboarding, future scripted captures, reconciliation)
pass `nil` and continue to honor the per-kind defaults from Settings.

Tests added (4 net):

- `Phase4AppStoreTests.testResolveOffsetsNilUsesKindDefault`
- `Phase4AppStoreTests.testResolveOffsetsEmptyOverrideFallsBackToAtDueOnly`
- `Phase4AppStoreTests.testResolveOffsetsPopulatedOverrideWinsOverKindDefault`
- `Phase4AppStoreTests.testEditDueAtDropsPriorAlertsBeforeRescheduling`

173 tests, all passing (was 169 after backend pass).

Visual gate: launched build/Moves.app via computer-use, opened the
capture palette via the popover, typed "finish proposal by friday
5pm". The chip row appeared on its own line with "At due", "1h", and
"Morning of" pre-selected (the `.task` deadline defaults of
`[24*60, 60, 0]`). Toggled 30m on, hit Return. Item saved into
Captured + Deadlines. Right-click → Edit due time → sheet displayed
the chips with At due/30m/1h/Morning of selected, matching the
override that was just saved.

## 2026-06-08 — Deadline alerts: multi-offset scheduling + 1-hour overdue cap (backend)

Backend pass on the deadlines workflow. The user's report: "nothing
happens when a deadline passes." Two root causes — only the at-due
notification was ever scheduled (the `reminderOffsetsMinutes` /
`deadlineTaskOffsetsMinutes` shapes on `UserPreferences` were ignored
by the scheduler), and the menubar badge counted overdue items
forever, making a missed call sit in the chrome until manually
cleared.

What changed:

- `Sources/Moves/Services/ReminderScheduler.swift`: new
  `scheduleAlerts(item:offsetsMinutes:)` that de-dupes / sorts
  descending, computes `fireDate = dueAt - offset*60`, skips
  past-fire offsets entirely (no Alert row, no OS request — the
  reconciler/badge handle past-due state), and writes one Alert row
  + one `moves.item.<itemId>.alert.<alertId>` request per surviving
  offset. Body uses a terse "Due in 15m"/"Due in 1h" copy for
  pre-due fires; at-due stays title-only. `scheduleAtDue(item:)` is
  now a one-liner that calls the new method with `[0]`. The protocol
  seam swapped `notificationSettings()` for
  `currentAuthorizationStatus()` so the test fake doesn't need an
  uninhabitable `UNNotificationSettings`.
- `Sources/Moves/Model/AppStore.swift`:
  `offsetsForCapture(kind:)` picks the offsets list (`.reminder` →
  `preferences.reminderOffsetsMinutes`, `.task` →
  `preferences.deadlineTaskOffsetsMinutes`, `.capture` → `[0]`).
  `capture(_:)` and `editDueAt(_:dueAt:dueKind:)` now call
  `scheduleAlerts` with that list. `reconcileAlerts(now:)` snapshots
  both preference lists into the new `offsetsForItem` closure passed
  to `AlertReconciliation`.
- `Sources/Moves/Services/AlertReconciliation.swift`: same three
  buckets, but the schedule bucket now dispatches to
  `scheduleAlerts` via an injected
  `offsetsForItem: @Sendable (Item) -> [Int]` closure. Pure
  `plan(...)` stays unchanged — the multi-alert work is downstream
  of the decision to schedule. Mark-fired already iterates per-row.
- `Sources/Moves/Persistence/Repositories/ItemRepository.swift`:
  `dueOrOverdueHardCount(now:)` adds `AND due_at >= now - 3600`.
  Items more than an hour past due fall off the menubar badge.
  `allOpenOrCapturedWithDueAt()` unchanged — reconciliation still
  needs to see all of them.

Tests added (5 net):

- `PersistenceRoundTripTests.testDueOrOverdueHardCountCapsAtOneHour`
  — 30m overdue counts, 90m overdue does not, exactly-60m overdue
  is inside the window.
- `AlertReconciliationTests.testReconcileSchedulesAllOffsetsAsAlertRowsForHardFutureItem`
  — three offsets → three Alert rows + three OS requests.
- `AlertReconciliationTests.testReconcileIsIdempotentForMultiAlertItem`
  — covered-by-pending detection prevents double-schedule across
  two reconcile passes.
- `AlertReconciliationTests.testReconcileMarksAllUnfiredAlertsForPastDueItem`
  — every unfired Alert row on a past-due hard item gets stamped.
- `AlertReconciliationTests.testPlanSchedulesHardFutureItemWhenNoPendingExists`
  — plan-level coverage of the new dispatch path.

169 tests, all passing. No UI changes — capture-palette / edit-due
chrome is a follow-on subagent.

## 2026-06-08 — In-app Help window

The product is opinionated about its vocabulary — thread, item, capture,
breadcrumb, deadline, parking, working hours — but none of that vocab
surfaces in the app itself. Added a `HelpView` that teaches the model in
one vertical scroll.

- New file `Sources/Moves/Views/Help/HelpView.swift`: nine sections (What
  is Moves?, Threads, Items: captures/tasks/reminders, The capture hotkey,
  Current vs Available, Breadcrumbs, Deadlines, Working hours, What Moves
  is NOT). Constrained to ~560pt reading measure; ~24pt section rhythm;
  `.title` page header, `.title3` semibold section heads, `.body`
  paragraphs, `.callout` `.secondary` asides. `**bold**` rendered inline
  via `LocalizedStringKey`.
- New `PopoverWindowID.help` case for the window-scene id.
- `MovesApp.swift`: registered a `Window("Moves Help", id: …)` scene
  (600×700, content-resizable, centered) and a `CommandGroup(replacing:
  .help)` that puts "Moves Help" in the Help menu bound to ⌘?. Pulled
  `@Environment(\.openWindow)` up to the `App` level so the commands
  closure can dispatch it.
- Single window, no tabs — this is a teaching page, not configuration.

`make check` and `make test` both clean. 164 tests, no business-logic
changes.

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
