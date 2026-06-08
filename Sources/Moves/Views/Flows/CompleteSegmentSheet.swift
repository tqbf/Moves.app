import SwiftUI

/// "Mark Segment Done" sheet from INITIAL-PLAN §5.5. Logs rough time
/// attributed to the active (thread, segment) pair, marks the segment done,
/// and advances to the next pending segment. No breadcrumb prompt — this
/// flow is segment advancement, not thread switching.
///
/// Hosted as its own `Window` scene for the same reason Stop/Switch/Park
/// are: `MenuBarExtra` popovers auto-dismiss on focus loss, which would
/// kill a SwiftUI `.sheet`'s host. Reads `AppStore.pendingFlow` on appear
/// and self-dismisses on stale state per the Phase-3 gate lesson.
struct CompleteSegmentSheet: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismissWindow) private var dismissWindow

  @State private var rough: RoughTimeBucket = .none
  @State private var resolvedThreadId: String?
  @State private var resolvedSegmentId: String?
  @State private var resolvedThreadTitle: String = ""
  @State private var resolvedSegmentTitle: String = ""

  var body: some View {
    FlowSheetChrome(
      title: title,
      subtitle: "Logs rough time against this segment and advances to the next pending segment.",
      primary: "Mark Done",
      onPrimary: confirm,
      onCancel: cancel,
      content: {
        VStack(alignment: .leading, spacing: 14) {
          if !resolvedSegmentTitle.isEmpty {
            HStack(spacing: 6) {
              Image(systemName: "circle.dashed.inset.filled")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
              Text(resolvedSegmentTitle)
                .font(.system(size: 13, weight: .medium))
            }
          }
          VStack(alignment: .leading, spacing: 6) {
            Text("Rough time")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.secondary)
            RoughTimePicker(selection: $rough)
          }
        }
      }
    )
    .onAppear(perform: prefill)
  }

  private var title: String {
    resolvedThreadTitle.isEmpty
      ? "Mark Segment Done"
      : "Mark segment done on \(resolvedThreadTitle)"
  }

  // MARK: - Actions

  private func prefill() {
    rough = .none
    guard case let .completeSegment(threadId, segmentId) = store.pendingFlow,
          let thread = store.thread(id: threadId) else {
      // Phase-3 gate lesson: Window scenes restore on launch even when we
      // didn't open them. If pendingFlow doesn't match the expected case,
      // self-dismiss rather than showing an empty sheet.
      resolvedThreadId = nil
      resolvedSegmentId = nil
      resolvedThreadTitle = ""
      resolvedSegmentTitle = ""
      dismissWindow(id: PopoverWindowID.completeSegment.rawValue)
      return
    }
    resolvedThreadId = thread.id
    resolvedSegmentId = segmentId
    resolvedThreadTitle = thread.title
    resolvedSegmentTitle = store.segmentsByThread[thread.id]?.first(where: { $0.id == segmentId })?.title ?? ""
  }

  private func confirm() {
    // Phase-3 gate lesson: read the active segment fresh from the store
    // inside the closure rather than capturing it. The user can navigate
    // away between sheet open and click — re-resolve at click time.
    Task {
      guard let threadId = resolvedThreadId,
            let thread = store.thread(id: threadId) else {
        finish()
        return
      }
      await store.completeActiveSegment(thread: thread, rough: rough)
      finish()
    }
  }

  private func cancel() { finish() }

  private func finish() {
    store.pendingFlow = nil
    dismissWindow(id: PopoverWindowID.completeSegment.rawValue)
  }
}
