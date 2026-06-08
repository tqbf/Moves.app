import SwiftUI

/// "Parking <thread>" sheet from INITIAL-PLAN §5.4. Breadcrumb-only —
/// no rough-time picker, because parking is not stopping (Phase 3
/// decision). Park is emotionally cheap (§2.8); the sheet should feel
/// like the lightest of the three modals.
///
/// Hosted in its own `Window` scene; see `StopSheet` for the rationale.
struct ParkSheet: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismissWindow) private var dismissWindow

  @State private var breadcrumb: String = ""
  @State private var resolvedThread: Thread?

  var body: some View {
    FlowSheetChrome(
      title: title,
      subtitle: "Leave a note so future-you can pick this up.",
      primary: "Park",
      onPrimary: confirm,
      onCancel: cancel,
      content: { field }
    )
    .onAppear(perform: prefill)
  }

  private var title: String { "Parking \(resolvedThread?.title ?? "thread")" }

  private var field: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Breadcrumb")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
      TextEditor(text: $breadcrumb)
        .font(.system(size: 13))
        .frame(minHeight: 80, maxHeight: 140)
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
    guard case let .park(threadId) = store.pendingFlow,
          let thread = store.thread(id: threadId)
    else {
      // See StopSheet.prefill — guard against SwiftUI scene restoration.
      resolvedThread = nil
      breadcrumb = ""
      dismissWindow(id: PopoverWindowID.park.rawValue)
      return
    }
    resolvedThread = thread
    breadcrumb = thread.breadcrumb
  }

  private func confirm() {
    guard let thread = resolvedThread else { return }
    Task {
      await store.park(thread, breadcrumb: breadcrumb)
      finish()
    }
  }

  private func cancel() { finish() }

  private func finish() {
    store.pendingFlow = nil
    dismissWindow(id: PopoverWindowID.park.rawValue)
  }
}
