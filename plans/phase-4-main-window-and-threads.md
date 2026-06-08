# Phase 4 — Main window & thread editing

**Goal:** Replace the placeholder main window with the real
editing/organizing surface. Thread detail with Markdown editor.
Working-hours visibility wired through.

**Reads:** INITIAL-PLAN.md §2.9 (no taxonomy creep — keep the surface
narrow), §4.2 (window views), §4.3 (thread detail), §6 (working hours),
§12 (Available behavior), §13 (Captured processing actions).

**Builds on:** Phases 1–3.

## Deliverables

- `Sources/Moves/Views/Window/RootWindow.swift` —
  `NavigationSplitView` with sidebar listing the six top-level views per
  §4.2: Available, Current, Threads, Captured, Deadlines, Parking Lot,
  Settings.
- `Sources/Moves/Views/Window/AvailableView.swift`,
  `ThreadsListView.swift`, `CapturedView.swift`, `DeadlinesView.swift`,
  `ParkingLotView.swift`.
- `Sources/Moves/Views/Window/ThreadDetail/ThreadDetailView.swift` —
  §4.3 layout: header (title/status/kind/visibility), breadcrumb editor,
  current segment summary (read-only here, phase 5 owns segment
  editing), items list with checkbox toggles, Markdown notes panel.
- `Sources/Moves/Views/Markdown/MarkdownEditorView.swift` — plain `TextEditor`
  source on the left, rendered `AttributedString(markdown:)` preview on
  the right. No rich editing (§17 explicitly says plain text is fine for
  v1). Tab-toggleable between edit and preview for narrow widths.
- `Sources/Moves/Services/WorkingHoursService.swift` — given a date,
  return whether we're inside working hours and apply the visibility
  policy enum (`normal / hide_during_work / downweight_during_work /
  only_during_work`) to a list of threads.
- `Sources/Moves/Views/Window/Settings/SettingsView.swift` — working-hours
  range (weekday picker + start/end times). Other settings land in
  phase 6.
- `Sources/Moves/Views/Window/Captured/CapturedRow.swift` — actions
  menu: attach to thread, convert to reminder/task, mark done,
  cancel/delete, edit due time (§13).
- `AppStore` gains: `attachToThread(_:item:)`, `convertItemKind(_:to:)`,
  `setVisibility(_:thread:)`.

## Decisions

- **Markdown rendering:** `AttributedString(markdown:)` for v1 — covers
  headings/lists/links/inline code. Code blocks render as monospaced
  paragraphs; tables are not supported (v2 candidate).
- **Window scenes:** keep the single `Window("Moves", id: "main")` scene;
  the sidebar drives content. No multi-window flow.
- **Working hours:** stored as a single row in `settings` table (key:
  `working_hours`, value: JSON `{days, start, end}`). Cached in
  `AppStore`.
- **Captured processing:** the row's context menu performs the action
  inline; only "attach to thread" opens a thread picker.

## Out of scope

- Regimented segments — editing/advancement is phase 5; phase 4 renders
  segment state read-only.
- Markdown import (phase 5).
- Settings beyond working hours (phase 6).
- Export/import (phase 6).

## Definition of done

- Every view from §4.2 renders and is reachable from the sidebar.
- Thread detail edits write through repos and immediately reflect in the
  popover (Phase 3) and Available counts.
- Setting a thread to `hide_during_work` hides it from Available during
  working hours unless it has a deadline-bearing item.
- Markdown notes editing is round-trip stable (write → relaunch → still
  there).

## Open questions

- Where should the visibility-policy control live in the UI? Inline pill
  in the thread detail header vs in a "thread settings" gear. Default to
  inline pill — it's a one-click affordance and matches §2.10's "passive
  display aid" spirit.
- Captured "edit due time" — inline date picker or a small sheet? Sheet,
  to share UI with the capture-edit case from phase 2.
