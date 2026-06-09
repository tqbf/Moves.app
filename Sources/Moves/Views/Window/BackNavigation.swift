import SwiftUI

/// Cross-scope wiring for the macOS "back" convention (Cmd-[) on the main
/// window. The actual selection state lives in `RootWindow` as `@State`,
/// but the menu item belongs at App scope under View → "Back to Threads"
/// so it shows up in the menu bar and gets the standard discoverability +
/// disabled-when-N/A treatment for free.
///
/// We bridge the two with `.focusedSceneValue`: RootWindow publishes a
/// `BackAction` while the user is on a `.thread(id)` selection, and the
/// App-scope `CommandGroup` reads it via `@FocusedValue`. When no thread
/// is selected (or the main window isn't key), the value is nil and the
/// menu item disables itself — exactly the behavior the §4.2 sibling
/// destinations want ("no-op everywhere else").
///
/// We intentionally do NOT model a generic browser-history stack — only
/// the single thread-detail → threads-list relationship is meaningful
/// per the task spec.
struct BackAction {
  /// Invoked by the View-menu button. Pops the sidebar selection from
  /// `.thread(_)` back to `.threadsList`. Caller is responsible for only
  /// publishing this when the pop is meaningful (i.e. the user is on a
  /// thread detail pane).
  let run: () -> Void
}

/// `FocusedValueKey` for the back action. We use the legacy key/extension
/// pattern (not the `@Entry` macro) because the deployment target is
/// macOS 14 — `@Entry` requires macOS 15+.
private struct BackFromThreadFocusKey: FocusedValueKey {
  typealias Value = BackAction
}

extension FocusedValues {
  /// Published by `RootWindow` while a thread is selected; read by the
  /// App-scope "Back to Threads" command. Nil means the menu item should
  /// be disabled.
  var backFromThread: BackAction? {
    get { self[BackFromThreadFocusKey.self] }
    set { self[BackFromThreadFocusKey.self] = newValue }
  }
}

/// View → "Back to Threads" menu item with Cmd-[ shortcut. Lives in its
/// own View so `@FocusedValue` resolves (property wrappers don't work
/// directly inside a `CommandGroup` closure — that closure is a
/// `@CommandsBuilder`, not a view body). The button disables itself when
/// no thread is selected, which is also when SwiftUI auto-disables the
/// shortcut — so Cmd-[ becomes a no-op on the other panes without us
/// having to swallow it explicitly.
struct BackToThreadsCommand: View {
  @FocusedValue(\.backFromThread) private var back

  var body: some View {
    Button("Back to Threads") { back?.run() }
      .keyboardShortcut("[", modifiers: [.command])
      .disabled(back == nil)
  }
}
