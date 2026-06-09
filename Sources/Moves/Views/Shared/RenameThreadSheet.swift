import SwiftUI

/// Minimal rename sheet — text field + cancel/save. Used by any pane
/// that surfaces "Rename thread" through a context menu (Available,
/// Threads). Kept deliberately small: the rename action mutates a single
/// scalar, so a full sheet with toggles would be overkill; a system-modal
/// alert with a TextField is the macOS idiom but doesn't compose cleanly
/// with `@FocusState`, so we use a small sheet instead.
///
/// Save is disabled when the trimmed draft is empty or unchanged so the
/// flow can't accidentally clear or no-op the title. Enter saves, Escape
/// cancels — both wired through `.keyboardShortcut`.
struct RenameThreadSheet: View {
  let currentTitle: String
  let onSave: (String) -> Void
  let onCancel: () -> Void

  @State private var draft: String = ""
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Rename thread")
        .font(.system(size: 16, weight: .semibold))

      TextField("Thread title", text: $draft)
        .textFieldStyle(.roundedBorder)
        .focused($focused)
        .onSubmit(save)

      HStack {
        Spacer()
        Button("Cancel", role: .cancel, action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button("Save", action: save)
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(trimmed.isEmpty || trimmed == currentTitle)
      }
    }
    .padding(20)
    .frame(width: 360)
    .onAppear {
      draft = currentTitle
      DispatchQueue.main.async { focused = true }
    }
  }

  private var trimmed: String {
    draft.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func save() {
    guard !trimmed.isEmpty, trimmed != currentTitle else { return }
    onSave(trimmed)
  }
}
