import KeyboardShortcuts
import SwiftUI

/// Phase-6 Settings additions: badge toggle, capture-hotkey rebind, and
/// "Show onboarding again" button. Combined into one section because
/// they're all small render-or-flag preferences — splitting them into
/// three sections would inflate the chrome past their content.
struct BadgeAndOnboardingSection: View {
  @Environment(AppStore.self) private var store

  /// Local edit buffer for the badge toggle. We re-resolve preferences
  /// from the store at save time (Phase-5 gate idiom).
  @State private var badgeEnabled: Bool = true
  @State private var loaded: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeader("Menu bar & notifications")

      Toggle(isOn: $badgeEnabled) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Show due/overdue badge")
            .font(.callout)
          Text("Adds “•N” next to the menu bar icon and to the popover header.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .toggleStyle(.switch)
      .onChange(of: badgeEnabled) { _, _ in saveBadge() }

      HStack(spacing: 12) {
        Text("Capture shortcut")
          .font(.callout)
        KeyboardShortcuts.Recorder(for: .capture)
        Spacer()
      }

      Divider().padding(.vertical, 4)

      sectionHeader("Onboarding")
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Show onboarding again")
            .font(.callout)
          Text("Replays the 3-step welcome flow.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Show onboarding") {
          Task {
            await store.resetOnboarding()
            OnboardingPresenter.shared.requestPresent()
          }
        }
      }
    }
    .onAppear(perform: prefillIfNeeded)
  }

  private func prefillIfNeeded() {
    guard !loaded else { return }
    loaded = true
    badgeEnabled = store.preferences.badgeEnabled
  }

  private func saveBadge() {
    guard badgeEnabled != store.preferences.badgeEnabled else { return }
    Task {
      // Re-resolve preferences at write time so a concurrent alert-offset
      // save doesn't clobber the field we touched.
      var copy = store.preferences
      copy.badgeEnabled = badgeEnabled
      await store.saveUserPreferences(copy)
    }
  }
}
