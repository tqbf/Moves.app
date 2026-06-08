import SwiftUI

/// Inline editor for the *active* segment, embedded inside `SegmentsPanel`.
/// Renders:
///
///   - Built-in move (single-line TextField, autosave on debounce)
///   - Body markdown (reuses `MarkdownEditorView`, autosave on debounce)
///   - Generated checklist items (read-only here — toggling happens in the
///     thread's main items list since items are per-thread, not per-segment)
///   - Optional scheduled / due / estimate metadata (read-only display)
///
/// Autosave pattern matches the Phase-4 thread-detail notes editor: 600ms
/// debounce via `.onChange(of:) { newValue in scheduleSave(newValue) }`,
/// no Save button. The lessons in PROGRESS.md call out that an explicit
/// Save button gets pushed off-screen by Markdown editors expanding into
/// vertical scroll layouts; autosave is the safe default.
struct SegmentDetail: View {
  let segment: Segment

  @Environment(AppStore.self) private var store

  @State private var move: String = ""
  @State private var body_: String = ""
  @State private var loadedSegmentId: String?

  // Debounced autosave handles for move + body.
  @State private var moveAutosave: Task<Void, Never>?
  @State private var bodyAutosave: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      moveField
      bodyField
      metadataRow
    }
    .onAppear { syncIfNeeded() }
    .onChange(of: segment.id) { _, _ in syncIfNeeded(force: true) }
  }

  // MARK: - Fields

  private var moveField: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Built-in move")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.tertiary)
          .textCase(.uppercase)
          .kerning(0.5)
        Spacer()
        if move != segment.builtInMove {
          Text("Saving…")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
      }
      TextField("e.g. Implement async Redis command loop", text: $move)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 13))
        .onChange(of: move) { _, newValue in scheduleMoveAutosave(newValue) }
    }
  }

  private var bodyField: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Body")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.tertiary)
          .textCase(.uppercase)
          .kerning(0.5)
        Spacer()
        if body_ != segment.bodyMarkdown {
          Text("Saving…")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
      }
      MarkdownEditorView(source: $body_, placeholder: "Notes, plan, or context for this segment…")
        .frame(minHeight: 160)
        .onChange(of: body_) { _, newValue in scheduleBodyAutosave(newValue) }
    }
  }

  @ViewBuilder
  private var metadataRow: some View {
    if let line = metadataLine {
      Text(line)
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }
  }

  private var metadataLine: String? {
    var parts: [String] = []
    if let scheduledAt = segment.scheduledAt {
      parts.append("Scheduled \(Self.dateLabel(scheduledAt))")
    }
    if let dueAt = segment.dueAt {
      parts.append("Due \(Self.dateLabel(dueAt))")
    }
    if let estimate = segment.estimateMinutes {
      parts.append("Estimate ~\(estimate)m")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  // MARK: - Sync

  private func syncIfNeeded(force: Bool = false) {
    if force || loadedSegmentId != segment.id {
      move = segment.builtInMove
      body_ = segment.bodyMarkdown
      loadedSegmentId = segment.id
    }
  }

  private func scheduleMoveAutosave(_ newValue: String) {
    moveAutosave?.cancel()
    moveAutosave = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 600_000_000)
      guard !Task.isCancelled else { return }
      guard newValue == move else { return }
      var copy = segment
      copy.builtInMove = newValue
      await store.editSegment(copy)
    }
  }

  private func scheduleBodyAutosave(_ newValue: String) {
    bodyAutosave?.cancel()
    bodyAutosave = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 600_000_000)
      guard !Task.isCancelled else { return }
      guard newValue == body_ else { return }
      var copy = segment
      copy.bodyMarkdown = newValue
      await store.editSegment(copy)
    }
  }

  private static func dateLabel(_ unixSeconds: Int64) -> String {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    f.doesRelativeDateFormatting = true
    return f.string(from: Date(timeIntervalSince1970: TimeInterval(unixSeconds)))
  }
}
