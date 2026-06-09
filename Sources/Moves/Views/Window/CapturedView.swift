import KeyboardShortcuts
import SwiftUI

/// "Captured" pane in the main window (INITIAL-PLAN §4.2, §13). All
/// captured-status items — the inbox. Processing actions live on each
/// row's context menu / overflow menu (`CapturedRow`). Swipe-left on a
/// row reveals a destructive Delete button. Click a row to surface the
/// item summary in the right inspector.
struct CapturedView: View {
  @Environment(AppStore.self) private var store

  @State private var selection: String?
  @SceneStorage("inspector.captured.visible") private var inspectorVisible = false

  var body: some View {
    PaneListShell(
      title: "Captured",
      count: store.capturedItems.count,
      accessory: { headerAccessory },
      content: { content },
      inspector: {
        InspectorColumn(isVisible: $inspectorVisible) { inspectorBody }
      }
    )
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
    if store.capturedItems.isEmpty {
      // Batch 8, item 28 — designed empty state. ContentUnavailableView
      // surfaces the capture shortcut (read live from KeyboardShortcuts so
      // a rebind via Settings is reflected here) and a button that opens
      // the same palette the global hotkey shows.
      ContentUnavailableView {
        Label("No captures yet", systemImage: "square.and.arrow.down")
      } description: {
        Text("Quick capture with \(Self.captureShortcutDisplay) — anything you type lands here.")
      } actions: {
        Button("Open capture palette") {
          CapturePaletteSingleton.shared?.show()
        }
        .buttonStyle(.borderedProminent)
      }
    } else {
      List(selection: $selection) {
        ForEach(store.capturedItems) { item in
          CapturedRow(item: item, isSelected: selection == item.id)
            .tag(item.id)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
              top: PaneMetrics.listRowVertical,
              leading: PaneMetrics.listRowLeading,
              bottom: PaneMetrics.listRowVertical,
              trailing: PaneMetrics.listRowTrailing
            ))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button(role: .destructive) {
                store.deleteItem(item)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
        }
      }
      .listStyle(.inset)
      .scrollContentBackground(.hidden)
    }
  }

  @ViewBuilder
  private var inspectorBody: some View {
    if let id = selection, let item = store.capturedItems.first(where: { $0.id == id }) {
      InspectorDetail(
        title: item.title,
        subtitle: item.bodyMarkdown.isEmpty ? nil : item.bodyMarkdown,
        metadata: metadataRows(for: item)
      ) {
        Button("Mark done") {
          Task { await store.markItemDone(item) }
        }
        .buttonStyle(.borderedProminent)
      }
    } else {
      InspectorEmptyState(
        title: "Nothing selected",
        systemImage: "tray",
        message: "Pick a captured item to triage. Hit ⌥Space to capture more.",
        actionLabel: "Open capture palette",
        action: { CapturePaletteSingleton.shared?.show() }
      )
    }
  }

  private func metadataRows(for item: Item) -> [(label: String, value: String)] {
    var rows: [(String, String)] = []
    rows.append(("Kind", item.kind.rawValue.capitalized))
    rows.append(("Status", item.status.rawValue.capitalized))
    if let due = item.dueAt {
      let date = Date(timeIntervalSince1970: TimeInterval(due))
      rows.append(("Due", Self.formatter.string(from: date)))
    }
    return rows
  }

  private static let formatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    f.timeStyle = .short
    f.doesRelativeDateFormatting = true
    return f
  }()

  /// Display string for the global capture hotkey, read live from the
  /// KeyboardShortcuts library so a rebind via Settings is reflected in
  /// the empty-state copy. Falls back to "⌥Space" (the default shipped
  /// in `KeyboardShortcuts.Name.capture`) so the line still reads if the
  /// shortcut is somehow unset.
  private static var captureShortcutDisplay: String {
    KeyboardShortcuts.getShortcut(for: .capture)?.description ?? "⌥Space"
  }
}
