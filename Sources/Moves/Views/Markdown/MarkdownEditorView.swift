import SwiftUI

/// Markdown notes view. Defaults to showing the rendered preview with a
/// small pencil affordance in the top-right corner; clicking the pencil
/// flips into the editor, where a "Done" button returns to preview. If
/// the source is empty, the editor is shown directly — there's nothing
/// to preview yet and forcing the user to click anything to begin
/// writing would be silly.
///
/// Replaces an earlier side-by-side editor/preview layout, which read as
/// an IDE pane on top of a notes field — fine for a Markdown demo but
/// wrong for an app where notes are meant to be read most of the time
/// and edited occasionally. The split chrome and monospaced editor card
/// also fought with the rest of the thread-detail surface visually.
struct MarkdownEditorView: View {
  @Binding var source: String
  var placeholder: String = "Notes…"

  @State private var isEditing: Bool = false
  @State private var didConfigureMode: Bool = false

  var body: some View {
    Group {
      if shouldShowEditor {
        EditorCard(source: $source, placeholder: placeholder)
          .overlay(alignment: .topTrailing) {
            doneButton
          }
      } else {
        PreviewCard(source: source)
          .overlay(alignment: .topTrailing) {
            editButton
          }
      }
    }
    .onAppear {
      // Pick the initial mode from the source. With content → preview;
      // empty → editor. Only runs once per view appearance so the user
      // can leave the editor open after typing without snapping back.
      guard !didConfigureMode else { return }
      didConfigureMode = true
      isEditing = source.isEmpty
    }
  }

  /// We force the editor when source is empty regardless of `isEditing`,
  /// so the user always lands on a writable surface for a fresh thread.
  private var shouldShowEditor: Bool {
    isEditing || source.isEmpty
  }

  private var editButton: some View {
    Button {
      isEditing = true
    } label: {
      Image(systemName: "pencil")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(6)
        .background(
          Circle().fill(.background.secondary)
        )
        .overlay(
          Circle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .padding(10)
    .help("Edit notes")
    .accessibilityLabel("Edit notes")
  }

  /// Only useful when source is non-empty — otherwise there's nothing to
  /// switch back to (and `shouldShowEditor` would just snap us back into
  /// the editor anyway).
  @ViewBuilder
  private var doneButton: some View {
    if !source.isEmpty {
      Button {
        isEditing = false
      } label: {
        Text("Done")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.white)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(
            Capsule().fill(Color.accentColor)
          )
      }
      .buttonStyle(.plain)
      .padding(10)
      .keyboardShortcut(.return, modifiers: [.command])
      .help("Switch back to preview (⌘↩)")
      .accessibilityLabel("Done editing")
    }
  }
}

// MARK: - Editor card

private struct EditorCard: View {
  @Binding var source: String
  let placeholder: String

  var body: some View {
    ZStack(alignment: .topLeading) {
      TextEditor(text: $source)
        .font(.system(size: 13, design: .monospaced))
        .scrollContentBackground(.hidden)
        .padding(12)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )

      if source.isEmpty {
        Text(placeholder)
          .font(.system(size: 13, design: .monospaced))
          .foregroundStyle(.tertiary)
          .padding(.horizontal, 17)
          .padding(.vertical, 19)
          .allowsHitTesting(false)
      }
    }
    .frame(minHeight: 220)
  }
}

// MARK: - Preview card

private struct PreviewCard: View {
  let source: String

  var body: some View {
    ScrollView {
      rendered
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(.background.secondary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
    )
    .frame(minHeight: 220)
  }

  /// Render the Markdown source as one stacked view. We parse line-by-
  /// line to support headings + lists + paragraphs, because
  /// `AttributedString(markdown:)` with `.full` parsing options handles
  /// inline syntax but renders block-level constructs as one flat
  /// paragraph. Phase-4 decision (carried over): keep this rendering
  /// deliberately simple — headings, list items, paragraphs, blank
  /// lines, fenced code. No tables / images / footnotes; v2 candidate.
  @ViewBuilder
  private var rendered: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
        renderBlock(block)
      }
    }
  }

  @ViewBuilder
  private func renderBlock(_ block: Block) -> some View {
    switch block {
    case let .heading(level, text):
      Text(attributed(text))
        .font(.system(size: headingSize(level), weight: .semibold))
        .padding(.top, 4)
    case let .listItem(level, text):
      HStack(alignment: .top, spacing: 6) {
        Text("•")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.secondary)
        Text(attributed(text))
      }
      .padding(.leading, CGFloat(level) * 12)
    case let .paragraph(text):
      Text(attributed(text))
    case let .code(text):
      Text(text)
        .font(.system(size: 12, design: .monospaced))
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
        )
    case .blank:
      Spacer().frame(height: 4)
    }
  }

  private func headingSize(_ level: Int) -> CGFloat {
    switch level {
    case 1: return 20
    case 2: return 17
    case 3: return 15
    default: return 14
    }
  }

  private func attributed(_ text: String) -> AttributedString {
    var options = AttributedString.MarkdownParsingOptions()
    options.interpretedSyntax = .inlineOnlyPreservingWhitespace
    return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
  }

  // MARK: - Block parsing

  private enum Block {
    case heading(level: Int, text: String)
    case listItem(level: Int, text: String)
    case paragraph(String)
    case code(String)
    case blank
  }

  private var blocks: [Block] {
    var result: [Block] = []
    var paragraphBuffer: [String] = []
    var codeBuffer: [String] = []
    var inCode = false

    func flushParagraph() {
      if !paragraphBuffer.isEmpty {
        result.append(.paragraph(paragraphBuffer.joined(separator: " ")))
        paragraphBuffer.removeAll()
      }
    }
    func flushCode() {
      if inCode {
        result.append(.code(codeBuffer.joined(separator: "\n")))
        codeBuffer.removeAll()
        inCode = false
      }
    }

    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
      let raw = String(line)
      // Fenced code blocks.
      if raw.hasPrefix("```") {
        if inCode {
          flushCode()
        } else {
          flushParagraph()
          inCode = true
        }
        continue
      }
      if inCode {
        codeBuffer.append(raw)
        continue
      }
      let trimmed = raw.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty {
        flushParagraph()
        result.append(.blank)
        continue
      }
      // ATX headings (1–6 #).
      if let level = atxHeadingLevel(trimmed) {
        flushParagraph()
        let text = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        result.append(.heading(level: level, text: text))
        continue
      }
      // Unordered list.
      if let (level, text) = listItem(raw) {
        flushParagraph()
        result.append(.listItem(level: level, text: text))
        continue
      }
      paragraphBuffer.append(trimmed)
    }

    flushParagraph()
    flushCode()
    return result
  }

  private func atxHeadingLevel(_ s: String) -> Int? {
    var n = 0
    for ch in s {
      if ch == "#" { n += 1 } else { break }
    }
    guard (1...6).contains(n) else { return nil }
    let rest = s.dropFirst(n)
    if rest.isEmpty || rest.first == " " { return n }
    return nil
  }

  private func listItem(_ raw: String) -> (Int, String)? {
    var leadingSpaces = 0
    for ch in raw {
      if ch == " " { leadingSpaces += 1 } else { break }
    }
    let level = leadingSpaces / 2
    let trimmed = String(raw.dropFirst(leadingSpaces))
    guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { return nil }
    let text = String(trimmed.dropFirst(2))
    return (level, text)
  }
}
