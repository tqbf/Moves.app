import AppKit
import Observation
import SwiftUI

/// Cross-scope signal bus for the few cases where an App-scope command or
/// the bootstrap path needs to nudge a View-scope observer that may not
/// be on screen yet. The pattern Phase 6 introduced for onboarding (a
/// singleton `@Observable` flag that one side flips and another watches
/// with `.onChange`) had multiplied by Phase 7 into two near-identical
/// singletons. They've been collapsed into named fields on one shared
/// signals object so the next "I need a flag" doesn't get a third
/// singleton.
///
/// Use sparingly. Most cross-view wiring should still flow through
/// `@FocusedValue` (see `BackNavigation.swift`) — that channel
/// auto-disables menu items when the publishing scope isn't active and
/// avoids global mutable state entirely. `AppSignals` is the fallback
/// for the "publisher needs to fire before the observer mounts" case
/// the focused-value bus can't model.
@Observable
@MainActor
final class AppSignals {
  static let shared = AppSignals()

  /// Flipped to true by `MovesApp.bootstrap` (first launch / version
  /// bump) or the Settings "Show onboarding again" button. The onboarding
  /// `Window` scene observes the flag and opens itself; the onboarding
  /// view flips it back to false on dismiss.
  private(set) var presentOnboarding: Bool = false

  /// Flipped to true by the App-scope Cmd-N command. `RootWindow`
  /// observes it and switches the sidebar to `.threadsList`;
  /// `ThreadsListView` observes it and focuses the inline "New thread…"
  /// field, then clears it.
  private(set) var requestNewThread: Bool = false

  private init() {}

  // MARK: - Onboarding

  func requestOnboarding() {
    presentOnboarding = true
  }

  func dismissOnboarding() {
    presentOnboarding = false
  }

  // MARK: - New thread

  /// Force a transition even if a previous request is still pending so
  /// observers' `.onChange` fires every time the user hits Cmd-N — keeps
  /// repeated presses re-focusing the field instead of no-oping when the
  /// flag is already set.
  func requestNewThreadFlow() {
    requestNewThread = false
    requestNewThread = true
  }

  func clearNewThreadRequest() {
    requestNewThread = false
  }
}
