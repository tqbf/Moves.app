import SwiftUI

/// "Stopping <thread>" sheet from INITIAL-PLAN §5.2. Prefilled breadcrumb,
/// optional rough-time bucket, "Park instead" escape hatch.
///
/// Hosted in its own `Window` scene (not a SwiftUI `.sheet`) because the
/// menu-bar popover auto-dismisses on focus loss — a SwiftUI sheet would
/// die with its host. Reads `AppStore.pendingFlow` on appear to figure out
/// which thread we're stopping.
struct StopSheet: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismissWindow) private var dismissWindow

  @State private var breadcrumb: String = ""
  @State private var rough: RoughTimeBucket = .none
  @State private var resolvedThread: Thread?

  var body: some View {
    FlowSheetChrome(
      title: title,
      subtitle: "Save where you are. Pick rough time if you feel like it.",
      primary: "Stop",
      onPrimary: confirm,
      onCancel: cancel,
      content: {
        VStack(alignment: .leading, spacing: 14) {
          field

          VStack(alignment: .leading, spacing: 6) {
            Text("Rough time")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.secondary)
            RoughTimePicker(selection: $rough)
          }
        }
      },
      trailingButtons: {
        Button("Park instead", action: parkInstead)
      }
    )
    .onAppear(perform: prefill)
  }

  private var title: String {
    "Stopping \(resolvedThread?.title ?? "thread")"
  }

  private var field: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Breadcrumb")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
      TextEditor(text: $breadcrumb)
        .font(.system(size: 13))
        .frame(minHeight: 70, maxHeight: 120)
        .padding(6)
        .background(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
  }

  // MARK: - Actions

  private func prefill() {
    guard case let .stop(threadId) = store.pendingFlow,
          let thread = store.thread(id: threadId)
    else { return }
    resolvedThread = thread
    breadcrumb = thread.breadcrumb
    rough = .none
  }

  private func confirm() {
    Task {
      await store.stop(breadcrumb: breadcrumb, rough: rough)
      finish()
    }
  }

  private func parkInstead() {
    guard let thread = resolvedThread else { return }
    Task {
      await store.park(thread, breadcrumb: breadcrumb)
      finish()
    }
  }

  private func cancel() { finish() }

  private func finish() {
    store.pendingFlow = nil
    dismissWindow(id: PopoverWindowID.stop.rawValue)
  }
}
