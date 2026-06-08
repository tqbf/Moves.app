# Moves — Progress Log

Newest first.

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
