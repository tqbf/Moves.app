# Moves — Known Problems

Open issues, dirty workarounds, and follow-ups that aren't in a phase
plan. Newest first.

## 2026-06-09 — SwiftUI insertion-with-transition crashes constraint engine on macOS 14.4

**Symptom.** App throws an `NSInternalInconsistencyException` from
`-[NSWindow _postWindowNeedsUpdateConstraintsUnlessPostingDisabled]`
during a layout pass. The stack shows ~12 frames of recursive
`-[NSView _informContainerThatSubviewsNeedUpdateConstraints]` calls
ending in SwiftUI's `OUTLINED_FUNCTION_4 + 30484` / `+ 98748`. Hit
twice during the UI glow-up (PR #3): once on first launch, then again
on clicking the Available pane's inspector reveal affordance.

**Root cause.** The pattern

```swift
if isVisible {
    SomeView()
        .transition(.move(edge: .trailing).combined(with: .opacity))
}
```

inserts or removes the view with a transition. Because the SwiftUI
hierarchy in a `Window` scene nested in `NavigationSplitView` is
hosted inside an `_NSConstraintBasedLayoutHostingView` chain, the
mid-transition insertion fires `setNeedsUpdateConstraints` from inside
the active update-constraints pass. AppKit's "view modified during
update" guard then throws. The same pattern works on some Macs and not
others — the constraint engine's strictness varies by hardware and
isn't debuggable from the SwiftUI side.

Related triggers seen in the same PR:

- `Spacer()` as the leading child of
  `ToolbarItemGroup(placement: .primaryAction)` — redundant given the
  trailing placement, and confuses the toolbar's intrinsic content
  size computation. Removed.
- `SettingsLink` hosted inside `safeAreaInset(edge: .bottom)` on a
  `List` — its private NSHostingView shim has the same constraint
  invalidation side effect. Replaced with
  `Environment(\.openSettings)` driving a plain `Button`.

**Workarounds.**

- For inspector-style reveal: always-mount the view and animate
  `.frame(width: isVisible ? W : 0).clipped()` instead of using
  insertion + transition. Pattern lives in
  `Sources/Moves/Views/Window/InspectorColumn.swift` (since gutted —
  see 2026-06-09 PR #3 followup that removed the affordance entirely
  on Thomas's call).
- For toolbars: never lead a `ToolbarItemGroup` with `Spacer()` if the
  placement already trails. Use `.primaryAction` or `.cancellationAction`
  directly.
- For programmatic Settings: `@Environment(\.openSettings)` reaches
  the SwiftUI `Settings { }` scene without the constraint hazard.
  Tradeoff: it can't pre-select a tab the way `SettingsLink` can.

**Heads-up for future code.** Any time a view's visibility is driven
by a Bool with a transition, look critically — the safe pattern on
macOS 14.x is animate-a-dimension, not insert-with-motion. Same for
`.matchedGeometryEffect`-based reveals near constraint-hosted views.

## 2026-06-08 — SwiftPM `Bundle.module` placement (workaround in `MovesApp.init`)

**Symptom.** On macOS 14, the app crashes the first time the
KeyboardShortcuts recorder is rendered (onboarding step 2 or the
capture-hotkey Settings row). The crash is a `Bundle.module`
assertion-failure from inside KeyboardShortcuts:

```
0  _assertionFailure(...)
1  closure #1 in variable initialization expression of static NSBundle.module
6  String.localized.getter
7  KeyboardShortcuts.RecorderCocoa.init(for:onChange:)
```

**Root cause.** SwiftPM (Swift 6.3 / Xcode 26) generates the
`Bundle.module` accessor as:

```swift
let mainPath = Bundle.main.bundleURL
                  .appendingPathComponent("<Name>.bundle").path
let buildPath = "<absolute build-time path>"
let preferredBundle = Bundle(path: mainPath)
guard let bundle = preferredBundle ?? Bundle(path: buildPath) else { ... }
```

`Bundle.main.bundleURL` for a macOS .app is the .app DIRECTORY itself,
not `Contents/Resources/`. So `mainPath` resolves to
`Moves.app/<Name>.bundle` — the top of the .app. The `buildPath`
fallback is the absolute path the file lived at on the *dev* machine
(`/Users/agentzero/codebase/moves/.build/...`), which the binary
embeds verbatim. That fallback masks the placement bug on the build
host because `.build/` is right there. As soon as the .app is copied
off-box (the user's "build on macOS 26, copy via SMB, run on macOS 14"
workflow), the fallback path doesn't exist either, and the closure
trips its `fatalError`.

**Why we can't just put the bundle at the .app root.** `codesign`
refuses to seal arbitrary content at an .app's bundle root:

```
build/Moves.app: unsealed contents present in the bundle root
```

The bundle MUST live under `Contents/`. Symlinks at the root also trip
this check — codesign records them as unsealed top-level content too.

**Why we can't patch the generated accessor at build time.** SwiftPM
regenerates `resource_bundle_accessor.swift` on every compile,
including the relink-after-patch step. We tried; the patch is
overwritten before the binary is produced.

**Workaround.** `MovesApp.init()` runs before any view is constructed,
which means before any `Bundle.module` access. It walks
`Contents/Resources/` for `.bundle` directories and creates a relative
symlink at the .app root for each:

```
Moves.app/<Name>.bundle → Contents/Resources/<Name>.bundle
```

`Bundle(path: mainPath)` follows the symlink to the real bundle inside
`Contents/Resources/` and succeeds. The symlinks aren't part of the
codesign seal — created at runtime, not build time — so codesign stays
happy at build time and the user's signature stays valid at launch.

`build.sh` also rewrites the nested bundle's `Info.plist` with the
minimum keys macOS 14's `Bundle(path:)` requires (`CFBundleIdentifier`,
`CFBundlePackageType=BNDL`, `CFBundleInfoDictionaryVersion`,
`CFBundleName`, `CFBundleVersion`). SwiftPM emits just
`CFBundleDevelopmentRegion`, which macOS 15+ accepts and macOS 14
rejects as "not a bundle."

**Follow-up: `make dist` will break.** This workaround relies on
runtime mutation of the .app bundle directory (creating the symlink).
Hardened runtime + notarized release builds re-verify bundle integrity
at every launch; on a notarized build the symlink creation will either
fail silently (if the .app is in a read-only location like
`/Applications/`) or trip a launch-time integrity check.

Before shipping `make dist`, choose one:
1. Vendor `KeyboardShortcuts`'s `resource_bundle_accessor.swift` and
   ship a patched copy that looks at `Contents/Resources/` directly.
2. Write a SwiftPM build-tool plugin that intercepts the resource
   accessor generation and emits the patched version.
3. Move all of KeyboardShortcuts's localized strings into our own
   target's resources and stub out `String.localized`.

The Phase 6 plan now references this; track that work there.

**Files.**
- `Sources/Moves/MovesApp.swift` — `init()` performs the symlink dance.
- `build.sh` — rewrites the nested Info.plist after copying the bundle
  into `Contents/Resources/`.

**Commits.** `0737b92` (copy bundle), `56f0d2b` (codesign nested
bundle), `185afb2` (rewrite Info.plist for macOS 14), `50fe4eb`
(runtime symlink — the actual fix).
