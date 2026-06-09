import SwiftUI

/// Small pill that surfaces a deadline in a row or card. Mirrors the
/// orange `bell.fill + relative date` chip the capture palette uses for
/// parsed hard deadlines so the deadline vocabulary stays consistent
/// across surfaces:
///
///   - capture preview ("Tomorrow at 3:00 PM" when a date is parsed),
///   - Current card (when the active segment carries a `dueAt`),
///   - row anatomy across the main window (Available, Captured,
///     Deadlines, Parking Lot).
///
/// Tooltip exposes the full calendar date so the relative label can be
/// verified at a glance.
///
/// ## Urgency rendering (batch 6, item 24)
///
/// The chip computes its own `DeadlineChipUrgency` from `dueAt + now`
/// inside a `TimelineView` so it flips to the overdue treatment the
/// minute the deadline passes — callers don't need to subscribe to a
/// timer. Tint policy (see `DeadlineChipUrgency`):
///
///   - `.overdue` → system red + `exclamationmark.triangle.fill`
///   - `.dueToday` / `.dueTomorrow` / `.dueFuture` → system orange +
///     `bell.fill`
///   - `lowConfidence: true` → system yellow + `questionmark.circle.fill`
///     (overrides urgency tinting — when we're not sure the date is
///     right, the chip should not also be screaming red).
///
/// ## Editable / clearable variants
///
/// Two optional closures opt the chip into command-overlay-style
/// affordances without breaking existing read-only call sites:
///
///   - `onTap`: when supplied, the chip becomes a `Button` whose action
///     is `onTap`. The capture palette uses this to open a date-picker
///     popover.
///   - `onClear`: when supplied, an `xmark.circle.fill` trailing glyph
///     appears as a separate button that removes the deadline.
///   - `isParked`: when true, the chip reduces opacity and a sibling
///     "Parked" capsule is rendered alongside. Used by ParkingLot rows
///     so a parked-with-due-date thread reads as deferred but still
///     time-sensitive.
///
/// All non-data parameters default to a neutral value, so existing call
/// sites (`CurrentSection`, `CurrentDetailView`, `TaskRow`) keep their
/// flat, label-style chip with no chrome.
struct DeadlineChip: View {

  /// The wall-clock deadline to render.
  let dueAt: Date

  /// Optional size hint. Defaults to the standard 11pt chip used in the
  /// capture preview; the main-window Current detail can request a slightly
  /// larger size where the card has more room.
  enum Size { case compact, regular }
  var size: Size = .compact

  /// When true, swap the bell glyph for a question-mark and tint yellow.
  /// Drives the "parser thinks it found a date but isn't sure" treatment
  /// in the capture overlay; safe to leave false everywhere else.
  /// Overrides urgency tinting.
  var lowConfidence: Bool = false

  /// When true, the chip is muted (reduced opacity) and a small "Parked"
  /// caption capsule is rendered next to it. Used by ParkingLotView to
  /// distinguish "parked thread with a future deadline" — still
  /// time-sensitive, but not actively in play.
  var isParked: Bool = false

  /// When non-nil, the chip becomes tappable. Used by the capture overlay
  /// to open a date-picker popover.
  var onTap: (() -> Void)? = nil

  /// When non-nil, a trailing `xmark.circle.fill` button appears as part of
  /// the chip and removes the deadline when pressed.
  var onClear: (() -> Void)? = nil

  var body: some View {
    // The chip self-ticks so `.overdue` flips on time. Once a minute is
    // plenty — the relative-date label rounds to the minute, and the
    // overdue visual change doesn't need sub-second precision. Scoping
    // `TimelineView` to just this small leaf keeps the rest of the row
    // out of the redraw.
    TimelineView(.periodic(from: .now, by: 60)) { ctx in
      content(now: ctx.date)
    }
  }

  @ViewBuilder
  private func content(now: Date) -> some View {
    let urgency = DeadlineChipUrgency.from(dueAt: dueAt, now: now)
    HStack(spacing: 6) {
      if let onTap {
        Button(action: onTap) { chipBody(urgency: urgency) }
          .buttonStyle(.plain)
          .help(Self.absoluteFormatter.string(from: dueAt))
          .accessibilityLabel(accessibilityLabel(urgency: urgency) + ". Tap to edit.")
      } else {
        chipBody(urgency: urgency)
          .help(Self.absoluteFormatter.string(from: dueAt))
          .accessibilityLabel(accessibilityLabel(urgency: urgency))
      }
      if isParked {
        parkedCapsule
      }
    }
  }

  private func chipBody(urgency: DeadlineChipUrgency) -> some View {
    HStack(spacing: 4) {
      Image(systemName: iconName(urgency: urgency))
        .font(.system(size: iconSize, weight: .semibold))
      Text(Self.relativeFormatter.string(from: dueAt))
        .font(.system(size: textSize, weight: .medium))
        .lineLimit(1)
        .truncationMode(.tail)
      if let onClear {
        // Separate button so it doesn't fire `onTap` when the user wants to
        // clear. Plain style keeps the chip tint of the surrounding chip.
        Button(action: onClear) {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: iconSize, weight: .semibold))
        }
        .buttonStyle(.plain)
        .help("Clear deadline")
        .accessibilityLabel("Clear deadline")
      }
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 2)
    .foregroundStyle(tint(urgency: urgency))
    .background(
      Capsule(style: .continuous)
        .fill(tint(urgency: urgency).opacity(0.15))
    )
    .opacity(isParked ? 0.6 : 1.0)
  }

  /// Small grey capsule that sits next to the chip when the parent
  /// thread is parked. Reads as metadata, not a status — the chip stays
  /// the dominant signal.
  private var parkedCapsule: some View {
    Text("Parked")
      .font(.caption2.weight(.medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 6)
      .padding(.vertical, 1)
      .background(
        Capsule(style: .continuous)
          .fill(Color.secondary.opacity(0.15))
      )
      .accessibilityLabel("Thread parked")
  }

  /// Yellow `.lowConfidence` wins over urgency tint — when the parser
  /// isn't sure, we don't want the chip simultaneously shouting "overdue".
  private func tint(urgency: DeadlineChipUrgency) -> Color {
    if lowConfidence { return .yellow }
    switch urgency {
    case .overdue: return .red
    case .dueToday, .dueTomorrow, .dueFuture: return .orange
    }
  }

  private func iconName(urgency: DeadlineChipUrgency) -> String {
    if lowConfidence { return "questionmark.circle.fill" }
    switch urgency {
    case .overdue: return "exclamationmark.triangle.fill"
    case .dueToday, .dueTomorrow, .dueFuture: return "bell.fill"
    }
  }

  private func accessibilityLabel(urgency: DeadlineChipUrgency) -> String {
    let dateString = Self.absoluteFormatter.string(from: dueAt)
    let parkedSuffix = isParked ? ", parked" : ""
    switch urgency {
    case .overdue: return "Overdue \(dateString)\(parkedSuffix)"
    case .dueToday: return "Due today, \(dateString)\(parkedSuffix)"
    case .dueTomorrow: return "Due tomorrow, \(dateString)\(parkedSuffix)"
    case .dueFuture: return "Deadline \(dateString)\(parkedSuffix)"
    }
  }

  private var iconSize: CGFloat { size == .compact ? 10 : 11 }
  private var textSize: CGFloat { size == .compact ? 11 : 12 }

  /// Relative + short — "Today at 3:00 PM", "Tomorrow at 3:00 PM",
  /// otherwise "M/D/YY at H:MM AM". Matches the capture palette's chip
  /// formatter so the two surfaces speak the same language.
  private static let relativeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    f.timeStyle = .short
    f.doesRelativeDateFormatting = true
    return f
  }()

  /// Tooltip companion — full calendar date so the user can verify the
  /// relative label.
  private static let absoluteFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .full
    f.timeStyle = .short
    f.doesRelativeDateFormatting = false
    return f
  }()
}
