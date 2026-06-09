# UI-NITS

A running log of the UI feedback Thomas has given on Moves, written down so
future agents can synthesize general rules out of it instead of relitigating
each individual nit.

Each entry: the **observation** (verbatim or close), the **rule it implies**,
and the **concrete change** that landed. Group entries by theme.

---

## Don't override system control typography

**Rule.** When a control wraps a `Toggle(.button)` / `Button` /
`Menu` at `.controlSize(.small)`, the system already picks the right
font size and weight for that control class. Slapping
`.font(.system(size: 11, weight: .medium))` on the label fights the
system metric, drops out of Dynamic Type scaling, and produces
inconsistent typography across the same idiom (filter pills in Mail,
System Settings "Filter by" pills).

**Landed.**
- `AlertOffsetChipRow` — dropped the explicit chip-label font; the
  toggle's small-button style now resolves automatically.
- The row's leading "Alert me:" label and the edit-due sheet's
  "Alert me" label both moved from `.font(.system(size: 11))` to the
  semantic `.font(.caption)`, matching the rest of the popover and
  capture-palette hints.

**Generalize.** Reach for semantic fonts (`.caption`, `.callout`,
`.body`, `.headline`) before reaching for `.font(.system(size: …))`.
The numeric form should only appear when there's no semantic match —
the 22pt Spotlight-style capture input is the legitimate exception.

---

## Animate transitions with a `value:`-bound trigger

**Rule.** `.transition(.opacity)` on a conditionally-rendered subview
is dormant unless an enclosing modifier provides an animation context
keyed on the same condition. Without it, the transition declaration
is decorative — the view pops in instantly. SwiftUI animates state
changes only when the surrounding view tree declares an animation,
either via `withAnimation` at the mutation site or
`.animation(_:value:)` on the container.

**Landed.** Capture palette's chip row had `.transition(.opacity)`
but no animation context. Added a derived `chipRowVisible: Bool`
and an `.animation(.easeOut(0.18), value: chipRowVisible)` on the
parent VStack. The chip row now fades + slides in when a deadline
is first recognized.

**Generalize.** Every `.transition(…)` needs a paired `.animation(_:
value:)` on a container watching whatever state controls the
view's appearance, or it's silently a no-op.

---

## Don't repeat the sidebar

> "Threads is wildly too prominent on the screen, it's static text that does
> nothing but label the pane."
>
> "what does this heading accomplish" *(arrow pointing at the window-level
> "Moves" navigation title)*

**Rule.** The sidebar already labels the current pane. A second giant heading
("Threads" / "Available" / "Captured") inside the content area is redundant
chrome that fights with actual content for the reader's eye. Pane titles do
not earn their visual weight when the surrounding UI already names the pane.

**Landed:**
- `RootWindow` no longer sets `.navigationTitle("Moves")` — the window title
  bar already says "Moves".
- `PaneShell` and `PaneListShell` no longer accept a `title` parameter. The
  shells are pure layout wrappers; each pane renders only its actual content
  + the small captions that carry real information (e.g. the "Working" pill).

**Generalize.** Whenever you're about to write a section/page title that just
restates what the surrounding UI already conveys, delete it. Save large
headings for content that wouldn't otherwise be findable.

---

## Don't render implicit defaults

> "don't render the default state, just NOT 'normal'" *(on the kind label
> appearing on every thread row)*

**Rule.** When a property has an "obvious default" value, don't render the
default on every row. Render only deviations from the default — those are
the values that carry information.

**Landed.** Thread rows in `AvailableView` and `ThreadsListView` only show
`thread.kind.rawValue.capitalized` when `kind != .normal`. "Regimented"
still surfaces because it's not the default; "Normal" stays invisible.

**Generalize.** Apply the same rule to visibility (don't render "Normal"),
status when implied by context, and any future enum where one case is the
obvious baseline.

---

## Strip noise from subtitles

> "???" *(arrow at the "09:00–17:30" hours range trailing the Working pill)*

**Rule.** A subtitle should answer one at-a-glance question. Tacking on
contextual info "for completeness" turns the subtitle into a dashboard, and
the eye starts skipping it. If the extra info lives elsewhere (Settings, the
sidebar, the toolbar), don't restate it here.

**Landed.** The Available pane's Working pill dropped the `· 09:00–17:30`
trailing text. The pill answers "am I in working hours now?"; the configured
hours live in Settings, one Cmd-, away.

**Generalize.** Pane subtitles + caption lines should be one bite. If you're
typing a "·" separator inside a subtitle, ask whether the second piece is
really needed.

---

## Affordances must be visible

> "it's not clear the titles of Threads are editable in the UI"

**Rule.** Editable text needs a visual signal that it's editable. A plain
`TextField(.plain)` at large weight is indistinguishable from a static
`Text`. Hover state, focus border, edit icon — pick at least one.

**Landed.** The thread-detail title now has:
- Hover: soft `Color.primary.opacity(0.04)` background + a `pencil` SF
  Symbol fades in on the right.
- Focus: `textBackgroundColor` fill + accent-color stroke border; the
  pencil hides because the caret becomes the active edit signal.

**Generalize.** The same hover-+-focus chrome pattern is the macOS-native
"inline rename" idiom (Finder, Notes). Use it wherever a label doubles as
an edit field.

---

## Don't make the user do silent bookkeeping

> "cmd-n quietly adds an unnamed thread; it should switch to some affordance
> for naming the thread immediately"

**Rule.** A "new item" command should leave the user inside the naming
affordance, not insert a placeholder row labeled "Untitled" that the user
has to track down and rename.

**Landed.** Cmd-N now:
1. Brings the main window forward (`NSApp.activate`).
2. Switches the sidebar to `.threadsList`.
3. Focuses the existing inline "New thread…" `TextField`.
No row is inserted until the user types and presses Return.

**Generalize.** Every "create" command should land focus where the user
will type the name. Two-finger trackpad inertia is acceptable; an
extra "find and rename Untitled 7" step is not.

---

## Use standard platform conventions

> "cmd-[ (back) from the thread/view editor should take me back to the list
> of threads"
>
> "wire settings to idiomatic CMD-, stuff, not a special settings thing in
> a sidebar that makes this look like a Qt app i've ported"
>
> "give all the fields in the main app, where we have entries, the standard
> swipe-left-to-reveal-delete-button behavior"

**Rule.** Don't invent new conventions for things that already have a macOS
convention. Cmd-, opens Settings. Cmd-[ goes back. Cmd-? opens Help. Lists
get swipe-actions, not custom delete buttons. Settings windows have a
toolbar of tab icons, not a sidebar destination.

**Landed:**
- `Settings { … }` scene for Cmd-, + the standard Moves → Settings… menu
  item. Sidebar destination removed.
- `Cmd-[` ("Back to Threads") under View menu via `.focusedSceneValue` so
  it auto-disables when not on a thread detail.
- Native `List` + `.swipeActions(edge: .trailing, role: .destructive)` on
  every main-window list pane.
- Settings panes use `Form` + `.formStyle(.grouped)` + `LabeledContent`
  (the System Settings shape), not card dashboards.

**Generalize.** If a macOS app you respect already does this, look at how
they do it before designing a new shape.

---

## Empty states need proportional space

> "start up with a smaller default window size; right now the empty state
> in each of our panes looks goofy because the window is so large (it looks
> badly laid out)"

**Rule.** A `ContentUnavailableView` (or any centered empty-state) needs
the surrounding window to be sized so the empty state reads as deliberate,
not stranded. A vast white canvas around a tiny centered "Nothing
available" looks like sloppy layout, not intentional minimalism.

**Landed.** Default window size dropped from 980×640 to 800×540. A
`WindowSizeInitializer` `NSViewRepresentable` forces this on first launch
because SwiftUI's `.defaultSize` is ignored when the scene's content is a
`NavigationSplitView` — the split view's intrinsic ideal-width sum wins
otherwise.

**Generalize.** Default-size your windows for the *empty* case, not the
fully-populated case. Users grow into the window; they shouldn't have to
shrink it on first launch.

---

## Don't port other platforms

> "wire settings to idiomatic CMD-, stuff, not a special settings thing in
> a sidebar that makes this look like a Qt app i've ported"
>
> "gross. don't do a split screen here." *(on the Markdown editor)*

**Rule.** Sidebar destinations for things macOS hosts elsewhere read as a
Linux/Windows/web app port. Side-by-side editor+preview reads as a
Markdown demo (Typora, MacDown) rather than a notes field embedded in a
larger app. Choose the native macOS shape.

**Landed:**
- Settings → system Settings scene.
- Markdown notes → preview-first single card with a pencil edit affordance
  that flips into a source editor. No split.

**Generalize.** Before adding a split view / dashboard / "config sidebar",
look at native Mail / Notes / Reminders / System Settings and ask what
shape they'd reach for.

---

## Preview-first for read-mostly content

> "Display the rendered markdown with an edit affordance (a button/icon or
> something) and switch to the editor when it's clicked; if there's no
> markdown note yet, only show the editor until one is created."

**Rule.** When content is mostly read and occasionally edited, default to
the rendered view + an edit affordance. Don't dump the user into the
editor every time they look at the thread. But: empty source must default
to the editor — there's nothing to preview, so an "edit it" button on a
blank canvas is a no-op.

**Landed.** `MarkdownEditorView` defaults to preview when source is
non-empty, with a pencil icon in the top-right corner. Pencil → editor; a
blue "Done" pill (also bound to ⌘↩) → back to preview. Empty source forces
editor mode and hides the pencil. Mode is sticky for the session — no
auto-snap-back interrupting a long edit.

**Generalize.** Apply the same shape to any future rich-text field where
read >> edit (segment body, thread notes, captured-item bodies).

---

## Urgency vocabulary: orange = "needs your attention"

> *On working hours:* "'outside working hours' should be 'Working: [no]'
> with some color highlight or whatever over 'no' or 'yes' ('yes' is the
> more urgent state)"

**Rule.** The orange tint already has a meaning in this app: hard-deadline
items badge orange in the menu bar; Upcoming hard-deadline icons render
orange. Use orange for "this is the more interrupting state." Use neutral
gray for "you're at rest." Don't invent a new color for new states.

**Landed.** The Working pill is orange-tinted when the user is inside
working hours (the more interrupting state); neutral-gray when outside.
Same `tint.opacity(0.15)` background + tinted text idiom as the deadline
chip in `CapturePaletteView`.

**Generalize.** Before reaching for a new color, ask whether one of the
existing colors already means what you want.

---

## Alignment: same x for stacked content

> *(Annotated screenshot: two vertical guide lines drawn over the pane,
> showing the title at one x and the row content at another. Caption:
> "what's going on with this grid here?")*

**Rule.** Stacked text inside a pane should share a left edge. When the
pane title is at 28pt but list rows are at the List's natural inset
(~10–12pt), the misalignment reads as a layout bug, even if the eye can't
articulate why.

**Landed.** Every list-based pane applies
`.listRowInsets(EdgeInsets(leading: 28, trailing: 28, …))` so row content
aligns with the captions above it. (The pane titles themselves are
also gone, per the earlier "don't repeat the sidebar" entry — that
removed half the alignment problem too.)

**Generalize.** When stacking custom content above a `List` with
`.listStyle(.inset)`, either match the list's natural inset on your
custom content or override the row insets to match your custom content's
left edge.

---

## Document the model in-app

> "write a help system that documents all the ideas in this app (in
> particular: threads vs. 'items' (what's that) vs 'tasks', what to do
> with things just captured, &c) — pull from INITIAL-PLAN.md for the
> core ideas"

**Rule.** If the product is opinionated about a vocabulary, the
vocabulary needs to be teachable inside the app — not buried in a spec
file. A user shouldn't have to read the README to know what "thread"
or "item" means.

**Landed.** Help → "Moves Help" (Cmd-?) opens a 600×700 window with
ten sections lifted from INITIAL-PLAN: what Moves is, threads, items
(captures/tasks/reminders), the capture hotkey, Current vs Available,
breadcrumbs, deadlines, working hours, the regimented-Markdown import
format, and "what Moves is NOT." Tone matches the spec — opinionated,
terse, no filler.

**Generalize.** Concepts get an in-app Help section. Formats get an
in-app Help section. Keyboard shortcuts get menu items so they're
discoverable, not just memorizable.

---

## Per-item alert offsets are first-class UI

> "when i add an item with a deadline, somewhere in the ui i need to be able
> to say how far in advance of the deadline i should get alerted (15m, 30m,
> 1hr, etc). multiple alerts."

**Rule.** The Settings → Alerts pane stores *defaults*. Deadline-bearing
items need a per-item override surface at the moment the deadline is set,
not buried two windows deep in preferences. Apply this anywhere a
preference's default is silently expanded into something the user might
want to bias one captured item at a time.

**Landed.**
- New `AlertOffsetChipRow` (`Views/Shared/`): canonical chip set
  `[0, 15, 30, 60, 120, 24*60]` rendered as `Toggle(isOn:)`
  `.toggleStyle(.button)` `.controlSize(.small)`. Selected = filled
  accent button, unselected = bordered grey button. Each chip carries
  short copy: "At due", "15m", "30m", "1h", "2h", "Morning of".
- **Capture palette:** chip row appears on its own line below the
  deadline-preview chip whenever the live parse recognized a `dueAt`.
  Leading "Alert me:" caption in `.system(size: 11)` `.secondary`.
  Seeded from `AppStore.offsetsForCapture(kind:)` for the inferred kind;
  reseeds when the inferred kind changes mid-typing, but only when it
  actually changes — keystroke noise on the title doesn't wipe a
  user's selection.
- **Capture palette panel widened** from 540pt to 620pt to fit all six
  chips on a single line without truncation. Hosting controller now
  uses `sizingOptions = [.preferredContentSize]` so the panel grows
  vertically when the chip row appears.
- **Edit-due sheet:** chip row appears under the DatePicker when "Has
  deadline" is on. Caption "Alert me" in 11pt secondary directly above
  the chips (no `LabeledContent` — the chip row is wider than a typical
  control), prefilled from the item's existing Alert rows (falls back
  to kind defaults if no rows exist). Sheet widened from 340pt to
  360pt for the chip row.
- **Empty selection floor:** the user can deselect every chip, but on
  save we treat `[]` as `[0]`. Deadline-bearing items never save with
  zero scheduled alerts.

**Generalize.** Whenever a setting is "list of values applied per item,"
surface the choice next to the trigger (the date picker, the deadline
preview), not in a global Settings tab. Settings holds the *default*;
the per-item surface holds the *override*.

---

## Menubar conveys three urgency states, not two

> "some visual indication in the menu bar that a deadline is NEAR or
> OVERDUE."

**Rule.** A binary "urgent / not urgent" badge can't distinguish
"approaching" from "absent." Reserve red for the past-tense state
(overdue, can't fix it by hurrying) and use orange for the pre-tense
state (near, you can still act). This matches the existing app
vocabulary established under "Urgency vocabulary: orange = 'needs
your attention'" — and Apple HIG, which calls out system red
`#FF3B30` / `#FF453A` for destructive/urgent and system orange
`#FF9500` / `#FF9F0A` for warning.

**Landed.** Three-state menubar driven by
`AppStore.renderedDeadlineUrgency`:

- **Neutral.** Template knight, system tint. No chip.
- **Near.** Knight tinted **system orange** (`Color.orange`). No
  count chip — a tint-only "approaching" signal, not a precise
  count. Triggered when any hard `captured`/`open` item is due in
  the strict-future window `(now, now + 30 min]`.
- **Overdue.** Knight tinted **system red** (`Color.red`) plus the
  existing red `•N` count chip. Same 1-hour overdue cap as before:
  once the item is more than an hour past due, it falls out of the
  bucket and the menubar returns to neutral / near.

Popover header mirrors the same state machine in matching language:

- Overdue → "**•N overdue**" in red.
- Near → "**•N soon**" in orange.
- Neutral → no chip.

**Generalize.** When a chrome surface conveys a state, ask whether
the user can act *before* vs. *after* the event. Pre-event states
get warning colors (orange/yellow); post-event states get urgency
colors (red). They are different in kind and shouldn't share a tint.

---

## Working notes (no rule yet, but worth recording)

- **PaneShell/PaneListShell are now pure layout wrappers** (no title,
  no subtitle, no view-builder slots). The Phase-A Tom's Laws audit
  caught the generic ceremony version and rolled it back; the followup
  here finished the job.
- **List vs ScrollView matters for swipe-actions.** `.swipeActions`
  only fires inside a `List`/`Form`. When converting `VStack { ForEach }`
  to a list, use `PaneListShell` (no enclosing ScrollView) — not the
  ScrollView-wrapping `PaneShell`.
- **`.defaultSize` is broken on `NavigationSplitView`.** SwiftUI prefers
  the split view's intrinsic ideal-width sum. `WindowSizeInitializer` is
  the workaround until Apple fixes it.
