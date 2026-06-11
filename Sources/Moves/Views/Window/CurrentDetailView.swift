import SwiftUI

/// "Current" pane in the main window (INITIAL-PLAN §4.2). Shows what the
/// app considers the current thread — the same data the menu-bar Current
/// section displays, presented for the larger surface.
///
/// Layout (batch 3, item 10): the main-window Current pane has real
/// estate, so the operational metadata reads as a hero card:
///   - thread title at `.title2` semibold,
///   - large rounded `monospacedDigit` elapsed time ("00:16"),
///   - "Started 2:14 PM" caption underneath,
///   - orange deadline chip prominent when the active segment carries a
///     `dueAt`,
///   - breadcrumb / segment metadata,
///   - button row at the bottom with a real hierarchy.
///
/// Button hierarchy (batch 3, item 11):
///   - **Open thread** — `.borderedProminent` (primary navigation),
///   - **Stop** — `.bordered` + `.tint(.red)` + `role: .destructive`
///     (terminal action),
///   - **Park** — `.bordered`, default tint (neutral secondary).
///
/// Stop / Park use the popover-based flow windows so the editing UX stays
/// identical across surfaces.
struct CurrentDetailView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.openWindow) private var openWindow
  var onSelectThread: (String) -> Void
  /// Empty-state action — flips the sidebar selection back to Available so
  /// the user can pick something to start. Injected by `RootWindow` so the
  /// pane stays decoupled from the sidebar's `SidebarDestination` model.
  var onGoAvailable: () -> Void

  var body: some View {
    let hasCurrent = store.thread(id: store.current.threadId ?? "") != nil
    PaneShell(title: "Current", count: hasCurrent ? 1 : nil) {
      if let thread = store.thread(id: store.current.threadId ?? "") {
        card(for: thread)
      } else {
        // Batch 8, item 28 — designed empty state per destination.
        // ContentUnavailableView with one obvious action ("Start something
        // from Ready") matches the macOS Reminders / Mail empty-state
        // idiom. `figure.walk` echoes the Available sidebar icon so the
        // visual link "go to Available to pick something" reads at a
        // glance.
        ContentUnavailableView {
          Label("Nothing in progress", systemImage: "figure.walk")
        } description: {
          Text("Pick a thread from Available to start working.")
        } actions: {
          Button("Start something from Ready", action: onGoAvailable)
            .buttonStyle(.borderedProminent)
        }
      }
    }
  }

  // MARK: - Card

  @ViewBuilder
  private func card(for thread: Thread) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      // Title + breadcrumb / segment line.
      VStack(alignment: .leading, spacing: 4) {
        Text(thread.title)
          .font(.title2)
          .fontWeight(.semibold)
          .lineLimit(2)
        if let segment = currentSegment(for: thread) {
          Text(segment.title)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        if !thread.breadcrumb.isEmpty {
          Text("Next: \(thread.breadcrumb)")
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      // Hero metadata: large elapsed time + started-at clock time +
      // deadline chip. The elapsed label self-ticks via TimelineView so
      // the whole card doesn't redraw every second.
      metadataBlock(for: thread)

      // Button row, hierarchy per item 11.
      buttonRow(for: thread)
    }
    .padding(20)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(.background.secondary)
    )
    .frame(maxWidth: 560, alignment: .leading)
  }

  /// Elapsed time + started-at clock time + optional orange deadline
  /// chip. The block lays out as:
  ///
  ///   [ 00:16 ]                 [orange chip]
  ///   Started 2:14 PM
  ///
  /// when there is a deadline, and just the left column otherwise.
  @ViewBuilder
  private func metadataBlock(for thread: Thread) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        if let started = startedAt(thread) {
          ElapsedTimeLabel(
            startedAt: started,
            font: .system(.title, design: .rounded),
            foregroundStyle: .primary
          )
          Text("Started \(started, format: .dateTime.hour().minute())")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          // Defensive fallback — Current is set but startedAt missing
          // (legacy rows from before §10 added the column). Show a
          // neutral placeholder rather than blanking out the line.
          Text("—")
            .font(.system(.title, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.tertiary)
        }
      }
      Spacer(minLength: 0)
      if let due = deadlineDate(for: thread) {
        DeadlineChip(dueAt: due, size: .regular)
      }
    }
  }

  /// Buttons in role order: primary first (`Open thread`), destructive
  /// last (`Stop`), neutral in the middle (`Park`). Equal widths look
  /// neat but undermine the hierarchy — let each button size naturally
  /// so the prominent one reads as the primary.
  @ViewBuilder
  private func buttonRow(for thread: Thread) -> some View {
    HStack(spacing: 8) {
      Button("Open thread") { onSelectThread(thread.id) }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .help("Open this thread in the Threads pane")

      Button("Park", action: openParkForCurrent)
        .buttonStyle(.bordered)
        .help("Park the current thread")

      Spacer()

      Button("Stop", role: .destructive, action: openStopForCurrent)
        .buttonStyle(.bordered)
        .tint(.red)
        .keyboardShortcut("s", modifiers: [])
        .help("Stop the current thread (S)")
    }
  }

  // MARK: - Lookups

  private func currentSegment(for thread: Thread) -> Segment? {
    store.currentSegment(for: thread)
  }

  private func startedAt(_ thread: Thread) -> Date? {
    guard store.current.threadId == thread.id,
          let started = store.current.startedAt
    else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(started))
  }

  private func deadlineDate(for thread: Thread) -> Date? {
    guard let due = currentSegment(for: thread)?.dueAt else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(due))
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
