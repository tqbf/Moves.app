import SwiftUI

/// The "Current" section of the popover (INITIAL-PLAN §4.1).
///
/// Shows the current thread's title, a single operational metadata line —
/// elapsed time + started clock time — the optional deadline chip, the
/// breadcrumb (the "Next:" line), and the Stop / Park action row.
/// When no thread is current, renders "Not working on anything" neutrally
/// (§2.6: zero current work is valid; no shame).
///
/// Layout density: this is a 320pt popover surface — the elapsed/started
/// pair lives on one line ("00:16 · Started 2:14 PM") so the section
/// doesn't blow out vertically. The main-window Current pane has more
/// room and uses a larger elapsed display (`CurrentDetailView`).
///
/// The Stop button has an `S`-key accelerator wired via
/// `.keyboardShortcut("s", modifiers: [])` and the hint is rendered inline
/// so users discover it.
///
/// Button hierarchy (batch 3, item 11): there is no "Open thread" button
/// in the popover — the popover's `Open` footer button covers main-window
/// navigation. The popover keeps Stop (`.bordered` + `.red` tint + role
/// `.destructive`) and Park (`.bordered`, neutral).
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

  private var startedAtDate: Date? {
    guard let started = store.current.startedAt else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(started))
  }

  private var deadlineDate: Date? {
    guard let due = currentSegment?.dueAt else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(due))
  }

  private func activeContent(for thread: Thread) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(thread.title)
        .font(.callout)
        .fontWeight(.semibold)
        .lineLimit(1)

      // Operational metadata line: "00:16 · Started 2:14 PM" + optional
      // orange deadline chip. The elapsed label self-ticks via
      // TimelineView so the surrounding card doesn't redraw every second.
      metadataRow

      if let segment = currentSegment {
        Text(segment.title)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      if !thread.breadcrumb.isEmpty {
        Text("Next: \(thread.breadcrumb)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }

      actionRow(for: thread)
        .padding(.top, 4)
    }
  }

  /// Single horizontal line carrying elapsed + started + (optional) due
  /// chip. Keeps the popover Current section compact.
  @ViewBuilder
  private var metadataRow: some View {
    HStack(spacing: 6) {
      if let started = startedAtDate {
        ElapsedTimeLabel(
          startedAt: started,
          font: .system(.caption, design: .rounded),
          foregroundStyle: .primary
        )
        Text("·")
          .font(.caption)
          .foregroundStyle(.tertiary)
        Text("Started \(started, format: .dateTime.hour().minute())")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if let due = deadlineDate {
        DeadlineChip(dueAt: due, size: .compact)
      }
    }
  }

  private var idleContent: some View {
    Text("Not working on anything")
      .font(.callout)
      .foregroundStyle(.secondary)
  }

  private func actionRow(for thread: Thread) -> some View {
    // Buttons read the current thread fresh from `store.current` at click
    // time instead of capturing `thread` from the closure scope. SwiftUI
    // does not always re-register a `.keyboardShortcut` handler when the
    // enclosing View identity is reused across @Observable updates, so a
    // captured `thread` can go stale right after a Switch.
    //
    // Button hierarchy (batch 3): Stop is the destructive terminal action
    // — `.bordered` with `.tint(.red)` and `role: .destructive`. Park is
    // a neutral secondary `.bordered`.
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Button("Stop", role: .destructive, action: openStopForCurrent)
          .buttonStyle(.bordered)
          .tint(.red)
          .keyboardShortcut("s", modifiers: [])
          .help("Stop the current thread (S)")

        Button("Park", action: openParkForCurrent)
          .buttonStyle(.bordered)
          .help("Park the current thread")

        Spacer()
      }
      // Permanently-unavailable buttons (the disabled "Switch" button)
      // misuse macOS disabled state, which means "temporarily
      // unavailable". A muted hint communicates the same affordance
      // without the dead-button pattern.
      Text("Or click a thread in Available to switch")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
  }

  // MARK: - Window openers

  private func openStopForCurrent() {
    guard let id = store.current.threadId else { return }
    store.pendingFlow = .stop(threadId: id)
    openWindow(id: PopoverWindowID.stop.rawValue)
  }

  private func openParkForCurrent() {
    guard let id = store.current.threadId else { return }
    store.pendingFlow = .park(threadId: id)
    openWindow(id: PopoverWindowID.park.rawValue)
  }
}
