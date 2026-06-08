# Phase 1 — Domain & persistence

**Goal:** Replace the hello-world `Move` model with the real domain — Threads,
Segments, Items, Alerts, CurrentState, TimeLog, Settings — and the SQLite
infrastructure those rest on. No new product UI in this phase; existing
sidebar/detail views are temporarily adapted to drive threads so we can keep
exercising the code end-to-end.

**Reads:** INITIAL-PLAN.md §3 (vocabulary), §10 (schema), §11 (move
resolution invariants), §17 (architecture / persistence).

**Builds on:** Phase 0 (the hello-world skeleton already in `main`).

## Deliverables

- `Sources/Moves/Persistence/`
  - `Database.swift` — replaces the current actor. Opens with WAL, runs
    migrations, exposes a connection to repositories.
  - `Migrations.swift` — explicit `[Migration]` array; v1 creates every
    table in INITIAL-PLAN.md §10 + indexes from the same section. The
    existing `moves` table is dropped (no preserved data — phase 0 was a
    throwaway).
  - `Repositories/` — `ThreadRepository`, `SegmentRepository`,
    `ItemRepository`, `AlertRepository`, `CurrentStateRepository`,
    `TimeLogRepository`, `SettingsRepository`. Each owns its prepared
    statements and returns domain values.
- `Sources/Moves/Domain/`
  - `Thread.swift`, `Segment.swift`, `Item.swift`, `Alert.swift`,
    `CurrentState.swift`, `TimeLogEntry.swift` — value types with the
    enums from §10 (`ThreadStatus`, `ThreadKind`, `Visibility`,
    `SegmentStatus`, `ItemKind`, `ItemStatus`, `DueKind`,
    `InterruptionKind`).
  - `MoveResolver.swift` — pure function over a Thread + its
    segments/items, returning the displayed re-entry move per §11. Used
    later by the popover; lives here because it's domain logic.
- `Sources/Moves/Model/AppStore.swift` — successor to `MovesStore`.
  `@Observable @MainActor`, composes the repos, exposes the slices the
  current UI needs. Existing `MovesStore.swift` is deleted along with
  `Move.swift`.
- Existing views (`MainView`, `MoveRow`, `MoveDetail`, `MenuBarContent`)
  rewired to read threads. Treat this as throwaway plumbing — phases 3/4
  replace these views entirely.

## Decisions

- **Timestamps:** integer Unix seconds. One column type to bind, no parsing,
  matches SQLite's storage class semantics. (§10 said "pick one.")
- **SQLite access:** continue with raw `libsqlite3`. Adding GRDB is a
  not-now decision — the domain is small enough that raw works, and
  we already have the linker setting + `SQLITE_TRANSIENT` plumbing.
  Revisit if statement boilerplate becomes a tax.
- **IDs:** UUID strings, generated client-side.
- **Concurrency:** keep `Database` as an `actor`. Each repository is a
  small struct that takes the actor and runs its statements via
  `await db.exec { ... }`-style helpers.

## Out of scope

- Capture parsing, notifications, hotkey (phase 2).
- The real menubar popover (phase 3).
- Markdown editor / thread-detail UI (phase 4).
- Segment lifecycle UI / Markdown import (phase 5).
- Export, notarization (phase 6).

## Definition of done

- `make check` clean.
- Launching the app creates the new schema; `sqlite3
  ~/Library/Application\ Support/Moves/moves.sqlite3 .schema` shows every
  table from §10.
- Manually inserting a Thread + open Item via the repos and relaunching
  the app surfaces it in the (placeholder) sidebar.
- Unit-style sanity script (one-off Swift file or `make test` target) that
  exercises insert/update/delete round-trips on each repo.

## Open questions

- Should `MoveResolver` live in `Domain/` (pure) or in a `Services/`
  folder we'd introduce later? Tentatively pure → `Domain/`. If it grows
  IO dependencies (e.g. working-hours filtering), move it.
- Repo error type — one shared `PersistenceError` or per-repo? Default to
  one shared until it becomes unwieldy.
