import SwiftUI

/// Thread detail (INITIAL-PLAN §4.3). Header with title/status/kind/
/// visibility, breadcrumb editor, current segment (read-only — Phase 5
/// owns segment editing), items list with done toggles, Markdown notes
/// editor.
///
/// Visibility is rendered as an inline pill in the header (Phase-4
/// open-question decision: inline pill > settings gear, one-click
/// affordance, matches §2.10's "passive display aid" spirit).
struct ThreadDetailView: View {
  let thread: Thread
  @Environment(AppStore.self) private var store

  @State private var editingTitle: String = ""
  @State private var editingBreadcrumb: String = ""
  @State private var notes: String = ""

  // Snapshot of which thread these editing buffers are tied to. SwiftUI
  // reuses View identity across @Observable updates, so we re-prefill the
  // local buffers whenever the bound thread id changes.
  @State private var loadedThreadId: String?

  // Debounced autosave for Markdown notes. The previous "Save notes"
  // button got pushed off-screen by the editor expanding to fill its
  // VStack, silently losing edits. Autosaving on a 600ms debounce
  // matches the macOS-native Notes/Bear pattern and removes the cliff.
  @State private var notesAutosave: Task<Void, Never>?

  /// Segments + open items, loaded async on appear and on thread switch.
  @State private var segments: [Segment] = []
  @State private var items: [Item] = []

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        header
        Divider()
        breadcrumbField
        currentSegmentSection
        itemsSection
        notesSection
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 24)
      .frame(maxWidth: 820, alignment: .leading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear { syncIfNeeded() }
    .onChange(of: thread.id) { _, _ in syncIfNeeded(force: true) }
  }

  // MARK: - Header

  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField("Thread title", text: $editingTitle)
        .textFieldStyle(.plain)
        .font(.system(size: 24, weight: .semibold))
        .onSubmit(commitTitle)

      HStack(spacing: 8) {
        StatusPill(thread: thread)
        KindPill(thread: thread)
        VisibilityPill(thread: thread)
      }
    }
  }

  // MARK: - Breadcrumb

  private var breadcrumbField: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Breadcrumb")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .kerning(0.5)
      TextEditor(text: $editingBreadcrumb)
        .font(.system(size: 13))
        .scrollContentBackground(.hidden)
        .frame(minHeight: 56, maxHeight: 100)
        .padding(8)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
      HStack {
        Spacer()
        Button("Save breadcrumb", action: commitBreadcrumb)
          .buttonStyle(.bordered)
          .disabled(editingBreadcrumb == thread.breadcrumb)
      }
    }
  }

  // MARK: - Current segment

  @ViewBuilder
  private var currentSegmentSection: some View {
    if thread.kind == .regimented {
      VStack(alignment: .leading, spacing: 6) {
        Text("Current segment")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.tertiary)
          .textCase(.uppercase)
          .kerning(0.5)
        if let segment = MoveResolver.displayedSegment(for: segments) {
          VStack(alignment: .leading, spacing: 4) {
            Text(segment.title)
              .font(.system(size: 14, weight: .medium))
            if !segment.builtInMove.isEmpty {
              Text("Built-in move: \(segment.builtInMove)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            Text("Segment editing lands in Phase 5.")
              .font(.system(size: 11))
              .foregroundStyle(.tertiary)
          }
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(.background.secondary)
          )
        } else {
          Text("No active segment.")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  // MARK: - Items

  private var itemsSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Items")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.tertiary)
          .textCase(.uppercase)
          .kerning(0.5)
        Spacer()
        Text("\(items.filter { $0.status == .done }.count)/\(items.count)")
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
          .monospacedDigit()
      }
      if items.isEmpty {
        Text("No items.")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
      } else {
        VStack(spacing: 0) {
          ForEach(items) { item in
            ItemRow(item: item, onToggle: { Task { await toggle(item) } })
            if item.id != items.last?.id {
              Divider().padding(.leading, 30)
            }
          }
        }
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.background.secondary)
        )
      }
    }
  }

  // MARK: - Notes

  private var notesSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Text("Notes")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.tertiary)
          .textCase(.uppercase)
          .kerning(0.5)
        Spacer()
        if notes != thread.detailMarkdown {
          Text("Saving…")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
      }
      MarkdownEditorView(source: $notes, placeholder: "Markdown notes for this thread…")
        .frame(minHeight: 240)
        .onChange(of: notes) { _, newValue in
          scheduleNotesAutosave(newValue: newValue)
        }
    }
  }

  // MARK: - Sync / commit

  private func syncIfNeeded(force: Bool = false) {
    if force || loadedThreadId != thread.id {
      editingTitle = thread.title
      editingBreadcrumb = thread.breadcrumb
      notes = thread.detailMarkdown
      loadedThreadId = thread.id
      Task { await loadRelations() }
    }
  }

  private func loadRelations() async {
    do {
      segments = thread.kind == .regimented
        ? try await store.segmentRepository.forThread(thread.id)
        : []
      items = try await store.itemRepository.forThread(thread.id)
    } catch {
      segments = []
      items = []
    }
  }

  private func commitTitle() {
    let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      editingTitle = thread.title
      return
    }
    store.rename(thread, to: trimmed)
  }

  private func commitBreadcrumb() {
    store.updateBreadcrumb(thread, to: editingBreadcrumb)
  }

  private func commitNotes() {
    store.updateDetailMarkdown(thread, to: notes)
  }

  /// Debounced autosave for Markdown notes. Each keystroke (re)schedules a
  /// commit 600ms in the future; if no further edit arrives, the commit
  /// fires. Cancels prior pending commits.
  private func scheduleNotesAutosave(newValue: String) {
    notesAutosave?.cancel()
    notesAutosave = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 600_000_000)
      guard !Task.isCancelled else { return }
      guard newValue == notes else { return } // newer keystroke superseded.
      store.updateDetailMarkdown(thread, to: newValue)
    }
  }

  private func toggle(_ item: Item) async {
    await store.toggleItemDone(item)
    await loadRelations()
  }
}

// MARK: - Pills (header)

private struct StatusPill: View {
  let thread: Thread
  @Environment(AppStore.self) private var store

  var body: some View {
    Menu {
      ForEach(ThreadStatus.allCases, id: \.self) { status in
        Button(status.rawValue.capitalized) { store.setStatus(thread, to: status) }
      }
    } label: {
      pillLabel(text: thread.status.rawValue.capitalized, icon: statusIcon)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
  }

  private var statusIcon: String {
    switch thread.status {
    case .active: return "circle.dashed"
    case .parked: return "pause.circle"
    case .done: return "checkmark.seal"
    }
  }
}

private struct KindPill: View {
  let thread: Thread
  @Environment(AppStore.self) private var store

  var body: some View {
    Menu {
      Button("Normal") { store.setKind(thread, to: .normal) }
      Button("Regimented") { store.setKind(thread, to: .regimented) }
    } label: {
      pillLabel(text: thread.kind.rawValue.capitalized, icon: thread.kind == .regimented ? "list.number" : "circle")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
  }
}

private struct VisibilityPill: View {
  let thread: Thread
  @Environment(AppStore.self) private var store

  var body: some View {
    Menu {
      Button("Normal") { store.setVisibility(thread, to: .normal) }
      Button("Hide during work") { store.setVisibility(thread, to: .hideWork) }
      Button("De-emphasize during work") { store.setVisibility(thread, to: .downweightWork) }
      Button("Only during work") { store.setVisibility(thread, to: .onlyWork) }
    } label: {
      pillLabel(text: visibilityLabel, icon: "eye")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
  }

  private var visibilityLabel: String {
    switch thread.visibility {
    case .normal: return "Always visible"
    case .hideWork: return "Hide during work"
    case .downweightWork: return "Quiet during work"
    case .onlyWork: return "Only during work"
    }
  }
}

@ViewBuilder
private func pillLabel(text: String, icon: String) -> some View {
  HStack(spacing: 4) {
    Image(systemName: icon)
      .font(.system(size: 11, weight: .semibold))
    Text(text)
      .font(.system(size: 11, weight: .semibold))
    Image(systemName: "chevron.down")
      .font(.system(size: 8, weight: .bold))
      .foregroundStyle(.tertiary)
  }
  .foregroundStyle(.secondary)
  .padding(.horizontal, 8)
  .padding(.vertical, 4)
  .background(
    Capsule(style: .continuous)
      .fill(Color.primary.opacity(0.06))
  )
}

// MARK: - Item row

private struct ItemRow: View {
  let item: Item
  let onToggle: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      Button(action: onToggle) {
        Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 16))
          .foregroundStyle(isDone ? Color.accentColor : .secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isDone ? "Mark not done" : "Mark done")

      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
          .font(.system(size: 13))
          .strikethrough(isDone, color: .secondary)
          .foregroundStyle(isDone ? .secondary : .primary)
        if let dueLabel {
          Text(dueLabel)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
      }
      Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var isDone: Bool { item.status == .done }

  private var dueLabel: String? {
    guard let due = item.dueAt else { return nil }
    let date = Date(timeIntervalSince1970: TimeInterval(due))
    let f = DateFormatter()
    f.dateStyle = .short
    f.timeStyle = .short
    f.doesRelativeDateFormatting = true
    return f.string(from: date)
  }
}
