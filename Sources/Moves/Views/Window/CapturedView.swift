import KeyboardShortcuts
import SwiftUI

/// "Captured" pane in the main window (INITIAL-PLAN §4.2, §13). All
/// captured-status items — the inbox. Processing actions live on each
/// row's context menu / overflow menu (`CapturedRow`). Swipe-left on a
/// row reveals a destructive Delete button.
struct CapturedView: View {
  @Environment(AppStore.self) private var store

  @State private var selection: String?

  var body: some View {
    PaneListShell(
      title: "Captured",
      count: store.capturedItems.count,
      content: { content }
    )
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

  /// Display string for the global capture hotkey, read live from the
  /// KeyboardShortcuts library so a rebind via Settings is reflected in
  /// the empty-state copy. Falls back to "⌥Space" (the default shipped
  /// in `KeyboardShortcuts.Name.capture`) so the line still reads if the
  /// shortcut is somehow unset.
  private static var captureShortcutDisplay: String {
    KeyboardShortcuts.getShortcut(for: .capture)?.description ?? "⌥Space"
  }
}
