import SwiftUI

/// The "Current" section of the popover (INITIAL-PLAN §4.1).
///
/// Shows the current thread's title, the segment line (if regimented), the
/// breadcrumb (the "Next:" line), and the Stop / Switch / Park action row.
/// When no thread is current, renders "Not working on anything" neutrally
/// (§2.6: zero current work is valid; no shame).
///
/// The Stop button has an `S`-key accelerator wired via
/// `.keyboardShortcut("s", modifiers: [])` and the hint is rendered inline
/// so users discover it (Phase 3 plan open question: yes, document inline).
struct CurrentSection: View {
  @Environment(AppStore.self) private var store
  @Environment(\.openWindow) private var openWindow

  /// Optional: the segment associated with the current thread, if known.
  /// We don't hit the DB on every render; the parent resolves this once.
  let currentSegment: Segment?

  var body: some View {
    PopoverSectionContainer(title: "Current") {
      if let thread = currentThread {
        activeContent(for: thread)
      } else {
        idleContent
      }
    }
  }

  // MARK: - States

  private var currentThread: Thread? {
    guard let id = store.current.threadId else { return nil }
    return store.thread(id: id)
  }

  private func activeContent(for thread: Thread) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(thread.title)
        .font(.system(size: 14, weight: .semibold))
        .lineLimit(1)

      if let segment = currentSegment {
        Text(segment.title)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      if !thread.breadcrumb.isEmpty {
        Text("Next: \(thread.breadcrumb)")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }

      actionRow(for: thread)
        .padding(.top, 2)
    }
  }

  private var idleContent: some View {
    Text("Not working on anything")
      .font(.system(size: 13))
      .foregroundStyle(.secondary)
  }

  private func actionRow(for thread: Thread) -> some View {
    HStack(spacing: 8) {
      Button("Stop") { openStop(for: thread) }
        .buttonStyle(.bordered)
        .keyboardShortcut("s", modifiers: [])
        .help("Stop the current thread (S)")

      Button("Switch") {
        // Switch from-the-popover requires picking a target. The
        // canonical entry point is clicking another Available row.
        // Surface that hint inline rather than building a thread picker.
      }
      .buttonStyle(.bordered)
      .disabled(true)
      .help("Click a thread in Available to switch")

      Button("Park") { openPark(for: thread) }
        .buttonStyle(.bordered)

      Spacer()
      Text("S")
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(.tertiary)
        .help("Press S to stop")
    }
  }

  // MARK: - Window openers

  private func openStop(for thread: Thread) {
    store.pendingFlow = .stop(threadId: thread.id)
    openWindow(id: PopoverWindowID.stop.rawValue)
  }

  private func openPark(for thread: Thread) {
    store.pendingFlow = .park(threadId: thread.id)
    openWindow(id: PopoverWindowID.park.rawValue)
  }
}
