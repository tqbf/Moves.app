import SwiftUI

/// Window-scene host for `OnboardingView`. Follows the Phase-3 sheet idiom:
/// if SwiftUI restores this window on app launch without the presenter
/// flag set, the host dismisses itself rather than presenting an
/// out-of-context onboarding panel. The bootstrap flow (or the Settings
/// "Show onboarding again" button) flips the flag, the RootWindow's
/// observer calls `openWindow(id:)`, and this host renders.
struct OnboardingHost: View {
  @Environment(\.dismissWindow) private var dismissWindow

  /// Observe the shared signal bus directly; the host doesn't need any
  /// other parent state.
  @Bindable var signals = AppSignals.shared

  var body: some View {
    Group {
      if signals.presentOnboarding {
        OnboardingView()
      } else {
        // SwiftUI restored this scene without the presenter flag —
        // dismiss to avoid an empty onboarding window. Matches the
        // Phase-3 Stop/Switch/Park self-dismiss-on-stale idiom.
        Color.clear
          .frame(width: 1, height: 1)
          .onAppear {
            dismissWindow(id: PopoverWindowID.onboarding.rawValue)
          }
      }
    }
  }
}
