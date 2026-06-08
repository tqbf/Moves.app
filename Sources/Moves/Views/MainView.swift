import SwiftUI

struct MainView: View {
    @Environment(MovesStore.self) private var store
    @State private var selection: Move.ID?
    @State private var newMoveTitle: String = ""
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            detail
        }
        .navigationTitle("Moves")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Move", systemImage: "plus") {
                    addFieldFocused = true
                }
                .help("Focus the new-move field")
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Moves") {
                    ForEach(store.moves) { move in
                        MoveRow(move: move)
                            .tag(move.id)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    store.delete(move)
                                }
                            }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.tint)
                TextField("Add a move…", text: $newMoveTitle)
                    .textFieldStyle(.plain)
                    .focused($addFieldFocused)
                    .onSubmit(commitAdd)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.background.secondary)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selection, let move = store.move(id: selection) {
            MoveDetail(move: move)
        } else if store.moves.isEmpty {
            ContentUnavailableView(
                "No Moves Yet",
                systemImage: "figure.walk.motion",
                description: Text("Add your first move in the sidebar.")
            )
        } else {
            ContentUnavailableView(
                "Pick a Move",
                systemImage: "hand.point.up.left",
                description: Text("Select a move from the sidebar to see its details.")
            )
        }
    }

    private func commitAdd() {
        let trimmed = newMoveTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.add(title: trimmed)
        newMoveTitle = ""
    }
}
