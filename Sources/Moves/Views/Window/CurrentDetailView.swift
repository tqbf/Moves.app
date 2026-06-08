import SwiftUI

/// "Current" pane in the main window (INITIAL-PLAN §4.2). Shows what the
/// app considers the current thread — the same row the menu-bar Current
/// section displays, presented for the larger surface. Clicking "Open
/// thread" routes to the thread detail; Stop / Park use the popover-
/// based flow windows so the editing UX stays identical across surfaces.
struct CurrentDetailView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.openWindow) private var openWindow
  var onSelectThread: (String) -> Void

  var body: some View {
    PaneShell(title: "Current") {
      if let thread = store.thread(id: store.current.threadId ?? "") {
        VStack(alignment: .leading, spacing: 14) {
          VStack(alignment: .leading, spacing: 6) {
            Text(thread.title)
              .font(.system(size: 20, weight: .semibold))
            if !thread.breadcrumb.isEmpty {
              Text("Next: \(thread.breadcrumb)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
            if let started = startedAt(thread) {
              Text("Started \(started, format: .relative(presentation: .named))")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            }
          }

          HStack(spacing: 8) {
            Button("Open thread") { onSelectThread(thread.id) }
              .buttonStyle(.borderedProminent)

            Button("Stop") {
              store.pendingFlow = .stop(threadId: thread.id)
              openWindow(id: PopoverWindowID.stop.rawValue)
            }
            .buttonStyle(.bordered)

            Button("Park") {
              store.pendingFlow = .park(threadId: thread.id)
              openWindow(id: PopoverWindowID.park.rawValue)
            }
            .buttonStyle(.bordered)
          }
        }
        .padding(16)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.background.secondary)
        )
      } else {
        ContentUnavailableView(
          "Not working on anything",
          systemImage: "play.slash",
          description: Text("Click a row in Available — or open the menu-bar popover — to start a thread.")
        )
      }
    }
  }

  private func startedAt(_ thread: Thread) -> Date? {
    guard store.current.threadId == thread.id,
          let started = store.current.startedAt
    else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(started))
  }
}
