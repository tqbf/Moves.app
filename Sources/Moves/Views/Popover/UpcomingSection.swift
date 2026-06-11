import SwiftUI

/// "Upcoming" section of the popover (INITIAL-PLAN §4.1, §7).
///
/// Renders the next hard reminder + runway from `HeadroomService`, then
/// any other upcoming items below. Soft items are listed alongside hard
/// items in the "Other" line for context — the runway calc is hard-only
/// per §2.10's "headroom is a nudge, not the app" constraint.
struct UpcomingSection: View {
  @Environment(AppStore.self) private var store

  /// Computed by parent on each refresh. Passing it in (rather than
  /// recomputing here) keeps the section pure and lets the parent control
  /// the timer cadence.
  let headroom: HeadroomService.Headroom

  var body: some View {
    PopoverSectionContainer(title: "Upcoming") {
      if let next = headroom.nextHard {
        VStack(alignment: .leading, spacing: 4) {
          Text("Next hard: \(next.title)")
            .font(.callout)
            .fontWeight(.medium)
            .lineLimit(1)
          Text(runwayLabel)
            .font(.caption)
            .foregroundStyle(PaneMetrics.secondaryText)
        }
      } else {
        Text("Nothing hard ahead")
          .font(.callout)
          .foregroundStyle(PaneMetrics.secondaryText)
      }

      let others = otherUpcoming
      if !others.isEmpty {
        Divider()
          .padding(.vertical, 2)
        VStack(alignment: .leading, spacing: 2) {
          ForEach(others) { item in
            UpcomingRow(item: item)
          }
        }
      }
    }
  }

  // MARK: - Derived

  private var runwayLabel: String {
    guard let runway = headroom.runway else { return "" }
    let parts = formatRunway(runway)
    if runway < 0 {
      return "\(parts) overdue"
    }
    return "in \(parts)"
  }

  private var otherUpcoming: [Item] {
    // "Other": everything in upcomingItems except the lead hard one.
    let leadId = headroom.nextHard?.id
    return store.upcomingItems
      .filter { $0.id != leadId }
      .prefix(3)
      .map { $0 }
  }

  private func formatRunway(_ runway: TimeInterval) -> String {
    let absSeconds = Int(abs(runway))
    let hours = absSeconds / 3600
    let minutes = (absSeconds % 3600) / 60
    if hours > 0, minutes > 0 { return "\(hours)h \(minutes)m" }
    if hours > 0 { return "\(hours)h" }
    return "\(minutes)m"
  }
}

private struct UpcomingRow: View {
  let item: Item

  var body: some View {
    HStack(spacing: 6) {
      // Leading icon still encodes interruption kind (hard / soft).
      // The trailing DeadlineChip encodes time pressure — the two
      // dimensions are independent and the popover row carries both.
      Image(systemName: item.interruptionKind == .hard ? "bell.fill" : "calendar")
        .font(.caption2)
        .foregroundStyle(item.interruptionKind == .hard ? .orange : .secondary)
        .frame(width: 12)
        .accessibilityLabel(item.interruptionKind == .hard ? "Hard reminder" : "Soft reminder")
      Text(item.title)
        .font(.caption)
        .lineLimit(1)
      Spacer(minLength: 4)
      if let due = item.dueAt {
        DeadlineChip(
          dueAt: Date(timeIntervalSince1970: TimeInterval(due)),
          size: .compact
        )
      }
    }
  }
}
