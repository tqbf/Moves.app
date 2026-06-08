import AppKit
import Observation
import SwiftUI

/// Singleton coordinator for the onboarding sheet. Phase 6 ships onboarding
/// as a separate `Window` scene (same idiom as the Phase-3 flow sheets) so
/// it survives the menubar popover dismissing on focus loss and so it can
/// be requested from app launch (before any view tree has mounted).
///
/// The presenter exposes a single `presentRequested` flag that any view
/// observing it can watch with `.onChange`. The window scene observes it
/// and opens itself on transitions to `true`; the onboarding view sets it
/// back to `false` on dismiss.
@Observable
@MainActor
final class OnboardingPresenter {
  static let shared = OnboardingPresenter()

  private(set) var presentRequested: Bool = false

  private init() {}

  func requestPresent() {
    presentRequested = true
  }

  func dismiss() {
    presentRequested = false
  }
}
