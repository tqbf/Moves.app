import SwiftUI

/// "Captured" section of the popover (INITIAL-PLAN §4.1, §13).
///
/// Recent captured items without a thread. Phase 3 renders read-only —
/// processing actions (attach to thread, convert, mark done) are Phase 4.
/// We surface them here so the popover feels complete and the §13 list
/// has a visible home in the daily-driver UI.
struct CapturedSection: View {
  @Environment(AppStore.self) private var store

  /// Cap the list — the popover is the daily-driver surface, not an inbox
  /// processor. Phase 4's main-window Captured view is where you triage.
  private static let maxRows = 4

  var body: some View {
    PopoverSectionContainer(title: "Captured") {
      let rows = Array(store.capturedItems.prefix(Self.maxRows))
      if rows.isEmpty {
        Text("Nothing captured")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(rows) { item in
            CapturedPopoverRow(item: item)
          }
          if store.capturedItems.count > Self.maxRows {
            Text("+\(store.capturedItems.count - Self.maxRows) more in the main window")
              .font(.caption)
              .foregroundStyle(.tertiary)
              .padding(.top, 2)
          }
        }
      }
    }
  }
}

private struct CapturedPopoverRow: View {
  let item: Item

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.caption2)
        .foregroundStyle(iconColor)
        .frame(width: 12)
        .accessibilityLabel(iconLabel)
      Text(item.title)
        .font(.caption)
        .lineLimit(1)
      Spacer(minLength: 4)
      // Reuse the shared DeadlineChip rather than rendering raw due text
      // — keeps the deadline vocabulary consistent across surfaces and
      // gives the popover row the same red/orange urgency treatment as
      // the main-window rows.
      if let dueDate {
        DeadlineChip(dueAt: dueDate, size: .compact)
      }
    }
  }

  /// VoiceOver label for the icon describing the capture's interruption.
  private var iconLabel: String {
    switch item.interruptionKind {
    case .hard: return "Hard reminder"
    case .soft: return "Soft reminder"
    case .none: return "Capture"
    }
  }

  private var icon: String {
    switch item.interruptionKind {
    case .hard: return "bell.fill"
    case .soft: return "calendar"
    case .none: return "tray"
    }
  }

  private var iconColor: Color {
    switch item.interruptionKind {
    case .hard: return .orange
    case .soft: return .secondary
    case .none: return Color.gray.opacity(0.6)
    }
  }

  private var dueDate: Date? {
    guard let due = item.dueAt else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(due))
  }
}
