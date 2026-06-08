import Observation
import SwiftUI

/// Singleton coordinator for the "New thread" command (Cmd-N). The menu
/// command lives at App scope while the focus target lives inside the
/// `ThreadsListView`, several scenes away; the simplest cross-view signal
/// is the same `@Observable` flag pattern Phase 6 uses for
/// `OnboardingPresenter`.
///
/// Flow:
/// 1. `MovesApp`'s Cmd-N button activates the app and calls `request()`,
///    flipping `requestPending` true.
/// 2. `RootWindow` observes the flag and switches the sidebar to
///    `.threadsList`, but does NOT clear the flag — `ThreadsListView`
///    might not be on screen yet, so the focus signal would be lost.
/// 3. `ThreadsListView` observes the same flag and, on the true
///    transition (or via `onAppear` when it mounts after the switch),
///    focuses the inline "New thread…" field and calls `clear()`.
///
/// `request()` always passes through `requestPending = false` first so
/// repeated Cmd-N presses while the field is already focused still fire
/// the `.onChange` observer.
@Observable
@MainActor
final class NewThreadPresenter {
  static let shared = NewThreadPresenter()

  private(set) var requestPending: Bool = false

  private init() {}

  func request() {
    // Force a transition even if a previous request is still pending so
    // observers' `.onChange` fires every time the user hits Cmd-N.
    requestPending = false
    requestPending = true
  }

  func clear() {
    requestPending = false
  }
}
