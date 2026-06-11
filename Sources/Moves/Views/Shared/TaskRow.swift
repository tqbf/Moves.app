import SwiftUI

/// Shared row anatomy for every task-shaped list pane in the main window
/// — Available, Captured, Deadlines, Parking Lot. One row vocabulary, one
/// set of metrics, so the eye moves between panes without retraining.
///
/// Anatomy (left → right):
///
///   [accent bar?] [leading icon?] title             [thread tag?] [deadline chip?] [hover actions] [trailing slot]
///                                  subtitle
///
/// - `title`: primary line, semibold, single line, tail-truncated.
/// - `subtitle`: optional second line; uses the shared `RowSubtitle` so the
///   trailing-ellipsis sanitizer from batch 1 applies consistently.
/// - `deadline`: optional `Date`. When set, the orange `DeadlineChip`
///   batch 3 ported from the capture palette renders trailing. Batch 6
///   owns the urgency-state visuals (overdue red etc.); this slot just
///   wires the data through.
/// - `threadTag`: optional short label (the parent thread's title) for
///   rows that live *outside* their thread's pane (Captured, Deadlines).
///   Renders as a small monochrome capsule so it reads as metadata, not a
///   primary action.
/// - `isNext`: bumps the leading edge with a 3pt accent bar and a faint
///   accent tint over the row background. Used by Available to visibly
///   answer "what should I do next?".
/// - `isSelected`: List-driven selection. Renders a full-row accent tint
///   distinct from the lighter `isNext` background — selected reads as
///   "this is what I clicked", next reads as "this is what I should do".
/// - `hoverActions`: a `@ViewBuilder` slot whose contents render with
///   fade-in opacity on hover. Batch 7 uses it for Start / Open / Edit
///   icons so rows surface their per-row actions without crowding the
///   resting state. Don't dismount the buttons — opacity-fade keeps row
///   width stable as the cursor moves.
/// - `trailing`: a `@ViewBuilder` slot that always renders (used by
///   CapturedRow's ellipsis menu and ParkedRow's Unpark/Open buttons).
///   EmptyView default so existing callers don't pay the layout cost.
///
/// Row metrics come from `PaneMetrics.rowMinHeight` (~60pt) — bumped
/// from the previous ~36pt to match Mail / Reminders density.
/// Optional muted glyph at the leading edge of a `TaskRow`. Captured uses
/// it to surface the interruption kind (bell / calendar / tray); Available
/// + Threads don't need an icon (the title carries enough weight). Lives
/// at file scope rather than nested in `TaskRow<Trailing>` so callers
/// don't have to spell the generic parameter when constructing one.
struct TaskRowLeadingIcon {
  let systemName: String
  let tint: Color
  let accessibilityLabel: String?
}

struct TaskRow<HoverActions: View, Trailing: View>: View {
  let title: String
  var subtitle: String?
  var deadline: Date?
  var threadTag: String?
  var leadingIcon: TaskRowLeadingIcon?
  var isNext: Bool = false
  /// When true and a `deadline` is set, the trailing `DeadlineChip`
  /// renders in its parked variant (reduced opacity + sibling "Parked"
  /// capsule). Used by ParkingLotView to surface "this parked thread
  /// has a future deadline" without dropping the chip vocabulary.
  var isParked: Bool = false
  /// Driven by `List(selection:)`. When true, the row paints a full-row
  /// accent tint at 0.12 so it visibly out-weighs the lighter 0.06
  /// `isNext` background. The two states can co-occur (the next row IS
  /// the selected row); selection wins because it represents an explicit
  /// user act.
  var isSelected: Bool = false
  @ViewBuilder var hoverActions: () -> HoverActions
  @ViewBuilder var trailing: () -> Trailing

  /// Pointer hover state. `.onHover` on macOS fires whenever the cursor
  /// enters/leaves the row's hit region, which makes it the right driver
  /// for "reveal these icons" affordances. Animated via .animation on the
  /// hover-actions opacity so the buttons fade rather than pop.
  @State private var isHovered: Bool = false

  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      // Next-row accent bar. Three points wide, vertically inset by
      // ~10pt at top/bottom so it reads as a marker, not a column rule.
      Rectangle()
        .fill(isNext ? Color.accentColor : Color.clear)
        .frame(width: PaneMetrics.nextAccentBarWidth)
        .padding(.vertical, 10)
        .accessibilityHidden(true)

      HStack(alignment: .center, spacing: 12) {
        if let leadingIcon {
          Image(systemName: leadingIcon.systemName)
            .font(.system(size: 14))
            .foregroundStyle(leadingIcon.tint)
            .frame(width: 18)
            .accessibilityLabel(leadingIcon.accessibilityLabel ?? "")
            .accessibilityHidden(leadingIcon.accessibilityLabel == nil)
        }

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
          if let subtitle, !subtitle.isEmpty {
            RowSubtitle(subtitle)
              .font(.system(size: 12))
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let threadTag, !threadTag.isEmpty {
          ThreadTagCapsule(label: threadTag)
        }

        if let deadline {
          DeadlineChip(dueAt: deadline, isParked: isParked)
        }

        // Hover-revealed actions. Opacity-faded so the row's width
        // doesn't reflow as the cursor crosses it. `allowsHitTesting`
        // gates the buttons so they aren't clickable while invisible —
        // otherwise a user could click "Start" by accident from outside
        // a hover region.
        hoverActions()
          .opacity(isHovered ? 1 : 0)
          .allowsHitTesting(isHovered)
          .animation(.easeOut(duration: 0.12), value: isHovered)

        trailing()
      }
      .padding(.leading, 8)
      .padding(.trailing, 4)
    }
    .frame(maxWidth: .infinity, minHeight: PaneMetrics.rowMinHeight, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(backgroundStyle)
    )
    .contentShape(Rectangle())
    .onHover { hovering in
      isHovered = hovering
    }
  }

  /// Background tint priority: selected > next > hovered > none.
  /// - Selected = 0.12 accent — the strongest, because the user explicitly
  ///   picked it.
  /// - Next = 0.06 accent — a hint, not a claim.
  /// - Hovered = a soft neutral tint that doesn't compete with accent. We
  ///   use a near-transparent gray so dark mode still reads it.
  private var backgroundStyle: AnyShapeStyle {
    if isSelected {
      return AnyShapeStyle(Color.accentColor.opacity(0.12))
    }
    if isNext {
      return AnyShapeStyle(Color.accentColor.opacity(0.06))
    }
    if isHovered {
      return AnyShapeStyle(Color.gray.opacity(0.08))
    }
    return AnyShapeStyle(Color.clear)
  }
}

// MARK: - Convenience inits

extension TaskRow where HoverActions == EmptyView, Trailing == EmptyView {
  init(
    title: String,
    subtitle: String? = nil,
    deadline: Date? = nil,
    threadTag: String? = nil,
    leadingIcon: TaskRowLeadingIcon? = nil,
    isNext: Bool = false,
    isParked: Bool = false,
    isSelected: Bool = false
  ) {
    self.title = title
    self.subtitle = subtitle
    self.deadline = deadline
    self.threadTag = threadTag
    self.leadingIcon = leadingIcon
    self.isNext = isNext
    self.isParked = isParked
    self.isSelected = isSelected
    self.hoverActions = { EmptyView() }
    self.trailing = { EmptyView() }
  }
}

extension TaskRow where HoverActions == EmptyView {
  /// Trailing-only init — kept for existing callers (CapturedRow,
  /// ParkedRow) that supply an always-visible trailing slot but no hover
  /// actions yet.
  init(
    title: String,
    subtitle: String? = nil,
    deadline: Date? = nil,
    threadTag: String? = nil,
    leadingIcon: TaskRowLeadingIcon? = nil,
    isNext: Bool = false,
    isParked: Bool = false,
    isSelected: Bool = false,
    @ViewBuilder trailing: @escaping () -> Trailing
  ) {
    self.title = title
    self.subtitle = subtitle
    self.deadline = deadline
    self.threadTag = threadTag
    self.leadingIcon = leadingIcon
    self.isNext = isNext
    self.isParked = isParked
    self.isSelected = isSelected
    self.hoverActions = { EmptyView() }
    self.trailing = trailing
  }
}

extension TaskRow where Trailing == EmptyView {
  /// Hover-actions-only init — used by Available/Deadlines rows which
  /// have no always-visible trailing chrome but need hover-revealed
  /// Start / Open / Edit / Done icons.
  init(
    title: String,
    subtitle: String? = nil,
    deadline: Date? = nil,
    threadTag: String? = nil,
    leadingIcon: TaskRowLeadingIcon? = nil,
    isNext: Bool = false,
    isParked: Bool = false,
    isSelected: Bool = false,
    @ViewBuilder hoverActions: @escaping () -> HoverActions
  ) {
    self.title = title
    self.subtitle = subtitle
    self.deadline = deadline
    self.threadTag = threadTag
    self.leadingIcon = leadingIcon
    self.isNext = isNext
    self.isParked = isParked
    self.isSelected = isSelected
    self.hoverActions = hoverActions
    self.trailing = { EmptyView() }
  }
}

/// Small monochrome capsule used to tag a row with its parent thread's
/// title — Captured/Deadlines rows show this because they're displayed
/// outside the parent thread's pane. Deliberately not orange (that's
/// reserved for the deadline chip vocabulary) and not accent-colored
/// (that's the "Next" treatment). Reads as metadata.
private struct ThreadTagCapsule: View {
  let label: String

  var body: some View {
    Text(label)
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .truncationMode(.tail)
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .background(
        Capsule(style: .continuous)
          .fill(Color.secondary.opacity(0.12))
      )
      .accessibilityLabel("Thread \(label)")
  }
}

// MARK: - Hover-action icon button

/// Small icon button intended for hover-revealed row affordances. Uses
/// `.borderless` so it doesn't draw a chip outline, `.controlSize(.small)`
/// to match the row's metrics, and a `.help` tooltip for discoverability.
/// Sized at 22pt so adjacent icons don't collide in cramped rows.
struct RowHoverActionButton: View {
  let systemName: String
  let help: String
  let role: ButtonRole?
  let action: () -> Void

  init(
    systemName: String,
    help: String,
    role: ButtonRole? = nil,
    action: @escaping () -> Void
  ) {
    self.systemName = systemName
    self.help = help
    self.role = role
    self.action = action
  }

  var body: some View {
    Button(role: role, action: action) {
      Image(systemName: systemName)
        .font(.system(size: 13, weight: .medium))
        .frame(width: 22, height: 22)
    }
    .buttonStyle(.borderless)
    .controlSize(.small)
    .help(help)
    .accessibilityLabel(help)
  }
}
