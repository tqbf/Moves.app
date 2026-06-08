import AppKit
import SwiftUI

/// Phase-6 export controls (INITIAL-PLAN §18). Two buttons:
///
///   - **SQLite snapshot…** — NSSavePanel for the destination, writes a
///     `VACUUM INTO` copy of the live DB. Canonical backup.
///   - **Markdown bundle…** — NSOpenPanel (chooseDirectories) for the
///     destination, writes one `.md` per thread + `captured.md` +
///     `time-log.csv`. Round-trippable with the §9 importer for
///     regimented threads.
///
/// Result is shown inline ("Export complete · path") below the buttons.
struct ExportSection: View {
  @Environment(AppStore.self) private var store

  @State private var status: Status = .idle
  @State private var isWorking: Bool = false

  enum Status: Equatable {
    case idle
    case success(String)
    case failure(String)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionHeader("Backup & export")

      Text("SQLite snapshot is the canonical backup. The Markdown bundle is a human-readable copy that round-trips with Markdown import for regimented threads.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 10) {
        Button("Export SQLite snapshot…", action: exportSnapshot)
          .disabled(isWorking)
        Button("Export Markdown bundle…", action: exportMarkdown)
          .disabled(isWorking)
        if isWorking {
          ProgressView()
            .controlSize(.small)
        }
        Spacer()
      }

      switch status {
      case .idle:
        EmptyView()
      case .success(let path):
        Label("Export complete · \(path)", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .font(.callout)
          .textSelection(.enabled)
      case .failure(let message):
        Label("Export failed · \(message)", systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .font(.callout)
      }
    }
  }

  // MARK: - Actions

  private func exportSnapshot() {
    let panel = NSSavePanel()
    panel.title = "Export SQLite snapshot"
    panel.nameFieldStringValue = "moves-snapshot-\(Self.timestamp()).sqlite3"
    panel.allowedContentTypes = []
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    isWorking = true
    Task {
      do {
        try await store.exportService().exportSnapshot(to: url)
        status = .success(url.path)
      } catch {
        status = .failure(String(describing: error))
      }
      isWorking = false
    }
  }

  private func exportMarkdown() {
    let panel = NSOpenPanel()
    panel.title = "Choose a folder for the Markdown bundle"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let base = panel.url else { return }
    let directory = base.appendingPathComponent("moves-export-\(Self.timestamp())", isDirectory: true)
    isWorking = true
    Task {
      do {
        let summary = try await store.exportService().exportMarkdownBundle(to: directory)
        status = .success("\(summary.directory.path) (\(summary.threadFileCount) threads, \(summary.capturedItemCount) captured)")
      } catch {
        status = .failure(String(describing: error))
      }
      isWorking = false
    }
  }

  // MARK: - Helpers

  /// Stable timestamp used in default filenames so back-to-back exports
  /// don't clobber each other.
  private static func timestamp() -> String {
    Self.fileNameDateFormatter.string(from: Date())
  }

  private static let fileNameDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd-HHmm"
    return f
  }()
}

// MARK: - Shared section header

/// Section header reused across the Phase-6 Settings additions (Export,
/// Alerts, Badge, Onboarding). Smaller, more compact than a SwiftUI
/// `Section` header — Settings is one long vertical pane, not a Form.
func sectionHeader(_ title: String) -> some View {
  Text(title)
    .font(.caption)
    .fontWeight(.semibold)
    .foregroundStyle(.tertiary)
    .textCase(.uppercase)
    .kerning(0.5)
}
