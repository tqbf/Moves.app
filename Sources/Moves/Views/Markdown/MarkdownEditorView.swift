import SwiftUI

/// Plain Markdown editor + live preview (INITIAL-PLAN §17). No rich editing
/// — the text field stores plain Markdown source; the preview renders it
/// through `AttributedString(markdown:)`. Code blocks land as monospaced
/// paragraphs; tables are not supported (v2 candidate, per the Phase-4
/// plan decision).
///
/// Layout: side-by-side on wide widths, tab-toggleable on narrow widths.
/// Width breakpoint is 560pt — narrower than that and the side-by-side
/// columns squeeze. `narrow` is driven by `GeometryReader`, kept local
/// to this view.
struct MarkdownEditorView: View {
  @Binding var source: String
  var placeholder: String = "Notes…"

  var body: some View {
    GeometryReader { geo in
      let narrow = geo.size.width < 560
      Group {
        if narrow {
          TabbedLayout(source: $source, placeholder: placeholder)
        } else {
          SplitLayout(source: $source, placeholder: placeholder)
        }
      }
    }
  }
}

// MARK: - Split

private struct SplitLayout: View {
  @Binding var source: String
  let placeholder: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      EditorColumn(source: $source, placeholder: placeholder)
      Divider()
      PreviewColumn(source: source)
    }
  }
}

// MARK: - Tabbed (narrow widths)

private struct TabbedLayout: View {
  @Binding var source: String
  let placeholder: String
  @State private var mode: Mode = .edit

  enum Mode: String, CaseIterable, Hashable {
    case edit, preview
  }

  var body: some View {
    VStack(spacing: 8) {
      Picker("", selection: $mode) {
        Text("Edit").tag(Mode.edit)
        Text("Preview").tag(Mode.preview)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(maxWidth: 220)

      switch mode {
      case .edit:
        EditorColumn(source: $source, placeholder: placeholder)
      case .preview:
        PreviewColumn(source: source)
      }
    }
  }
}

// MARK: - Columns

private struct EditorColumn: View {
  @Binding var source: String
  let placeholder: String

  var body: some View {
    ZStack(alignment: .topLeading) {
      TextEditor(text: $source)
        .font(.system(size: 13, design: .monospaced))
        .scrollContentBackground(.hidden)
        .padding(10)
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
          .padding(.horizontal, 14)
          .padding(.vertical, 14)
          .allowsHitTesting(false)
      }
    }
    .frame(minHeight: 180)
  }
}

private struct PreviewColumn: View {
  let source: String

  var body: some View {
    ScrollView {
      if source.isEmpty {
        Text("Nothing to preview yet.")
          .font(.system(size: 12))
          .foregroundStyle(.tertiary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        rendered
          .font(.system(size: 13))
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(.background.secondary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
    )
    .frame(minHeight: 180)
  }

  /// Render the Markdown source into one stacked view. We parse the source
  /// line-by-line to support headings + lists + paragraphs, because
  /// `AttributedString(markdown:)` with `.full` parsing options handles
  /// inline syntax but renders block-level constructs as one flat paragraph.
  /// Phase-4 decision: keep this rendering deliberately simple — headings,
  /// list items, paragraphs, blank lines. Code fences land as monospaced
  /// blocks. No tables / images / footnotes; v2 candidate.
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
    // Must be followed by space or end-of-line.
    let rest = s.dropFirst(n)
    if rest.isEmpty || rest.first == " " { return n }
    return nil
  }

  private func listItem(_ raw: String) -> (Int, String)? {
    // Count leading spaces (2 spaces = 1 indent level).
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
