import AppKit
import SwiftUI

struct MenuBarContent: View {
    @Environment(MovesStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if store.moves.isEmpty {
                Text("No moves yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.moves.prefix(6))) { move in
                        MenuBarMoveRow(move: move)
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
            Text("\(store.pendingCount) active")
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

private struct MenuBarMoveRow: View {
    let move: Move
    @Environment(MovesStore.self) private var store

    var body: some View {
        Button {
            store.toggle(move)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: move.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(move.done ? Color.accentColor : .secondary)
                Text(move.title)
                    .lineLimit(1)
                    .strikethrough(move.done, color: .secondary)
                    .foregroundStyle(move.done ? .secondary : .primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
