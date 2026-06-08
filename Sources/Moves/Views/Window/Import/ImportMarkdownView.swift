import SwiftUI
import UniformTypeIdentifiers

/// Import a regimented thread from a §9-shaped Markdown file. Three states
/// in one view:
///
///   1. Empty — drop a `.md` file or click "Choose File…".
///   2. Preview — parsed thread + segments + items + warnings. User can
///      cancel or commit. Cancel discards; Import creates rows in one
///      transaction via `AppStore.importMarkdown(_:)`.
///   3. Done — confirmation toast showing what was created.
///
/// Hosted in its own `Window` scene so the user can drag a file from
/// Finder onto it without the popover dismissing.
///
/// Re-imports of the same title produce a new thread (create-only per the
/// Phase 5 plan); the preview surfaces a warning so the user can cancel
/// before producing a duplicate.
struct ImportMarkdownView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismissWindow) private var dismissWindow

  @State private var stage: Stage = .empty
  @State private var preview: ImportPreview?
  @State private var sourceText: String = ""
  @State private var importedResult: ImportResult?
  @State private var dragTargeted: Bool = false
  @State private var errorMessage: String?

  enum Stage: Hashable { case empty, preview, done }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Import Markdown")
          .font(.system(size: 18, weight: .semibold))
        Text("Drop a Markdown file with YAML frontmatter to create a regimented thread.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }

      switch stage {
      case .empty:
        dropTarget
      case .preview:
        if let preview { previewView(preview) }
      case .done:
        if let result = importedResult { doneView(result) }
      }

      if let error = errorMessage {
        Text(error)
          .font(.system(size: 12))
          .foregroundStyle(.red)
      }

      Spacer(minLength: 0)

      footer
    }
    .padding(22)
    .frame(width: 560, height: 540)
  }

  // MARK: - Drop target

  private var dropTarget: some View {
    VStack(spacing: 14) {
      Image(systemName: "doc.text.fill")
        .font(.system(size: 36))
        .foregroundStyle(dragTargeted ? Color.accentColor : Color.secondary)
      Text(dragTargeted ? "Drop to parse" : "Drop a .md file here")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.secondary)
      Button("Choose File…", action: openFilePicker)
        .buttonStyle(.bordered)
    }
    .frame(maxWidth: .infinity, minHeight: 280)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(dragTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(
          dragTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
          style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
        )
    )
    .onDrop(of: [.fileURL], isTargeted: $dragTargeted) { providers in
      handleDrop(providers)
    }
  }

  // MARK: - Preview state

  @ViewBuilder
  private func previewView(_ preview: ImportPreview) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          Text(preview.thread.title)
            .font(.system(size: 16, weight: .semibold))
          Text("\(preview.thread.kind.rawValue.capitalized) thread · \(preview.segments.count) segment\(preview.segments.count == 1 ? "" : "s") · \(preview.items.count) item\(preview.items.count == 1 ? "" : "s")")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }

        if !preview.warnings.isEmpty {
          warnings(preview.warnings)
        }

        if !preview.segments.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(preview.segments) { segment in
              segmentRow(segment, items: preview.items.filter { $0.segmentId == segment.id })
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxHeight: 380)
  }

  private func segmentRow(_ segment: Segment, items: [Item]) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(segment.title)
          .font(.system(size: 13, weight: .medium))
        Spacer()
        if segment.status == .active {
          Text("ACTIVE")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor))
        }
      }
      if !segment.builtInMove.isEmpty {
        Text("Move: \(segment.builtInMove)")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
      if !items.isEmpty {
        Text("\(items.count) checklist item\(items.count == 1 ? "" : "s")")
          .font(.system(size: 10))
          .foregroundStyle(.tertiary)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.primary.opacity(0.04))
    )
  }

  private func warnings(_ messages: [String]) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
        HStack(alignment: .top, spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundStyle(Color.orange)
          Text(message)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.orange.opacity(0.08))
    )
  }

  // MARK: - Done state

  private func doneView(_ result: ImportResult) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "checkmark.seal.fill")
          .foregroundStyle(Color.accentColor)
        Text("Imported \(result.segmentCount) segment\(result.segmentCount == 1 ? "" : "s") and \(result.itemCount) item\(result.itemCount == 1 ? "" : "s").")
          .font(.system(size: 13, weight: .medium))
      }
      if !result.warnings.isEmpty {
        warnings(result.warnings)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.green.opacity(0.08))
    )
  }

  // MARK: - Footer

  private var footer: some View {
    HStack(spacing: 8) {
      Spacer()
      switch stage {
      case .empty:
        Button("Close", role: .cancel) { close() }
          .keyboardShortcut(.cancelAction)
      case .preview:
        Button("Discard", role: .cancel) { resetToEmpty() }
          .keyboardShortcut(.cancelAction)
        Button("Import", action: commitImport)
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(preview == nil)
      case .done:
        Button("Close") { close() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      }
    }
  }

  // MARK: - Actions

  private func openFilePicker() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.plainText, .text, UTType(filenameExtension: "md") ?? .data]
    panel.title = "Choose a Markdown file"
    if panel.runModal() == .OK, let url = panel.url {
      loadFile(at: url)
    }
  }

  private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
    guard let provider = providers.first else { return false }
    _ = provider.loadObject(ofClass: URL.self) { url, _ in
      guard let url else { return }
      Task { @MainActor in
        loadFile(at: url)
      }
    }
    return true
  }

  private func loadFile(at url: URL) {
    do {
      let text = try String(contentsOf: url, encoding: .utf8)
      sourceText = text
      preview = MarkdownImportService.parse(text)
      stage = .preview
      errorMessage = nil
    } catch {
      errorMessage = "Could not read file: \(error.localizedDescription)"
    }
  }

  private func commitImport() {
    guard preview != nil else { return }
    Task {
      let result = await store.importMarkdown(sourceText)
      if let result {
        importedResult = result
        stage = .done
      } else {
        errorMessage = store.loadError ?? "Import failed."
      }
    }
  }

  private func resetToEmpty() {
    preview = nil
    sourceText = ""
    stage = .empty
  }

  private func close() {
    preview = nil
    sourceText = ""
    importedResult = nil
    stage = .empty
    errorMessage = nil
    dismissWindow(id: PopoverWindowID.importMarkdown.rawValue)
  }
}
