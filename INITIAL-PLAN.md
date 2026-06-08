# Product Plan: Menu-Bar Re-Entry App

## 1. Product thesis

This is a macOS menu-bar productivity app organized around **resuming important threads of work**, not managing a giant task inventory.

The app exists for this moment:

> It is 2pm on Tuesday. I am not using my time well. I want to quickly pick something important and productive to do, without optimizing my entire day, negotiating a priority matrix, or spelunking through a task database.

The core function is not scheduling. It is not priority management. It is not time tracking. It is not behavior policing.

The core function is:

> Show me the live things I could resume right now, with enough context that I can actually resume one of them.

The app should also replace lightweight day-to-day Clock.app timer usage: quick reminders, arbitrary near-term deadlines, and simple notifications. These reminders should integrate with the productivity surface, but they are not the central organizing concept.

---

## 2. Design principles

### 2.1 Re-entry over task management

The app is about returning to meaningful work.

A typical task app asks:

> What tasks are due? What is next? What is highest priority?

This app asks:

> What important thread can I pick back up right now?

The primary object is a **Thread**, not a task.

Examples:

* Python refresh
* Multivariable calculus
* YIMBY essay
* Picture frames
* Wood shop improvements
* Civic writing
* House projects

Each thread should have a visible re-entry point: a breadcrumb, segment, or concrete next move.

---

### 2.2 Productive is enough

The user is not trying to bin-pack every minute of the day. The app should not over-optimize.

The goal is to move from:

> I am wasting time.

to:

> I am doing something productive.

That is enough.

The app should not attempt to rank all possible productive activities by value. It should present available options.

---

### 2.3 No priority theater

Do not implement low/medium/high priority.

The only real priority signal is a deadline.

Priority levels have failed the user in other apps and should be treated as a product smell. Deadlines may change visibility and urgency. Nothing else should.

Allowed urgency concepts:

* Due now
* Due soon
* Due today
* Upcoming
* Overdue

Forbidden concepts:

* Low priority
* Medium priority
* High priority
* Eisenhower matrix
* Priority score
* Focus score
* Importance ranking

---

### 2.4 Deadlines are exceptional

Deadlines are real and must cut through the normal display.

A parked thread with a deadline should still surface.

A captured item with a deadline should trigger alerts even before it has been processed or attached to a thread.

Deadlines are the only thing allowed to jump the queue.

---

### 2.5 Passive, not disciplinary

The app should not police the user.

No idle detection.
No browser/app monitoring.
No “you seem distracted” nudges.
No shame language.
No streaks.
No productivity score.

The user initiates the interaction by clicking the menu bar icon or using the capture hotkey.

---

### 2.6 Zero current work is valid

The app tracks one current thread, but having no current thread is a normal state.

The UI should make it easy to say:

> I am not currently representing that I am working on anything.

This must be one click away.

Stopping should not feel like failure.

---

### 2.7 Breadcrumbs are the killer feature

When switching away from a thread, stopping work, or parking a thread, the app should prompt for a breadcrumb.

A breadcrumb is the note that allows future re-entry.

Examples:

* RESP parser works; next failure is GET nil bulk string.
* Need to revise the filtering paragraph; current objection is too abstract.
* Half-lap is slightly proud on the top-left corner; sand before glue-up.
* Finished constrained extrema example 3; next do one with an ellipse constraint.

The app should preserve the user’s working state, not just mark tasks complete.

---

### 2.8 Parked is not abandoned

Parking is a first-class state.

A parked thread means:

> Not in my daily choice set right now.

It does not mean failed, stale, abandoned, someday/maybe, or overdue.

The app must make parking emotionally cheap.

Parked threads live in the Parking Lot, which is hidden/collapsed by default and intentionally visited occasionally.

---

### 2.9 No taxonomy creep

No Areas.
No tags.
No contexts beyond working-hours visibility.
No multilevel project hierarchy.

The app should resist becoming an ontology of the user’s life.

The organizing levels are:

* Thread
* Segment
* Item

That is enough.

---

### 2.10 Headroom is a nudge, not the app

The app should show upcoming reminders/deadlines and roughly how much time exists before the next hard interruption.

This is only a display aid.

It should not hide work.
It should not auto-rank work.
It should not become a day planner.
It should not attempt to schedule or bin-pack the user’s day.

Headroom answers:

> How much runway do I roughly have?

It does not answer:

> What is the mathematically optimal thing to do next?

---

### 2.11 Regimented work is preloaded breadcrumbs

A regimented thread is not a separate productivity model.

It is simply a thread with preloaded ordered segments.

Examples:

* Python refresh day 1, day 2, day 3…
* Multivariable calculus lesson 1, lesson 2, lesson 3…
* Writing course module 1, module 2…

Only one segment should be active at a time.

Switching away from a regimented thread should not automatically advance the segment.

Segment advancement is explicit.

---

### 2.12 Details are Markdown

Thread details, segment details, and item notes should be arbitrary Markdown.

The app needs an integrated Markdown editor/viewer.

Do not over-structure notes. The app should preserve context and working state, not force every piece of information into a form field.

---

## 3. Core vocabulary

### Thread

An ongoing line of work.

A thread can be active, parked, or done.

Examples:

* Python refresh
* Multivariable calculus
* Picture frames
* Shop improvements
* YIMBY essay

A thread has:

* title
* status
* kind
* visibility policy
* breadcrumb
* Markdown detail
* optional current segment
* optional deadline-bearing items

---

### Breadcrumb

The current re-entry note for a thread.

This is the most important field in the app.

A breadcrumb should usually be written or updated when the user stops, switches, or parks a thread.

---

### Segment

An ordered unit inside a regimented thread.

Examples:

* Day 08 — asyncio streams
* Lesson 14 — Lagrange multipliers
* Draft pass 03 — revise intro

A segment may have:

* built-in move
* Markdown body
* optional due date
* optional scheduled date
* rough estimate
* generated checklist items

Only one segment is active per regimented thread.

---

### Item

A captured thing.

Items cover:

* inbox captures
* reminders
* deadline tasks
* lightweight todos

An item may or may not belong to a thread.

Examples:

* buy walnut dowels
* call Sarah at 4pm
* pull rice in 18m
* submit calc homework Friday 5pm
* check glue-up in 45m

Items with deadlines should become active immediately, even if still unprocessed.

---

### Current

The one thread currently selected as being worked on.

Current may be null.

The user can stop current work without switching to something else.

---

### Parking Lot

The hidden/collapsed set of parked threads.

The Parking Lot is for optional revisiting, not reminders or nagging.

---

## 4. Product surfaces

## 4.1 Menu-bar popover

The menu-bar popover is the daily-driver UI.

It should be fast, calm, and small.

Suggested structure:

```txt
Current
Python refresh
Day 08 — asyncio streams
Next: GET nil bulk string still failing; inspect serializer

[Stop] [Switch] [Park]

Upcoming
Next hard reminder: Call at 4:00pm — 1h 42m
Other: Pull rice at 4:30pm

Available
Python refresh
Fix GET nil bulk string
~45m

Multivariable calculus
Lesson 14
Do one Lagrange multiplier problem
~30m

Writing
Revise filtering paragraph
~60m

De-emphasized during working hours
Picture frames
Dry-fit half-lap frame
~20m

Captured
buy walnut dowels
submit calc homework — Fri 5pm

[Capture…] [Parking Lot] [Open App]
```

If there is no current thread:

```txt
Current
Not working on anything

Upcoming
Next hard reminder: Call at 4:00pm — 1h 42m

Available
Python refresh — Fix GET nil bulk string
Multivariable calculus — Do one Lagrange multiplier problem
Writing — Revise filtering paragraph
```

The “not working on anything” state should be neutral.

---

## 4.2 Main window

The main window is mostly for editing and organizing.

Views:

* Available
* Current
* Threads
* Captured
* Deadlines / Upcoming
* Parking Lot
* Settings

The main window should not become the primary daily-driver interface. The menu-bar popover is the main daily surface.

---

## 4.3 Thread detail view

A thread detail view should include:

* title
* status: active / parked / done
* kind: normal / regimented
* visibility policy
* breadcrumb
* current segment, if any
* Markdown detail
* associated items
* rough time log

Example:

```txt
Python refresh

Status: Active
Kind: Regimented
Visibility: Normal

Current segment:
Day 08 — asyncio streams

Breadcrumb:
GET nil bulk string still failing; inspect serializer.

Built-in segment move:
Implement async Redis command loop.

Items:
- [ ] Add nil bulk string test
- [ ] Implement GET miss
- [ ] Check StreamWriter.drain semantics

Notes:
[Markdown editor/viewer]
```

---

## 4.4 Capture hotkey

There should be exactly one global hotkey in v1: Capture.

The capture UI should be a small text field.

Examples:

```txt
call Sarah at 4
pull rice in 18m
check glue-up in 45m
submit calc homework Friday 5pm
buy walnut dowels
```

Pressing Enter should save immediately.

The app should show a brief confirmation with parsed result.

Examples:

```txt
Saved reminder: call Sarah — today 4:00pm
Saved reminder: pull rice — in 18m
Saved captured item: buy walnut dowels
```

Capture should not require choosing a thread.

Capture should not require tags.

Capture should not require categorization.

Deadline-bearing captures should schedule alerts immediately.

---

## 5. Main flows

## 5.1 Choosing work

User opens menu-bar popover.

They see:

* current state
* upcoming hard reminders/deadlines
* available threads
* de-emphasized threads
* captured items

They click an available thread.

The app:

1. Sets that thread as current.
2. Opens the detail view.
3. Preserves existing breadcrumb.
4. Does not start a precise timer.
5. May record `started_at` for coarse later time estimation.

---

## 5.2 Stopping work

User clicks Stop.

The app shows:

```txt
Stopping Python refresh

Breadcrumb:
[ GET nil bulk string still failing; inspect serializer ]

Rough time:
[ none ] [ 15m ] [ 30m ] [ 45m ] [ 1h ] [ 2h ] [ 3h+ ]

[Stop] [Park instead] [Cancel]
```

Behavior:

* Existing breadcrumb is prefilled.
* User can edit it.
* User can leave it unchanged.
* User can clear it.
* User can choose rough time.
* Current becomes null.
* Thread remains active unless parked.

There should be an escape hatch. The app should not trap the user.

---

## 5.3 Switching work

User clicks a different available thread while one is current.

The app shows:

```txt
Before switching from Python refresh:

Breadcrumb:
[ GET nil bulk string still failing; inspect serializer ]

Rough time:
[ none ] [ 15m ] [ 30m ] [ 45m ] [ 1h ] [ 2h ] [ 3h+ ]

[Switch to Writing] [Park Python] [Cancel]
```

Behavior:

* Saves breadcrumb.
* Optionally logs coarse time.
* Sets new current thread.
* Does not mark the old segment done.
* Does not advance regimented work automatically.

---

## 5.4 Parking a thread

User clicks Park.

The app asks for breadcrumb first:

```txt
Parking Python refresh

Breadcrumb:
[ GET nil bulk string still failing; inspect serializer ]

[Park] [Cancel]
```

Behavior:

* Thread status becomes parked.
* Thread disappears from normal Available.
* Thread appears in Parking Lot.
* Deadline-bearing items from the thread still appear in Upcoming / Deadlines.

---

## 5.5 Completing a regimented segment

User explicitly clicks Mark Segment Done.

The app:

1. Marks current segment done.
2. Prompts for rough time.
3. Advances to next pending segment.
4. Updates the displayed move from the next segment.
5. Does not require a user-written breadcrumb unless there is useful residual state.

Segment advancement is never implicit.

---

## 5.6 Capturing a reminder

User hits global capture hotkey.

Input:

```txt
check glue-up in 45m
```

The app parses:

* title: check glue-up
* due_at: now + 45 minutes
* kind: reminder
* interruption_kind: hard
* alert: at due time

It schedules a macOS notification.

The item appears in Upcoming.

The user may later attach it to a thread, but that is not required.

---

## 5.7 Capturing a deadline task

Input:

```txt
submit calc homework Friday 5pm
```

The app parses:

* title: submit calc homework
* due_at: next Friday at 5pm
* kind: task or capture
* interruption_kind: soft by default, unless user marks hard
* alert policy: default deadline policy

It appears in Captured and Upcoming.

It alerts even before being processed.

---

## 6. Working-hours behavior

There is one global working-hours setting.

Example:

```txt
Monday-Friday, 9:00am-5:30pm
```

This is not a context system. It is a decluttering tool.

Each thread has a visibility policy:

```txt
normal
hide_during_work
downweight_during_work
only_during_work
```

Behavior:

* `normal`: always shown.
* `hide_during_work`: hidden from Available during working hours unless deadline-bearing.
* `downweight_during_work`: shown in a lower/de-emphasized section during working hours.
* `only_during_work`: shown only during working hours unless deadline-bearing.

No other contexts in v1.

---

## 7. Upcoming / headroom behavior

Upcoming is a nudge.

It should show:

* next hard reminder
* time until next hard reminder
* soonest deadline/reminder items
* overdue items

It should not:

* auto-schedule the user
* hide available threads
* rank work
* decide what fits
* become a calendar

Example:

```txt
Upcoming

Next hard reminder:
4:00pm Call with Sarah — 1h 42m

Also:
4:30pm Pull rice
Friday 5:00pm Submit calc homework
```

Available items should remain visible even if their estimate exceeds the time until the next hard reminder.

At most, the UI can show the runway:

```txt
~1h 42m until next hard reminder
```

The user decides what to do with that information.

---

## 8. Reminder and alert semantics

## 8.1 Item due times

All timers and deadlines normalize to an absolute `due_at`.

Examples:

```txt
in 45m      -> now + 45 minutes
at 4        -> next 4:00
at 4pm      -> next 4:00pm
tomorrow 9  -> tomorrow 9:00am
Friday 5pm  -> next Friday 5:00pm
2026-06-12  -> date deadline
```

## 8.2 Reminder kinds

Each deadline-bearing item has an interruption kind:

```txt
none
soft
hard
```

Suggested defaults:

* `in 45m`: hard
* `at 4pm`: hard
* `call at 4pm`: hard
* `leave at 5:15`: hard
* `due Friday`: soft
* `submit homework Friday 5pm`: soft
* no due time: none

Hard items contribute to the displayed runway.

Soft items appear in Upcoming but do not define runway.

## 8.3 Alerts

Alerts should support:

* at due time
* 5 minutes before
* 10 minutes before
* 1 hour before
* 1 day before
* custom offset

Default policies:

```txt
Quick timer/reminder:
- at due time

Deadline task:
- configurable
- likely defaults: morning of, 1 hour before, at due time
```

## 8.4 Notifications

Use macOS notifications.

The menu-bar icon may show a simple badge for due/overdue items.

Notification actions should include snooze.

Required snooze options:

* 5 minutes
* 15 minutes
* 1 hour

Completing from notification is useful but optional for v1.

---

## 9. Markdown import for regimented threads

Regimented threads should be importable from deterministic Markdown.

No LLM parsing.

Use YAML frontmatter plus H2 segments.

Example:

```md
---
title: Python Refresh
kind: regimented
visibility: normal
default_estimate_minutes: 60
---

## Day 01: Modern Python syntax
date: 2026-06-01
estimate: 60

move: Write a tiny parser using dataclasses and match/case.

- [ ] Review dataclasses
- [ ] Review type hints
- [ ] Write parser
- [ ] Add pytest cases

## Day 02: pathlib, argparse, pytest
date: 2026-06-02
estimate: 60

move: Build a compact access-log parser.

- [ ] Parse one line
- [ ] Add named-group regex
- [ ] Add invalid-line tests
```

Parsing rules:

1. YAML frontmatter defines thread metadata.
2. Each H2 starts a segment.
3. Segment metadata lines are `key: value` lines immediately after the heading.
4. Segment metadata ends at the first blank line.
5. `move:` defines the segment’s built-in move.
6. Markdown checkboxes become associated items.
7. Remaining content becomes `body_markdown`.
8. Segment order is determined by file order.
9. First pending segment becomes active.
10. Import should be idempotent if possible, but v1 can start with create-only import.

Supported frontmatter:

```yaml
title: Python Refresh
kind: regimented
visibility: normal
default_estimate_minutes: 60
```

Supported segment metadata:

```txt
date: 2026-06-01
due: 2026-06-12 17:00
estimate: 60
move: Do one Lagrange multiplier problem.
```

---

## 10. Data model

SQLite local database.

No sync in v1.

Use WAL mode.

Use explicit migrations.

Timestamps should be stored as ISO-8601 strings or integer Unix timestamps. Pick one and use it everywhere.

Suggested schema:

```sql
CREATE TABLE threads (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active', 'parked', 'done')),
  kind TEXT NOT NULL CHECK (kind IN ('normal', 'regimented')),
  visibility TEXT NOT NULL CHECK (
    visibility IN ('normal', 'hide_work', 'downweight_work', 'only_work')
  ),
  breadcrumb TEXT NOT NULL DEFAULT '',
  detail_markdown TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_touched_at TEXT
);

CREATE TABLE segments (
  id TEXT PRIMARY KEY,
  thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  order_index INTEGER NOT NULL,
  body_markdown TEXT NOT NULL DEFAULT '',
  built_in_move TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL CHECK (status IN ('pending', 'active', 'done', 'skipped')),
  scheduled_at TEXT,
  due_at TEXT,
  estimate_minutes INTEGER,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE items (
  id TEXT PRIMARY KEY,
  thread_id TEXT REFERENCES threads(id) ON DELETE SET NULL,
  segment_id TEXT REFERENCES segments(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  body_markdown TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL CHECK (status IN ('captured', 'open', 'done', 'canceled')),
  kind TEXT NOT NULL CHECK (kind IN ('capture', 'task', 'reminder')),
  due_at TEXT,
  due_kind TEXT NOT NULL CHECK (due_kind IN ('none', 'date', 'datetime')),
  interruption_kind TEXT NOT NULL CHECK (interruption_kind IN ('none', 'soft', 'hard')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT
);

CREATE TABLE alerts (
  id TEXT PRIMARY KEY,
  item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  offset_minutes INTEGER NOT NULL,
  fired_at TEXT
);

CREATE TABLE current_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  thread_id TEXT REFERENCES threads(id) ON DELETE SET NULL,
  segment_id TEXT REFERENCES segments(id) ON DELETE SET NULL,
  started_at TEXT
);

CREATE TABLE time_log (
  id TEXT PRIMARY KEY,
  thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
  segment_id TEXT REFERENCES segments(id) ON DELETE SET NULL,
  week_start TEXT NOT NULL,
  rough_minutes INTEGER NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
```

Useful indexes:

```sql
CREATE INDEX idx_threads_status ON threads(status);
CREATE INDEX idx_segments_thread_status ON segments(thread_id, status);
CREATE INDEX idx_items_due_at ON items(due_at);
CREATE INDEX idx_items_status_due ON items(status, due_at);
CREATE INDEX idx_items_thread ON items(thread_id);
CREATE INDEX idx_time_log_week ON time_log(week_start);
```

---

## 11. Move resolution

The Available list should show one resumable move per active thread.

There does not need to be a `moves` table in v1.

A move is a UI projection.

Resolution order:

```txt
1. If thread.breadcrumb is non-empty:
   show breadcrumb.

2. Else if thread is regimented and has active/pending segment:
   show segment.built_in_move.

3. Else if thread has an open item:
   show first open item.

4. Else:
   do not show thread in Available.
```

For regimented threads:

* active segment wins over pending segment
* if no active segment exists, first pending segment becomes the displayed segment
* only explicit completion advances the active segment

---

## 12. Available list behavior

The Available list includes active threads with a resolved move.

Ordering should be simple and stable.

Suggested sections:

```txt
Deadline-bearing
Available
De-emphasized during working hours
```

Do not sort by fake priority.

Deadline-bearing threads/items appear first only because deadlines are real.

Within Available, sort by:

1. last touched, descending; or
2. manual order; or
3. creation order

Manual order is probably best eventually. For v1, last touched is acceptable.

Do not auto-hide based on headroom.

Do not auto-rank based on estimated time.

---

## 13. Captured list behavior

Captured items are unprocessed inputs.

They may have deadlines.

A captured item with a deadline should:

* appear in Captured
* appear in Upcoming
* schedule notifications
* optionally appear in Deadlines
* not require attachment to a thread

Processing actions:

* attach to thread
* convert to reminder
* convert to task
* mark done
* cancel/delete
* edit due time

No tags.

No areas.

---

## 14. Time tracking

Time tracking should be coarse.

No precise timers as a core experience.

When stopping, switching, parking, or completing a segment, prompt:

```txt
Rough time:
[ none ] [ 15m ] [ 30m ] [ 45m ] [ 1h ] [ 2h ] [ 3h+ ]
```

Store only rough minutes.

Weekly view:

```txt
This week

Python refresh          ~3h
Multivariable calculus  ~4h
Writing                 ~2h
Wood shop               ~3h
Picture frames          ~1h
```

No minute-level precision.

No productivity score.

No streaks.

---

## 15. Date parsing grammar

Keep date parsing intentionally small.

Supported forms:

```txt
in 10m
in 45m
in 2h
at 4
at 4pm
tomorrow
tomorrow 9
tomorrow 9am
friday
friday 5pm
due friday
due friday 5pm
by friday
by friday 5pm
YYYY-MM-DD
YYYY-MM-DD HH:MM
```

Rules:

* `in` forms are relative timers.
* `at` forms create next occurrence of that clock time.
* weekday means next occurrence of that weekday.
* if an ambiguous time has already passed today, choose the next valid occurrence.
* `due` and `by` imply soft deadline by default.
* `in` and `at` imply hard reminder by default.
* no recognized date/time leaves item as captured without deadline.

Examples:

```txt
call Sarah at 4
=> title: call Sarah
=> due_at: next 4:00
=> interruption_kind: hard

pull rice in 18m
=> title: pull rice
=> due_at: now + 18m
=> interruption_kind: hard

submit calc homework due Friday 5pm
=> title: submit calc homework
=> due_at: next Friday 5pm
=> interruption_kind: soft

buy walnut dowels
=> title: buy walnut dowels
=> no deadline
=> interruption_kind: none
```

---

## 16. Notifications and badge

Use macOS UserNotifications.

Required:

* notification at due time
* configurable alert offsets
* snooze actions
* menu-bar badge for due/overdue count

Snooze options:

* 5 minutes
* 15 minutes
* 1 hour

Badge behavior:

* show count of due/overdue hard reminders and deadline items
* do not show count of ordinary captured items
* do not show count of available threads
* do not create generic productivity pressure

---

## 17. Technical architecture

Target:

* macOS
* SwiftUI
* menu-bar app
* SQLite backend
* local-only v1
* future Litestream sync/backup in v3

Suggested components:

```txt
App
- SwiftUI app entry
- MenuBarExtra
- main window scene
- global hotkey registration
- notification delegate

Persistence
- SQLite connection
- migrations
- repositories
- query projections

Domain
- Thread
- Segment
- Item
- Alert
- CurrentState
- TimeLog

Services
- CaptureParser
- ReminderScheduler
- AvailabilityService
- MoveResolver
- WorkingHoursService
- MarkdownImportService
- TimeLogService

UI
- MenuPopoverView
- CapturePaletteView
- ThreadDetailView
- MarkdownEditorView
- AvailableListView
- CapturedListView
- ParkingLotView
- SettingsView
```

SQLite access options:

* GRDB is probably the best Swift SQLite wrapper.
* Raw SQLite is acceptable if the implementer prefers.
* Avoid Core Data for v1. The model is simple and SQLite is a product requirement.

Markdown:

* Store Markdown as text.
* Use a Markdown renderer for preview.
* Editing can be plain text in v1.
* Rich Markdown editing is not required.

Menu bar:

* Use `MenuBarExtra` if deployment target supports it.
* If more control is needed, use an `NSStatusItem` wrapper.

Global hotkey:

* Use Carbon hotkey APIs, KeyboardShortcuts package, or equivalent.
* v1 only needs one hotkey: Capture.

Notifications:

* Use `UNUserNotificationCenter`.
* Register snooze actions.
* Persist scheduled alerts in SQLite.
* On app launch, reconcile pending alerts with database state.

---

## 18. v1 scope

### Must have

* menu-bar popover
* global capture hotkey
* fast capture of reminders/tasks
* simple date parsing
* macOS notifications
* snooze
* menu-bar badge for due/overdue items
* current thread state
* null current state
* stop/switch/park flows
* breadcrumb prompt
* active / parked / done thread states
* Parking Lot
* Available list
* working-hours visibility
* Markdown thread detail
* regimented Markdown import
* one active segment per regimented thread
* explicit segment completion
* coarse rough-time logging
* SQLite local database
* migrations
* export/import database or Markdown backup

### Explicitly not v1

* sync
* tags
* areas
* priorities
* weekly review
* full calendar
* app/browser monitoring
* automatic scheduling
* recommendation engine
* energy/context matrix
* subprojects
* multilevel hierarchy
* precise time tracking
* Pomodoro/streak mechanics
* productivity scoring
* AI parsing
* complex natural language dates
* recurring reminders

---

## 19. v2 candidates

Only after v1 proves the core loop.

Possible v2 features:

* better Markdown editor
* better manual ordering of Available threads
* richer deadline editing
* recurring reminders
* calendar import/read-only display
* search
* saved capture presets
* import/export regimented plans
* command palette
* item attachment flow improvements
* notification completion actions
* more robust date parser

---

## 20. v3 candidates

* sync / backup via Litestream or similar
* multi-device story
* conflict handling
* shared/imported regimented plans
* mobile companion capture
* optional calendar integration

---

## 21. Product anti-patterns to avoid

Do not let implementation drift into these:

### Generic GTD clone

The app should not become Things with different nouns.

Tasks are subordinate to threads. The daily surface is Available, not a giant Today list.

### Priority manager

Do not add low/medium/high priority. Deadlines are enough.

### Scheduling optimizer

Do not turn headroom into automatic scheduling.

### Taxonomy garden

No areas, tags, contexts, folders, goals, OKRs, projects-within-projects, or review categories.

### Shame machine

No streaks, scores, productivity grades, idle warnings, or moralizing copy.

### Fine-grained tracker

No second-by-second timers. No detailed time accounting. Rough weekly time is enough.

### Calendar replacement

The app needs deadlines and reminders, not a full calendar.

### LLM-dependent parser

Markdown imports and capture parsing must be deterministic.

---

## 22. The core invariant

An active thread should appear in Available only if it has a re-entry point.

A re-entry point is one of:

1. breadcrumb
2. active regimented segment with built-in move
3. next pending regimented segment with built-in move
4. open item attached to the thread

If a thread has no re-entry point, it should not clutter Available.

It can still exist in Threads.

---

## 23. The product in one sentence

A passive macOS menu-bar app that helps you stop wasting time by quickly resuming one important thread of work, while also handling lightweight reminders and deadlines without turning into a generic GTD system.

