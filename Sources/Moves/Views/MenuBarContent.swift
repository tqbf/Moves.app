import AppKit
import SwiftUI

/// Throwaway phase-1 menubar popover. Phase 3 replaces this with the real
/// Current / Upcoming / Available / Captured popover.
struct MenuBarContent: View {
  @Environment(AppStore.self) private var store
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header

      Divider()

      if store.threads.isEmpty {
        Text("No threads yet")
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(store.threads.prefix(6))) { thread in
            MenuBarThreadRow(thread: thread)
          }
        }
        .padding(.vertical, 4)
      }

      Divider()

      footer
    }
    .frame(width: 280)
    .task { await store.load() }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text("Moves")
        .font(.headline)
      Spacer()
      Text("\(store.activeCount) active")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }

  private var footer: some View {
    VStack(spacing: 0) {
      Button {
        openMainWindow()
      } label: {
        Label("Open Moves", systemImage: "macwindow")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .keyboardShortcut("o")
      .padding(.horizontal, 12)
      .padding(.vertical, 8)

      Button(role: .destructive) {
        NSApp.terminate(nil)
      } label: {
        Label("Quit Moves", systemImage: "power")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .keyboardShortcut("q")
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
    .padding(.bottom, 4)
  }

  private func openMainWindow() {
    openWindow(id: "main")
    NSApp.activate(ignoringOtherApps: true)
  }
}

private struct MenuBarThreadRow: View {
  let thread: Thread
  @Environment(AppStore.self) private var store

  var body: some View {
    Button {
      let next: ThreadStatus = thread.status == .done ? .active : .done
      store.setStatus(thread, to: next)
    } label: {
      HStack(spacing: 8) {
        Image(systemName: thread.status == .done ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(thread.status == .done ? Color.accentColor : .secondary)
        Text(thread.title)
          .lineLimit(1)
          .strikethrough(thread.status == .done, color: .secondary)
          .foregroundStyle(thread.status == .done ? .secondary : .primary)
        Spacer()
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
  }
}
