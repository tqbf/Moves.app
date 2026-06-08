import SwiftUI

struct MoveRow: View {
    let move: Move
    @Environment(MovesStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            Button {
                store.toggle(move)
            } label: {
                Image(systemName: move.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(move.done ? Color.accentColor : .secondary)
                    .symbolEffect(.bounce, value: move.done)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(move.done ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 1) {
                Text(move.title)
                    .font(.body)
                    .strikethrough(move.done, color: .secondary)
                    .foregroundStyle(move.done ? .secondary : .primary)
                    .lineLimit(1)
                Text(move.created, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
