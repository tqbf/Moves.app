# Moves — Progress Log

Newest first.

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
