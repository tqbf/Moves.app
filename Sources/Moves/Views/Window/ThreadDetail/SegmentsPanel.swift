import SwiftUI

/// Phase-5 segments panel embedded inside the thread detail view for
/// regimented threads. Renders an ordered list:
///
///   - Active segment (highlighted), inline with `SegmentDetail` body
///   - Pending segments (dimmed)
///   - "Show N completed" disclosure → Done + Skipped segments collapsed
///
/// Switching, parking, and stopping do NOT touch segment status — only the
/// CompleteSegmentSheet does (§5.5). The "Mark Done" button on the active
/// row opens the sheet via `openWindow(id: PopoverWindowID.completeSegment)`
/// after staging `AppStore.pendingFlow`.
///
/// "Add segment" is an inline field at the bottom that creates a pending
/// segment via `AppStore.addSegment(...)` (always lands at the end).
struct SegmentsPanel: View {
  let thread: Thread

  @Environment(AppStore.self) private var store
  @Environment(\.openWindow) private var openWindow

  @State private var newSegmentTitle: String = ""
  @State private var showCompleted: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header

      // Render the ordered, deterministic set so insertions / reorderings
      // animate cleanly. Done/Skipped sit behind the disclosure.
      VStack(spacing: 8) {
        ForEach(activeAndPending) { segment in
          SegmentRowView(
            segment: segment,
            isActive: segment.status == .active,
            onActivate: { Task { await store.activateSegment(segment) } },
            onComplete: { openCompleteSheet(for: segment) },
            onSkip: { Task { await store.skipSegment(segment) } }
          )
        }
      }

      if !completed.isEmpty {
        DisclosureGroup(
          "Show \(completed.count) completed",
          isExpanded: $showCompleted
        ) {
          VStack(spacing: 6) {
            ForEach(completed) { segment in
              CompletedSegmentRow(segment: segment)
            }
          }
          .padding(.top, 6)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
      }

      addSegmentField
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text("Segments")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .kerning(0.5)
      Spacer()
      Text(progressLabel)
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .monospacedDigit()
    }
  }

  private var progressLabel: String {
    let done = segments.filter { $0.status == .done }.count
    return "\(done)/\(segments.count)"
  }

  // MARK: - Add new segment

  private var addSegmentField: some View {
    HStack(spacing: 8) {
      TextField("New segment title…", text: $newSegmentTitle)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 13))
        .onSubmit(commitNewSegment)
      Button("Add", action: commitNewSegment)
        .buttonStyle(.bordered)
        .disabled(newSegmentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }

  private func commitNewSegment() {
    let title = newSegmentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    newSegmentTitle = ""
    Task {
      await store.addSegment(thread: thread, title: title)
    }
  }

  // MARK: - Sheet hand-off

  private func openCompleteSheet(for segment: Segment) {
    store.pendingFlow = .completeSegment(threadId: thread.id, segmentId: segment.id)
    openWindow(id: PopoverWindowID.completeSegment.rawValue)
  }

  // MARK: - Slicing

  private var segments: [Segment] {
    (store.segmentsByThread[thread.id] ?? []).sorted { $0.orderIndex < $1.orderIndex }
  }

  private var activeAndPending: [Segment] {
    segments.filter { $0.status == .active || $0.status == .pending }
  }

  private var completed: [Segment] {
    segments.filter { $0.status == .done || $0.status == .skipped }
  }
}

// MARK: - Row: active / pending

private struct SegmentRowView: View {
  let segment: Segment
  let isActive: Bool
  let onActivate: () -> Void
  let onComplete: () -> Void
  let onSkip: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      header
      if isActive {
        SegmentDetail(segment: segment)
        actions
      } else if !segment.builtInMove.isEmpty {
        Text("Next: \(segment.builtInMove)")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(isActive ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(isActive ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
    )
    .opacity(isActive ? 1 : 0.85)
  }

  private var header: some View {
    HStack(spacing: 8) {
      Image(systemName: isActive ? "circle.dashed.inset.filled" : "circle.dashed")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
      Text(segment.title)
        .font(.system(size: 14, weight: isActive ? .semibold : .medium))
        .foregroundStyle(isActive ? .primary : .secondary)
      Spacer()
      if let label = metadataLabel {
        Text(label)
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
          .monospacedDigit()
      }
      Menu {
        if !isActive {
          Button("Make active", action: onActivate)
        }
        Button("Skip", action: onSkip)
      } label: {
        Image(systemName: "ellipsis.circle")
          .font(.system(size: 13))
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
    }
  }

  private var metadataLabel: String? {
    var bits: [String] = []
    if let est = segment.estimateMinutes { bits.append("~\(est)m") }
    if segment.dueAt != nil { bits.append("due") }
    if segment.scheduledAt != nil { bits.append("sched") }
    return bits.isEmpty ? nil : bits.joined(separator: " · ")
  }

  private var actions: some View {
    HStack(spacing: 8) {
      Spacer()
      Button("Mark Done") { onComplete() }
        .buttonStyle(.borderedProminent)
        .help("Mark this segment done, log rough time, advance to next pending segment")
    }
  }
}

// MARK: - Row: done / skipped (collapsed)

private struct CompletedSegmentRow: View {
  let segment: Segment

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 12))
        .foregroundStyle(.tertiary)
      Text(segment.title)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .strikethrough(segment.status == .done, color: .secondary)
      Spacer()
      Text(segment.status.rawValue.capitalized)
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
          Capsule().fill(Color.primary.opacity(0.05))
        )
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
  }

  private var icon: String {
    switch segment.status {
    case .done: return "checkmark.circle.fill"
    case .skipped: return "arrowshape.bounce.right.fill"
    default: return "circle"
    }
  }
}
