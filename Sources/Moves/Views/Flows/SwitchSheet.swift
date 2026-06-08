import SwiftUI

/// "Before switching from <thread>" sheet from INITIAL-PLAN §5.3. Prefilled
/// breadcrumb on the *previous* thread, optional rough-time bucket, and
/// a "Park <previous>" escape hatch.
///
/// Hosted in its own `Window` scene; see `StopSheet` for the rationale.
struct SwitchSheet: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismissWindow) private var dismissWindow

  @State private var breadcrumb: String = ""
  @State private var rough: RoughTimeBucket = .none
  @State private var previousThread: Thread?
  @State private var targetThread: Thread?

  var body: some View {
    FlowSheetChrome(
      title: title,
      subtitle: "Save your breadcrumb on \(previousTitle), then pick up \(targetTitle).",
      primary: "Switch to \(targetTitle)",
      onPrimary: confirm,
      onCancel: cancel,
      content: {
        VStack(alignment: .leading, spacing: 14) {
          field

          VStack(alignment: .leading, spacing: 6) {
            Text("Rough time on \(previousTitle)")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.secondary)
            RoughTimePicker(selection: $rough)
          }
        }
      },
      trailingButtons: {
        Button("Park \(previousTitle)", action: parkPrevious)
      }
    )
    .onAppear(perform: prefill)
  }

  private var title: String { "Before switching from \(previousTitle)" }
  private var previousTitle: String { previousThread?.title ?? "thread" }
  private var targetTitle: String { targetThread?.title ?? "next" }

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
    rough = .none
    guard case let .switch(fromId, toId) = store.pendingFlow else {
      // See StopSheet.prefill — guard against SwiftUI scene restoration.
      previousThread = nil
      targetThread = nil
      breadcrumb = ""
      dismissWindow(id: PopoverWindowID.switchFlow.rawValue)
      return
    }
    previousThread = store.thread(id: fromId)
    targetThread = store.thread(id: toId)
    breadcrumb = previousThread?.breadcrumb ?? ""
  }

  private func confirm() {
    guard let target = targetThread else { return }
    Task {
      await store.switchTo(target, breadcrumb: breadcrumb, rough: rough)
      finish()
    }
  }

  private func parkPrevious() {
    guard let previous = previousThread else { return }
    Task {
      await store.park(previous, breadcrumb: breadcrumb)
      finish()
    }
  }

  private func cancel() { finish() }

  private func finish() {
    store.pendingFlow = nil
    dismissWindow(id: PopoverWindowID.switchFlow.rawValue)
  }
}
