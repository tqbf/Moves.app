# Phase 5 — Regimented threads & time log

**Goal:** Make regimented threads first-class: segments with an active /
pending lifecycle, explicit completion + advancement, and import from
deterministic Markdown. Add the weekly rough-time view.

**Reads:** INITIAL-PLAN.md §2.11 (regimented = preloaded breadcrumbs),
§3 (Segment), §5.5 (segment completion), §9 (Markdown import), §14
(rough time / weekly view).

**Builds on:** Phases 1–4.

## Deliverables

- `Sources/Moves/Views/Window/ThreadDetail/SegmentsPanel.swift` — under
  the thread detail, ordered list of segments. Active segment is
  highlighted; pending segments are dimmed; done are collapsed under a
  disclosure ("Show N completed").
- `Sources/Moves/Views/Window/ThreadDetail/SegmentDetail.swift` — body
  Markdown (reuses `MarkdownEditorView`), built-in move, generated
  checklist items, optional due/scheduled dates and estimate.
- `Sources/Moves/Views/Flows/CompleteSegmentSheet.swift` — explicit
  "Mark Segment Done" flow per §5.5: rough-time prompt, no breadcrumb
  required, advances to next pending segment.
- `Sources/Moves/Services/MarkdownImportService.swift` — parser
  implementing §9 exactly: YAML frontmatter for thread metadata, `## `
  H2 segments, `key: value` lines until first blank line, `move:`,
  `- [ ] …` items, residual content → `body_markdown`. Idempotency
  deferred: v1 is create-only (§9 rule 10).
- Import UI: `Sources/Moves/Views/Window/Import/ImportMarkdownView.swift`
  — drag-drop or file-picker target; preview parsed thread + segments
  before commit.
- `Sources/Moves/Services/TimeLogService.swift` —
  `roughLog(threadID, segmentID?, minutes)`; aggregations by ISO week
  via `time_log.week_start`. Pure projections, the repo holds rows.
- `Sources/Moves/Views/Window/TimeLog/WeeklyView.swift` — §14 weekly
  layout: one row per thread, `~Nh` aggregate, current ISO week + week
  selector.
- `MoveResolver` updates: regimented threads with no breadcrumb fall
  through to active-segment's `built_in_move`, then to the first pending
  segment's `built_in_move` (§11 rules 2–3, already designed in phase 1).

## Decisions

- **Segment advancement is never implicit (§5.5).** Switching, parking,
  and stopping leave segments untouched.
- **Import is create-only in v1.** Re-importing a thread with the same
  title produces a new thread; the UI warns. Idempotent updates are a
  v2 candidate.
- **YAML parsing:** small built-in parser, not a dependency. The
  supported keys are exactly those in §9 ("Supported frontmatter" /
  "Supported segment metadata"); anything else is ignored with a warning
  in the import preview.
- **Week boundary:** ISO weeks (Monday-start). `week_start` stored as
  `YYYY-MM-DD` of the Monday.

## Out of scope

- Recurring segments / cron-style scheduling (v2+).
- Re-import / merge (v2 candidate per §19).
- Per-day minute-level time tracking (§14 explicitly: rough only).
- Productivity scores / streaks (§2.5, §21).

## Definition of done

- Importing the §9 example Markdown produces a regimented thread with
  two segments, the first active, all checkboxes as `items`.
- Completing the active segment via the sheet logs rough time, marks
  done, advances to next pending. Popover (phase 3) updates its
  Available move accordingly.
- Weekly view aggregates across multiple stop/switch logs from earlier
  in the week.
- Segment lifecycle survives relaunch.

## Open questions

- Built-in move display when a regimented thread's breadcrumb is empty:
  show "Next: <built-in move>" vs "<built-in move>" alone? Lean toward
  the former for consistency with the §4.1 popover example.
- YAML library decision: keep tiny built-in parser, or pull in
  Yams? Default to built-in; the §9 schema is small. Revisit only if
  we hit edge cases.
