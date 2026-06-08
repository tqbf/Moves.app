import SwiftUI

struct MoveDetail: View {
    let move: Move
    @Environment(MovesStore.self) private var store
    @State private var editingTitle: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                GroupBox("Title") {
                    TextField("Title", text: $editingTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(commitTitle)
                        .onChange(of: move.id) { _, _ in editingTitle = move.title }
                }

                GroupBox("Status") {
                    HStack {
                        Label(
                            move.done ? "Done" : "Active",
                            systemImage: move.done ? "checkmark.seal.fill" : "circle.dashed"
                        )
                        .foregroundStyle(move.done ? Color.accentColor : .secondary)
                        .font(.headline)

                        Spacer()

                        Button(move.done ? "Mark Active" : "Mark Done") {
                            store.toggle(move)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Created") {
                    Text(move.created, format: .dateTime.weekday(.wide).month().day().hour().minute())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear { editingTitle = move.title }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(move.title)
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("Move")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)
        }
    }

    private func commitTitle() {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != move.title else { return }
        store.rename(move, to: trimmed)
    }
}
