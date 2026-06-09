import SwiftUI

/// "Available" pane in the main window (INITIAL-PLAN §4.2, §12, §22).
///
/// Same §22 + §6 contract as the popover, rendered larger. Threads are
/// grouped into `Visible` (the normal Available list) and the §12
/// "De-emphasized during working hours" section. The §6 visibility
/// classifications (`hide_during_work` / `only_during_work` with no
/// deadline-bearing item) drop rows entirely.
///
/// Click a row → selects it (showing the inspector summary). Double-click
/// or hit Return → navigate to the thread detail. Switching is not done
/// from this pane; that flow lives in the popover (where it's a one-click
/// affordance during active work). Swipe-left on a row to delete the
/// underlying thread.
struct AvailableView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.openSettings) private var openSettings
  var onSelectThread: (String) -> Void

  /// List selection — kept so a future detail surface can read it; no
  /// longer drives an inspector.
  @State private var selection: String?

  var body: some View {
    let filtered = filtered()
    let total = filtered.visible.count + filtered.deemphasized.count
    PaneListShell(
      title: "Available",
      count: total,
      content: { body(filtered: filtered) }
    )
  }

  @ViewBuilder
  private func body(filtered: WorkingHoursService.FilteredAvailable) -> some View {
    VStack(spacing: 0) {
      if filtered.visible.isEmpty, filtered.deemphasized.isEmpty {
        // Batch 8, item 28 — Available's empty state was already in
        // shape from batch 4. Tightened copy: "Nothing ready to work on"
        // reads as a status, not a verdict; the description points the
        // user at the two ways a row gets here (breadcrumb on a thread,
        // or a captured item).
        ContentUnavailableView(
          "Nothing ready to work on",
          systemImage: "figure.walk.motion",
          description: Text("Add a breadcrumb to a thread, or capture a reminder, to put a row here.")
        )
      } else {
        List(selection: $selection) {
          // Flat top section, no header — the pane header already labels
          // the content. The de-emphasized group below DOES keep its
          // header because the visual demotion needs explaining.
          //
          // The first visible row gets the "Next" treatment (3pt leading
          // accent bar + faint accent tint) so the eye lands on the most
          // obvious next move without inventing a priority system.
          ForEach(Array(filtered.visible.enumerated()), id: \.element.id) { offset, row in
            rowView(row, deemphasized: false, isNext: offset == 0)
              .tag(row.thread.id)
              .listRowSeparator(.hidden)
              .listRowInsets(EdgeInsets(
                top: PaneMetrics.listRowVertical,
                leading: PaneMetrics.listRowLeading,
                bottom: PaneMetrics.listRowVertical,
                trailing: PaneMetrics.listRowTrailing
              ))
          }
          if !filtered.deemphasized.isEmpty {
            Section("De-emphasized during working hours") {
              ForEach(filtered.deemphasized) { row in
                rowView(row, deemphasized: true, isNext: false)
                  .tag(row.thread.id)
                  .listRowSeparator(.hidden)
                  .listRowInsets(EdgeInsets(
                    top: PaneMetrics.listRowVertical,
                    leading: PaneMetrics.listRowLeading,
                    bottom: PaneMetrics.listRowVertical,
                    trailing: PaneMetrics.listRowTrailing
                  ))
              }
            }
          }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      workingStatus
    }
  }

  /// Working-hours status footer. Batch 8, item 29 — the previous
  /// "Working hours: no" chip read as a debug toggle (a yes/no value
  /// with no context). Reframed as a status sentence with a tiny status
  /// dot (green when inside the window, neutral when outside), the same
  /// idiom Mail's connection footer uses. Wrapped in `SettingsLink` so
  /// clicking the footer opens System Settings → Moves at the Working
  /// Hours tab — the natural destination when the reader notices the
  /// state and wants to edit it.
  ///
  /// Closed state appends a "· Next: <when>" suffix when the next
  /// opening is within the next 12h, so the reader sees runway without
  /// having to hunt for it. Stays silent when the next window is far
  /// out (e.g. weekend on a Mon–Fri config) to keep the footer compact.
  ///
  /// `TimelineView` ticks once a minute so "Next: …" updates as the
  /// clock advances — same cadence as the rest of the working-hours
  /// derived UI.
  @ViewBuilder
  private var workingStatus: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      workingStatusBody(now: context.date)
    }
  }

  @ViewBuilder
  private func workingStatusBody(now: Date) -> some View {
    let working = store.isWorkTime
    // Plain `Button` + `openSettings()` instead of `SettingsLink`.
    // SettingsLink hosted inside a `safeAreaInset(edge: .bottom)` on a
    // List triggered an
    // `_postWindowNeedsUpdateConstraintsUnlessPostingDisabled` crash on
    // first layout under macOS 14.4 on at least one machine — see the
    // 2026-06-09 launch-crash entry in PROGRESS.md.
    // `Environment(\.openSettings)` reaches SwiftUI's `Settings { }`
    // scene reliably on macOS 14+ without the constraint hazard.
    Button {
      openSettings()
    } label: {
      HStack(spacing: 6) {
        Circle()
          .fill(working ? Color.green : Color.secondary.opacity(0.6))
          .frame(width: 6, height: 6)
          .accessibilityHidden(true)
        Text(workingStatusLine(working: working, now: now))
          .font(.caption)
          .foregroundStyle(PaneMetrics.secondaryText)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("Edit working hours in Settings")
    .accessibilityLabel(working ? "Working hours open. Open Settings." : "Outside working hours. Open Settings.")
    .padding(.horizontal, PaneMetrics.horizontalInset)
    .padding(.vertical, 8)
    .background(.bar)
  }

  /// Compose the status sentence. Open: "Working hours · open" — a
  /// declarative present-tense reading. Closed: "Outside working hours"
  /// alone, or with a "· Next: <time>" suffix when the next opening
  /// falls within the 12h runway window.
  private func workingStatusLine(working: Bool, now: Date) -> String {
    if working {
      return "Working hours · open"
    }
    guard let next = nextWorkingHoursStart(after: now),
          next.timeIntervalSince(now) <= 12 * 3600
    else {
      return "Outside working hours"
    }
    return "Outside working hours · Next: \(Self.nextOpeningFormatter.string(from: next))"
  }

  /// Search forward in 1-minute steps for the start of the next working
  /// window. Bounded at 8 days so a misconfigured (empty-days) `WorkingHours`
  /// can never spin — we return `nil` and the footer drops the runway
  /// suffix gracefully.
  ///
  /// One-minute granularity matches `WorkingHoursService.isInside`'s
  /// minute-of-day check and the surrounding 1-minute TimelineView tick.
  private func nextWorkingHoursStart(after start: Date) -> Date? {
    let hours = store.workingHours
    guard !hours.days.isEmpty else { return nil }
    let calendar = Calendar(identifier: .iso8601)
    // Start probing from the next whole minute so we don't return `start`
    // itself when it sits exactly at the boundary.
    let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
    guard var probe = calendar.date(from: comps) else { return nil }
    probe = probe.addingTimeInterval(60)
    let limit = start.addingTimeInterval(8 * 24 * 3600)
    var wasInside = WorkingHoursService.isInside(date: probe, hours: hours, calendar: calendar)
    while probe <= limit {
      let next = probe.addingTimeInterval(60)
      let nowInside = WorkingHoursService.isInside(date: next, hours: hours, calendar: calendar)
      if !wasInside, nowInside { return next }
      wasInside = nowInside
      probe = next
    }
    return nil
  }

  /// Relative-date-aware short formatter for the "Next: …" suffix. Uses
  /// `doesRelativeDateFormatting` so "tomorrow" renders as the word,
  /// not a redundant date — matches the deadline chip vocabulary the
  /// rest of the app uses.
  private static let nextOpeningFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = .autoupdatingCurrent
    f.dateStyle = .medium
    f.timeStyle = .short
    f.doesRelativeDateFormatting = true
    return f
  }()

  private func filtered() -> WorkingHoursService.FilteredAvailable {
    WorkingHoursService.filter(
      available: store.availableThreads,
      isWorkTime: store.isWorkTime,
      hasDeadline: { row in
        (store.openItemsByThread[row.thread.id] ?? []).contains { $0.dueAt != nil }
      }
    )
  }

  @ViewBuilder
  private func rowView(_ row: AvailableThread, deemphasized: Bool, isNext: Bool) -> some View {
    AvailableRow(
      item: row,
      deemphasized: deemphasized,
      isNext: isNext,
      isSelected: selection == row.thread.id,
      deadline: earliestDeadline(for: row.thread.id),
      onOpen: { onSelectThread(row.thread.id) },
      onStart: { Task { await store.start(row.thread) } },
      onPark: { store.setStatus(row.thread, to: .parked) },
      onDelete: { store.delete(row.thread) },
      onRename: { newTitle in store.rename(row.thread, to: newTitle) }
    )
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button(role: .destructive) {
        store.delete(row.thread)
      } label: {
        Label("Delete", systemImage: "trash")
      }
    }
  }

  /// Earliest deadline across the thread's open items, if any. Surfacing
  /// the closest deadline on the row reuses the orange `DeadlineChip`
  /// vocabulary and matches item 22's "deadlines must appear on normal
  /// task rows, not only on the Deadlines pane".
  private func earliestDeadline(for threadId: String) -> Date? {
    let items = store.openItemsByThread[threadId] ?? []
    let earliest = items.compactMap(\.dueAt).min()
    return earliest.map { Date(timeIntervalSince1970: TimeInterval($0)) }
  }
}

private struct AvailableRow: View {
  let item: AvailableThread
  let deemphasized: Bool
  let isNext: Bool
  let isSelected: Bool
  let deadline: Date?
  let onOpen: () -> Void
  let onStart: () -> Void
  let onPark: () -> Void
  let onDelete: () -> Void
  /// Closure-style rename (rather than wiring AppStore through here) so
  /// the row stays decoupled from the store and tests can stub it.
  let onRename: (String) -> Void

  /// Local sheet state for the inline Rename action surfaced via the
  /// context menu. Per-row state so two open rows can't fight over it.
  @State private var renaming: Bool = false

  var body: some View {
    Button(action: onOpen) {
      TaskRow(
        title: item.thread.title,
        subtitle: item.move.text,
        deadline: deadline,
        threadTag: nil,
        isNext: isNext && !deemphasized,
        isSelected: isSelected,
        hoverActions: {
          // Hover-revealed actions. Order: Start (primary verb), Open
          // (navigate). Both wired via the row's existing AppStore-backed
          // callbacks so the menu items and icons share semantics.
          RowHoverActionButton(systemName: "play.fill", help: "Start") {
            onStart()
          }
          RowHoverActionButton(systemName: "arrow.up.right", help: "Open") {
            onOpen()
          }
        }
      )
      .opacity(deemphasized ? 0.5 : 1.0)
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button("Start") { onStart() }
      Button("Open Thread") { onOpen() }
      Button("Rename Thread…") { renaming = true }
      Divider()
      Button("Park") { onPark() }
      Divider()
      Button("Delete", role: .destructive) { onDelete() }
    }
    .sheet(isPresented: $renaming) {
      RenameThreadSheet(
        currentTitle: item.thread.title,
        onSave: { newTitle in
          onRename(newTitle)
          renaming = false
        },
        onCancel: { renaming = false }
      )
    }
  }
}

