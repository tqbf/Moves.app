import KeyboardShortcuts
import SwiftUI

/// First-launch onboarding (INITIAL-PLAN §18, Phase 6). Three panes max,
/// teaching the user the capture hotkey by doing — not by reading.
///
///   1. **What this app is for.** One-sentence pitch + a small mockup hint.
///   2. **Capture hotkey.** A `KeyboardShortcuts.Recorder` for `.capture`.
///      Default is ⌥Space; the user can rebind or accept.
///   3. **Try a capture.** A live, working capture field. Hitting Return
///      saves a real `Item`, which becomes the user's first captured row.
///
/// macos-design: progressive disclosure, native sheet chrome (Continue /
/// Back navigation), default action + cancel action on Return / Esc. The
/// completion marker is written via `AppStore.markOnboardingComplete()`
/// once the user finishes the last pane.
///
/// The sheet runs as its own `Window` scene (see `MovesApp`) because the
/// menubar popover would auto-dismiss this if we hosted it as a `.sheet`.
struct OnboardingView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismissWindow) private var dismissWindow
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var step: Step = .intro
  @State private var draft: String = ""
  @State private var didCapture: Bool = false

  enum Step: Int, CaseIterable {
    case intro
    case hotkey
    case capture

    var title: String {
      switch self {
      case .intro: return "Welcome to Moves"
      case .hotkey: return "Capture hotkey"
      case .capture: return "Try a capture"
      }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      content
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
      Divider()
      footer
    }
    .frame(width: 520)
    .background(.background)
    .onAppear {
      step = .intro
      draft = ""
      didCapture = false
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "figure.walk.motion")
        .font(.title2)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(step.title)
          .font(.title3)
          .fontWeight(.semibold)
        Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 16)
  }

  // MARK: - Content

  @ViewBuilder
  private var content: some View {
    let contentTransition: AnyTransition = reduceMotion
      ? .identity
      : .opacity.combined(with: .move(edge: .trailing))

    switch step {
    case .intro:
      introContent
        .transition(contentTransition)
    case .hotkey:
      hotkeyContent
        .transition(contentTransition)
    case .capture:
      captureContent
        .transition(contentTransition)
    }
  }

  private var introContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Resume the work that matters.")
        .font(.title2)
        .fontWeight(.semibold)
      Text("Moves lives in your menu bar. It quietly tracks which thread of work you’re on, what the next move is, and any lightweight reminders you capture along the way.")
        .font(.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      mockupPreview
        .padding(.top, 8)
    }
  }

  private var mockupPreview: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: "figure.walk.motion")
          .font(.caption)
        Text("Moves")
          .font(.caption)
          .fontWeight(.semibold)
        Spacer()
        Text("•2 due")
          .font(.caption2)
          .foregroundStyle(.orange)
      }
      Divider()
      Text("Current")
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
      Text("Ship Moves v1")
        .font(.callout)
        .fontWeight(.medium)
      Text("Next: revise onboarding copy")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
    )
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Sample menu-bar popover")
  }

  private var hotkeyContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Pick a shortcut for the capture palette.")
        .font(.title3)
        .fontWeight(.semibold)
      Text("Press the hotkey from anywhere on your Mac to drop in a thought. Default: ⌥Space. Click below to record your own.")
        .font(.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 12) {
        Text("Capture")
          .font(.callout)
        KeyboardShortcuts.Recorder(for: .capture)
      }
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor))
      )
      Text("You can change this any time in Settings.")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
  }

  private var captureContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Capture your first item.")
        .font(.title3)
        .fontWeight(.semibold)
      Text("Type something you don’t want to lose — a reminder, a task, anything. Hit Return to save it. A deadline is optional.")
        .font(.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      TextField("Try: pull rice in 18m", text: $draft)
        .textFieldStyle(.roundedBorder)
        .font(.title3)
        .onSubmit(saveFirstCapture)
        .disabled(didCapture)
        .accessibilityLabel("First capture")
      if didCapture {
        Label("Saved. Finishing up…", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .font(.callout)
      } else {
        Text("Press Return to save.")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
  }

  // MARK: - Footer

  private var footer: some View {
    HStack(spacing: 12) {
      Button("Skip") {
        Task { await finish() }
      }
      .accessibilityLabel("Skip onboarding")

      Spacer()

      if step.rawValue > 0 {
        Button("Back") {
          if let prev = Step(rawValue: step.rawValue - 1) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
              step = prev
            }
          }
        }
        .keyboardShortcut(.cancelAction)
      }

      Button(primaryActionLabel, action: primaryAction)
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(step == .capture && !didCapture)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 14)
  }

  private var primaryActionLabel: String {
    switch step {
    case .intro: return "Continue"
    case .hotkey: return "Continue"
    case .capture: return "Done"
    }
  }

  // MARK: - Actions

  private func primaryAction() {
    switch step {
    case .intro:
      withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
        step = .hotkey
      }
    case .hotkey:
      withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
        step = .capture
      }
    case .capture:
      Task { await finish() }
    }
  }

  private func saveFirstCapture() {
    let input = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty, !didCapture else { return }
    Task {
      _ = await store.capture(input)
      didCapture = true
      // Auto-advance after a brief dwell so the user sees the "Saved"
      // confirmation. Removes the "find the Done button" gap that made
      // the previous flow feel stuck for users who treated Return-to-save
      // as the natural end of this step.
      try? await Task.sleep(nanoseconds: 700_000_000)
      await finish()
    }
  }

  private func finish() async {
    await store.markOnboardingComplete()
    AppSignals.shared.dismissOnboarding()
    dismissWindow(id: PopoverWindowID.onboarding.rawValue)
  }
}
