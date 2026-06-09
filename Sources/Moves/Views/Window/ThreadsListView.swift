import SwiftUI

/// "Threads" pane in the main window (INITIAL-PLAN §4.2). All threads,
/// grouped by status, with an inline "New thread…" field at the top.
/// Selecting a row routes to the thread detail. Swipe-left on a row to
/// delete the thread.
///
/// This is the editing/organizing entry point — the popover is for daily-
/// driver flow, this pane is for "give me the whole list".
struct ThreadsListView: View {
  @Environment(AppStore.self) private var store
  var onSelectThread: (String) -> Void

  @State private var newTitle: String = ""
  @FocusState private var addFocused: Bool
  /// Cmd-N from the App-scope menu flips `signals.requestNewThread`; we
  /// focus the inline "New thread…" field and clear the flag so a
  /// subsequent Cmd-N (which goes false → true again) refocuses cleanly.
  @Bindable private var signals = AppSignals.shared

  /// Selected row drives the inspector summary.
  @State private var selection: String?
  @SceneStorage("inspector.threads.visible") private var inspectorVisible = false

  var body: some View {
    PaneListShell(
      title: "Threads",
      count: store.threads.count,
      accessory: { headerAccessory },
      content: { content },
      inspector: {
        InspectorColumn(isVisible: $inspectorVisible) { inspectorBody }
      }
    )
    .onChange(of: signals.requestNewThread) { _, requested in
      if requested { focusNewThreadInput() }
    }
    .onAppear {
      // Handle the case where the user fired Cmd-N before this view
      // mounted (e.g. switching from the Available pane). RootWindow
      // flipped selection but left the flag set; pick it up here.
      if signals.requestNewThread { focusNewThreadInput() }
    }
  }

  @ViewBuilder
  private var headerAccessory: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.18)) { inspectorVisible.toggle() }
    } label: {
      Label("Toggle inspector", systemImage: "sidebar.right")
        .labelStyle(.iconOnly)
    }
    .buttonStyle(.borderless)
    .help(inspectorVisible ? "Hide inspector" : "Show inspector")
  }

  @ViewBuilder
  private var content: some View {
    VStack(spacing: 0) {
      newRow
        .padding(.horizontal, PaneMetrics.horizontalInset)
        .padding(.top, PaneMetrics.headerToContentSpacing)
        .padding(.bottom, 6)
      if store.threads.isEmpty {
        // Batch 8, item 28 — designed empty state. The new-thread row
        // stays mounted above (it's the action), and the empty view
        // points the user at it. Tapping "New thread…" focuses the
        // inline field via the same path Cmd-N uses.
        ContentUnavailableView {
          Label("No threads yet", systemImage: "square.stack.3d.up")
        } description: {
          Text("Threads are the units of ongoing work in Moves. Create one to get started.")
        } actions: {
          Button("New thread…") { focusNewThreadInput() }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(selection: $selection) {
          section("Active", threads: store.threads(matching: .active))
          section("Parked", threads: store.threads(matching: .parked))
          section("Done", threads: store.threads(matching: .done))
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
      }
    }
  }

  @ViewBuilder
  private var inspectorBody: some View {
    if let id = selection, let thread = store.thread(id: id) {
      InspectorDetail(
        title: thread.title,
        subtitle: thread.breadcrumb.isEmpty ? nil : "Next: \(thread.breadcrumb)",
        metadata: [
          ("Status", thread.status.rawValue.capitalized),
          ("Kind", thread.kind.rawValue.capitalized)
        ]
      ) {
        Button("Open thread") { onSelectThread(thread.id) }
          .buttonStyle(.borderedProminent)
      }
    } else {
      InspectorEmptyState(
        title: "Nothing selected",
        systemImage: "rectangle.stack",
        message: "Pick a thread to see its breadcrumb and open it. Cmd-N adds a new thread.",
        actionLabel: "New thread",
        action: { signals.requestNewThreadFlow() }
      )
    }
  }

  /// Defer the focus assignment one runloop tick so it doesn't race the
  /// TextField's mount (same idiom as `CapturePaletteView.onAppear`).
  /// Clear the signal once we've taken it so a future request can
  /// refire `.onChange`.
  private func focusNewThreadInput() {
    DispatchQueue.main.async {
      addFocused = true
      signals.clearNewThreadRequest()
    }
  }

  // MARK: - New row

  /// Inline composer at the top of the Threads pane. Native idiom is the
  /// Reminders "+ New Reminder" row: a card that reads as editable, not
  /// disabled. The previous treatment leaned on `.background.secondary`
  /// fill + a system-tertiary placeholder — together they looked exactly
  /// like a disabled control. Bumped contrast on three axes: a slightly
  /// more present `.quaternary` fill, a thin separator stroke that turns
  /// accent-tinted on focus (mirrors the macOS focus ring), and a body-
  /// sized field with `.primary` foreground for typed text. The whole row
  /// is the hit target — tapping the icon, the padding, or the inert area
  /// to the right all focus the field. Aux text "Press ⏎ to add" replaces
  /// the floating "Add" button so the row stays a single horizontal slot.
  private var newRow: some View {
    HStack(spacing: 10) {
      Image(systemName: "plus.circle.fill")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
      TextField("New thread", text: $newTitle, prompt: Text("New thread"))
        .textFieldStyle(.plain)
        .font(.body)
        .foregroundStyle(.primary)
        .focused($addFocused)
        .onSubmit(commitNew)
        .accessibilityLabel("New thread title")
      Spacer(minLength: 6)
      if newTitle.isEmpty {
        Text("Press \u{23CE} to add")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      } else {
        Button("Add", action: commitNew)
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(.quaternary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(
          addFocused ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
          lineWidth: addFocused ? 1.5 : 0.5
        )
    )
    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .onTapGesture { addFocused = true }
    .animation(.easeInOut(duration: 0.12), value: addFocused)
  }

  private func commitNew() {
    let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    newTitle = ""
    Task {
      if let id = await store.createThread(title: trimmed) {
        onSelectThread(id)
      }
    }
  }

  // MARK: - Sections

  @ViewBuilder
  private func section(_ title: String, threads: [Thread]) -> some View {
    if !threads.isEmpty {
      Section(title) {
        ForEach(threads) { thread in
          ThreadRowSummary(
            thread: thread,
            isSelected: selection == thread.id,
            action: { onSelectThread(thread.id) },
            onRename: { newTitle in store.rename(thread, to: newTitle) }
          )
            .tag(thread.id)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
              top: PaneMetrics.listRowVertical,
              leading: PaneMetrics.listRowLeading,
              bottom: PaneMetrics.listRowVertical,
              trailing: PaneMetrics.listRowTrailing
            ))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button(role: .destructive) {
                store.delete(thread)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
        }
      }
    }
  }
}

private struct ThreadRowSummary: View {
  let thread: Thread
  var isSelected: Bool = false
  let action: () -> Void
  /// Closure-style rename so the row can present a `RenameThreadSheet`
  /// without reaching for AppStore.
  let onRename: (String) -> Void

  @Environment(AppStore.self) private var store
  @State private var renaming: Bool = false

  var body: some View {
    Button(action: action) {
      // Thread rows aren't task-shaped (no deadline, no thread tag — they
      // ARE the thread). Reuse `TaskRow` for the same metrics + anatomy
      // so the eye sees the same row density across panes, but feed it
      // only the title + breadcrumb.
      TaskRow(
        title: thread.title,
        subtitle: secondaryLine,
        isSelected: isSelected
      )
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button("Open") { action() }
      Button("Rename…") { renaming = true }
      Divider()
      Button("Mark Active") { store.setStatus(thread, to: .active) }
        .disabled(thread.status == .active)
      Button("Park") { store.setStatus(thread, to: .parked) }
        .disabled(thread.status == .parked)
      Button("Mark Done") { store.setStatus(thread, to: .done) }
        .disabled(thread.status == .done)
      Divider()
      Button("Delete", role: .destructive) { store.delete(thread) }
    }
    .sheet(isPresented: $renaming) {
      RenameThreadSheet(
        currentTitle: thread.title,
        onSave: { newTitle in
          onRename(newTitle)
          renaming = false
        },
        onCancel: { renaming = false }
      )
    }
  }

  private var secondaryLine: String {
    if !thread.breadcrumb.isEmpty { return thread.breadcrumb }
    return thread.status.rawValue.capitalized
  }
}
