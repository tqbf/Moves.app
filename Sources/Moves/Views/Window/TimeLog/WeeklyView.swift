import SwiftUI

/// "Time Log" pane (INITIAL-PLAN §14). One row per thread that had at least
/// one `TimeLogEntry` in the active ISO week, with a `~Nh` aggregate label
/// from `TimeLogService.roughBucketLabel`. Prev / Next chrome navigates
/// between weeks; the current week is the default.
///
/// Reads the projection through `AppStore.weeklyView(for:)` so the query
/// stays aligned with how completion rows get written (Monday-start ISO
/// weeks, week_start as `YYYY-MM-DD`). The pane does not render minute-by-
/// minute precision — §14 is explicit about rough only.
struct WeeklyView: View {
  @Environment(AppStore.self) private var store

  @State private var anchor: Date = .now
  @State private var summary: WeeklySummary = .empty(weekStart: "")

  var body: some View {
    PaneShell(
      title: "Time Log",
      count: summary.entries.count,
      accessory: { weekChip },
      content: {
        navigator
        content
      }
    )
    .task(id: anchor) { await reload() }
  }

  /// Compact week chip surfaced in the pane header so the user sees
  /// which window they're in even after scrolling. Matches the macOS
  /// pattern of "current scope in the title strip."
  @ViewBuilder
  private var weekChip: some View {
    Text(weekHeaderLabel)
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(Capsule(style: .continuous).fill(.quaternary))
  }

  // MARK: - Subviews

  private var navigator: some View {
    HStack(spacing: 10) {
      Button {
        anchor = shifted(by: -7)
      } label: {
        Label("Previous week", systemImage: "chevron.left")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.bordered)
      .help("Previous week")

      Text(weekHeaderLabel)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(minWidth: 220, alignment: .center)

      Button {
        anchor = shifted(by: 7)
      } label: {
        Label("Next week", systemImage: "chevron.right")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.bordered)
      .help("Next week")

      Spacer()

      if !isCurrentWeek {
        Button("This week") { anchor = .now }
          .buttonStyle(.borderless)
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    if summary.entries.isEmpty {
      // Batch 8, item 28 — copy aligned with the other empty states
      // ("Work sessions will appear here"); systemImage trimmed to the
      // plain `clock` glyph so the empty surface reads cleaner than the
      // animated `clock.arrow.circlepath`.
      ContentUnavailableView(
        "No work sessions yet",
        systemImage: "clock",
        description: Text("Work sessions will appear here. Stop, switch, or finish a segment to log rough time.")
      )
      .frame(maxWidth: .infinity)
      .padding(.top, 24)
    } else {
      VStack(spacing: 0) {
        ForEach(summary.entries) { aggregate in
          row(for: aggregate)
          if aggregate.id != summary.entries.last?.id {
            Divider().padding(.leading, 14)
          }
        }
      }
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(.background.secondary)
      )
    }
  }

  private func row(for aggregate: ThreadAggregate) -> some View {
    HStack(alignment: .center, spacing: 12) {
      Text(threadTitle(for: aggregate.threadId))
        .font(.system(size: 14, weight: .medium))
        .lineLimit(1)
      Spacer()
      Text(TimeLogService.roughBucketLabel(aggregate.totalMinutes))
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Derived strings

  private var subtitleText: String {
    let count = summary.entries.count
    return "\(count) thread\(count == 1 ? "" : "s") with rough-time logs this week."
  }

  private var weekHeaderLabel: String {
    // "Jun 1 – Jun 7" derived from `summary.weekStart` + 6 days. Use a
    // formatter rather than a string-math hack so future locales don't
    // break us.
    guard let monday = Self.mondayDate(from: summary.weekStart) else {
      return summary.weekStart
    }
    let sunday = Calendar.iso8601Monday.date(byAdding: .day, value: 6, to: monday) ?? monday
    return "\(Self.weekHeaderFormatter.string(from: monday)) – \(Self.weekHeaderFormatter.string(from: sunday))"
  }

  private var isCurrentWeek: Bool {
    summary.weekStart == TimeLogService.weekStart(for: .now)
  }

  private func threadTitle(for id: String) -> String {
    store.thread(id: id)?.title ?? "Deleted thread"
  }

  // MARK: - Mutations

  private func shifted(by days: Int) -> Date {
    Calendar.iso8601Monday.date(byAdding: .day, value: days, to: anchor) ?? anchor
  }

  private func reload() async {
    summary = await store.weeklyView(for: anchor)
  }

  // MARK: - Static helpers

  /// Cached "MMM d" formatter used by `weekHeaderLabel`. The pane re-renders
  /// on each working-hours timeline tick; building a `DateFormatter` per
  /// render is wasted work and matches the codebase's pattern of
  /// `static let` formatters (cf. `MarkdownEditorView`, `CapturedPopoverRow`).
  private static let weekHeaderFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = .iso8601Monday
    f.timeZone = Calendar.iso8601Monday.timeZone
    f.dateFormat = "MMM d"
    return f
  }()

  /// Parse a `yyyy-MM-dd` Monday key back into a `Date` for the header.
  private static let weekStartParser: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = .iso8601Monday
    f.timeZone = Calendar.iso8601Monday.timeZone
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  private static func mondayDate(from yyyyMMdd: String) -> Date? {
    weekStartParser.date(from: yyyyMMdd)
  }
}
