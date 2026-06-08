# Phase 6 — Export, polish, release

**Goal:** Take v1 from "feature-complete" to "shippable." Backup/export,
launch-time reconciliation, settings completion, onboarding, and the
notarization pipeline.

**Reads:** INITIAL-PLAN.md §8.4 (notification reconciliation), §16
(badge), §17 (technical architecture, "on app launch, reconcile pending
alerts with database state"), §18 (must-have: export/import), §21
(anti-patterns to keep absent during polish).

**Builds on:** Phases 1–5.

## Deliverables

- `Sources/Moves/Services/ExportService.swift`:
  - **SQLite snapshot:** `VACUUM INTO` to a chosen path.
  - **Markdown bundle:** one `.md` per thread (frontmatter +
    `## segments`), one `captured.md` for orphan items, one `time-log.csv`.
    Round-trippable with `MarkdownImportService` (phase 5) for
    regimented threads.
- `Sources/Moves/Views/Window/Settings/ExportSection.swift` — buttons
  for snapshot + Markdown bundle, with destination picker.
- `Sources/Moves/Services/AlertReconciliation.swift` — on app launch:
  cancel notifications whose Items are done/canceled, schedule missing
  ones for open items whose `due_at` is in the future, fire-and-mark any
  hard items whose `due_at` is already past.
- Settings additions: default alert offsets per
  `kind` (reminder vs deadline task), badge enable/disable toggle.
- `Sources/Moves/Views/Onboarding/OnboardingView.swift` — short modal,
  three panes max: (1) what this app is for, (2) capture hotkey
  registration, (3) try a capture. Per macos-design skill: teach
  shortcuts through doing, not reading.
- Accessibility pass: VoiceOver labels on every icon button, Dynamic
  Type respected in the popover, reduce-motion honored on the symbol
  bounce. Run the `swiftui-pro` skill review on the final tree.
- Build pipeline: restore the notarization targets from
  `Makefile.example` (`dist`, `notary-setup`, `sign`, `notarize`,
  `staple`, `verify-release`, `github-release`). Adapt entitlements as
  needed for hardened runtime; switch from ad-hoc/dev sign to Developer
  ID for `make dist`.

## Decisions

- **Export format:** SQLite snapshot is the canonical backup; Markdown
  bundle is the human-readable variant. Both are offered; the user
  picks per use case.
- **Reconciliation policy:** on launch we trust the DB. Anything
  scheduled in `UNUserNotificationCenter` that isn't reflected in
  `alerts.fired_at IS NULL` is canceled.
- **Onboarding trigger:** first launch only (a `settings`
  `onboarded_version` row). Re-runnable from Settings.
- **No new product features in this phase.** Polish-only. If a deferral
  surfaces from earlier phases, that gets a separate plan file, not a
  bolt-on here.

## Out of scope

- Sync / multi-device (v3 per §20).
- Recurring reminders, calendar integration (v2 candidates).
- Tags / areas / priorities (forbidden — §2.3, §2.9).

## Definition of done

- Cold launch with notifications already pending: badge count matches
  DB, no orphan scheduled notifications.
- `make dist` from a clean checkout on a `vX.Y.Z` tag produces a
  notarized, stapled, zipped `Moves-X.Y.Z-macos.zip` that passes
  `spctl --assess`.
- Onboarding completes in <60s and ends with the user having captured
  one real item.
- VoiceOver navigation reaches every primary action.

## Open questions

- Where do we keep the "what's new in this version" string for future
  onboarding re-runs? Lean toward a `CHANGELOG.md` parsed on demand —
  no DB table.
- Default alert offsets for deadline tasks: §8.3 suggests "morning of, 1
  hour before, at due time." Ship those; expose a Settings editor.
