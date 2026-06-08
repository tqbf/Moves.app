# Moves — Plan Index

Moves is a macOS menu-bar app for **resuming important threads of work**.
The product spec lives in [`INITIAL-PLAN.md`](INITIAL-PLAN.md); this file is
the table of contents over the phased build plan. Running log of what's
shipped is in [`PROGRESS.md`](PROGRESS.md).

> **One-sentence pitch (INITIAL-PLAN §23):** A passive macOS menu-bar app
> that helps you stop wasting time by quickly resuming one important
> thread of work, while also handling lightweight reminders and deadlines
> without turning into a generic GTD system.

## Phase index

Each row is a self-contained deliverable. Phases are roughly equal in size
and ordered by dependency. Click into a plan for the full breakdown
(deliverables, decisions, out-of-scope, definition of done).

| Phase | File | One-liner | Lands these files / services | Spec sections |
|------:|------|-----------|------------------------------|---------------|
| 0 | (shipped — see [`PROGRESS.md`](PROGRESS.md)) | Hello-world menubar + window + SQLite skeleton, build pipeline. | `MovesApp`, hello-world `Move`, `Makefile`, `build.sh`. | — |
| 1 | [`plans/phase-1-domain-and-persistence.md`](plans/phase-1-domain-and-persistence.md) | Real domain & SQLite schema; replaces the hello-world model. **Refactor-heavy, no new UX.** | `Database` w/ WAL+migrations, `Persistence/Repositories/*`, `Domain/{Thread,Segment,Item,Alert,CurrentState,TimeLogEntry}`, `MoveResolver`, `AppStore`. | §3, §10, §11, §17 |
| 2 | [`plans/phase-2-capture-and-reminders.md`](plans/phase-2-capture-and-reminders.md) | Global capture hotkey, deterministic date parser, macOS notifications + snooze, due/overdue badge. | `CaptureParser`, `ReminderScheduler`, `NotificationDelegate`, `CapturePaletteView`, KeyboardShortcuts dep. | §4.4, §5.6–§5.7, §8, §13, §15, §16 |
| 3 | [`plans/phase-3-menu-bar-popover.md`](plans/phase-3-menu-bar-popover.md) | **The daily-driver UI.** Current/Upcoming/Available/Captured popover, Stop/Switch/Park flows with breadcrumb + rough-time. | `MenuPopoverView`, `{Current,Upcoming,Available,Captured}Section`, `HeadroomService`, `{Stop,Switch,Park}Sheet`, `RoughTimePicker`. | §2.1–§2.10, §4.1, §5.1–§5.5, §11, §12, §14, §22 |
| 4 | [`plans/phase-4-main-window-and-threads.md`](plans/phase-4-main-window-and-threads.md) | Real main window (Available / Current / Threads / Captured / Deadlines / Parking Lot / Settings), thread detail with Markdown editor, working-hours visibility. | `RootWindow`, `{Available,ThreadsList,Captured,Deadlines,ParkingLot}View`, `ThreadDetailView`, `MarkdownEditorView`, `WorkingHoursService`, `SettingsView`. | §2.9, §4.2, §4.3, §6, §12, §13 |
| 5 | [`plans/phase-5-regimented-and-time-log.md`](plans/phase-5-regimented-and-time-log.md) | Regimented threads end-to-end: segment lifecycle, explicit completion, Markdown import (YAML + H2), weekly rough-time view. | `SegmentsPanel`, `SegmentDetail`, `CompleteSegmentSheet`, `MarkdownImportService`, `ImportMarkdownView`, `TimeLogService`, `WeeklyView`. | §2.11, §3 (Segment), §5.5, §9, §14 |
| 6 | [`plans/phase-6-export-polish-release.md`](plans/phase-6-export-polish-release.md) | Backup/export, launch-time alert reconciliation, settings completion, onboarding, notarization pipeline restored. **Polish-only; no new product features.** | `ExportService`, `AlertReconciliation`, `OnboardingView`, `ExportSection`, notarization Makefile targets. | §8.4, §16, §17, §18 |

## Cross-cutting constraints (don't drift)

These come from INITIAL-PLAN.md but are easy to forget mid-phase. Re-read
the linked sections before adding anything in the area:

- **No priority theater** — deadlines are the only urgency signal.
  No low/medium/high. (§2.3, §21)
- **No taxonomy creep** — no Areas, tags, contexts, multilevel hierarchy.
  The model is Thread / Segment / Item. Full stop. (§2.9, §21)
- **No discipline / no shame** — no idle detection, streaks, scores,
  monitoring, moralizing copy. (§2.5, §21)
- **No precise time tracking** — rough buckets only:
  none/15m/30m/45m/1h/2h/3h+. (§14, §21)
- **No LLM parsing** — Markdown import and capture grammar are
  deterministic. (§9, §15, §21)
- **Core invariant:** a thread appears in Available iff it has a
  re-entry point (breadcrumb / active segment move / next segment move
  / open item). (§22)

## Where things live in this repo

```
moves/
├── INITIAL-PLAN.md          # the product spec; source of truth for §refs
├── PLAN.md                  # ← you are here (TOC)
├── PROGRESS.md              # running log of what's shipped
├── PROBLEMS.md              # known issues / parking lot for build problems
├── plans/                   # one file per phase, format is consistent
│   ├── phase-1-domain-and-persistence.md
│   ├── phase-2-capture-and-reminders.md
│   ├── phase-3-menu-bar-popover.md
│   ├── phase-4-main-window-and-threads.md
│   ├── phase-5-regimented-and-time-log.md
│   └── phase-6-export-polish-release.md
├── Sources/Moves/           # SwiftPM target
├── Package.swift            # macOS 14+, links libsqlite3
├── Makefile + build.sh      # swift build → .app bundle → codesign
└── Moves/Moves.entitlements
```

## Plan-file format

Each `plans/phase-N-*.md` follows the same shape so they stay skim-able:

1. **Goal** — one paragraph.
2. **Reads:** INITIAL-PLAN.md section numbers (so you know what to
   re-read before working in this phase).
3. **Builds on:** prior phases this depends on.
4. **Deliverables** — concrete files + what they do.
5. **Decisions** — calls made up-front so future work doesn't relitigate.
6. **Out of scope** — what NOT to build here.
7. **Definition of done** — observable acceptance criteria.
8. **Open questions** — calls we're punting.

If you add a new plan, follow this format and add a row to the phase
index above.
