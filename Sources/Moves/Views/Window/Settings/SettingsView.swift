import KeyboardShortcuts
import SwiftUI

/// The Settings scene root. Hosted by the SwiftUI `Settings` scene in
/// `MovesApp`, so the system wires up Cmd-, and the "Moves →
/// Settings…" menu item for free.
///
/// Four tabs, matching the System Settings idiom on modern macOS:
/// General, Working Hours, Alerts, Backup. Each tab is its own `Form`
/// with `.formStyle(.grouped)` — the same look the system uses for
/// Network, Notifications, etc. The window is fixed-size; tabs share a
/// width but the system sizes vertically to whichever tab is frontmost.
struct SettingsView: View {
  enum Tab: String, Hashable {
    case general
    case workingHours
    case alerts
    case backup
  }

  @State private var selection: Tab = .general

  var body: some View {
    TabView(selection: $selection) {
      GeneralSettingsTab()
        .tabItem { Label("General", systemImage: "gearshape") }
        .tag(Tab.general)

      WorkingHoursSettingsTab()
        .tabItem { Label("Working Hours", systemImage: "clock") }
        .tag(Tab.workingHours)

      AlertsSettingsTab()
        .tabItem { Label("Alerts", systemImage: "bell") }
        .tag(Tab.alerts)

      BackupSettingsTab()
        .tabItem { Label("Backup", systemImage: "externaldrive") }
        .tag(Tab.backup)
    }
    .frame(width: 520, height: 420)
  }
}

// MARK: - General

/// Menu-bar badge toggle, capture shortcut rebind, "Show onboarding
/// again" button. Render-level or one-shot preferences — nothing that
/// reshapes the data model.
struct GeneralSettingsTab: View {
  @Environment(AppStore.self) private var store

  @State private var badgeEnabled: Bool = true
  @State private var loaded: Bool = false

  var body: some View {
    Form {
      Section {
        Toggle("Show due/overdue badge in the menu bar", isOn: $badgeEnabled)
          .onChange(of: badgeEnabled) { _, _ in saveBadge() }
      } header: {
        Text("Menu bar")
      } footer: {
        Text("Adds the count next to the menu bar icon and to the popover header.")
      }

      Section("Capture") {
        LabeledContent("Capture shortcut") {
          KeyboardShortcuts.Recorder(for: .capture)
        }
      }

      Section("Onboarding") {
        LabeledContent("Welcome flow") {
          Button("Show onboarding again") {
            Task {
              await store.resetOnboarding()
              OnboardingPresenter.shared.requestPresent()
            }
          }
        }
      }
    }
    .formStyle(.grouped)
    .scrollBounceBehavior(.basedOnSize)
    .onAppear(perform: prefillIfNeeded)
  }

  private func prefillIfNeeded() {
    guard !loaded else { return }
    loaded = true
    badgeEnabled = store.preferences.badgeEnabled
  }

  private func saveBadge() {
    guard badgeEnabled != store.preferences.badgeEnabled else { return }
    Task {
      var copy = store.preferences
      copy.badgeEnabled = badgeEnabled
      await store.saveUserPreferences(copy)
    }
  }
}

// MARK: - Working Hours

/// Working-hours editor (INITIAL-PLAN §6). Days picker + start/end times,
/// rendered as a Form so it matches the standard macOS settings look.
struct WorkingHoursSettingsTab: View {
  @Environment(AppStore.self) private var store

  @State private var days: Set<Int> = []
  @State private var startDate: Date = Date()
  @State private var endDate: Date = Date()
  @State private var loaded: Bool = false

  var body: some View {
    Form {
      Section {
        weekdayPicker
        LabeledContent("Start") {
          DatePicker("", selection: $startDate, displayedComponents: .hourAndMinute)
            .labelsHidden()
        }
        LabeledContent("End") {
          DatePicker("", selection: $endDate, displayedComponents: .hourAndMinute)
            .labelsHidden()
        }
      } header: {
        Text("Working hours")
      } footer: {
        Text(currentStateLine)
      }

      Section {
        HStack {
          Spacer()
          Button("Save", action: save)
            .buttonStyle(.borderedProminent)
            .disabled(!hasChanges)
        }
      }
    }
    .formStyle(.grouped)
    .scrollBounceBehavior(.basedOnSize)
    .onAppear(perform: prefillIfNeeded)
  }

  private var weekdayPicker: some View {
    LabeledContent("Days") {
      HStack(spacing: 6) {
        ForEach(WorkingHoursWeekday.allCases, id: \.self) { day in
          let isOn = days.contains(day.rawValue)
          Button {
            if isOn { days.remove(day.rawValue) } else { days.insert(day.rawValue) }
          } label: {
            Text(day.shortLabel)
              .font(.callout)
              .fontWeight(isOn ? .semibold : .regular)
              .foregroundStyle(isOn ? Color.white : Color.primary)
              .frame(minWidth: 34)
              .padding(.vertical, 5)
              .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                  .fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
              )
              .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                  .strokeBorder(Color(nsColor: .separatorColor), lineWidth: isOn ? 0 : 1)
              )
          }
          .buttonStyle(.plain)
          .accessibilityLabel("\(day.fullLabel) \(isOn ? "selected" : "not selected")")
        }
      }
    }
  }

  private var currentStateLine: String {
    let state = store.isWorkTime ? "Inside working hours." : "Outside working hours."
    let dayCount = store.workingHours.days.count
    return "\(state) \(dayCount) day\(dayCount == 1 ? "" : "s") active."
  }

  private func prefillIfNeeded() {
    guard !loaded else { return }
    loaded = true
    days = store.workingHours.days
    startDate = dateFromMinute(store.workingHours.startMinute)
    endDate = dateFromMinute(store.workingHours.endMinute)
  }

  private var hasChanges: Bool {
    pendingHours != store.workingHours
  }

  private var pendingHours: WorkingHours {
    WorkingHours(
      days: days,
      startMinute: minuteFromDate(startDate),
      endMinute: minuteFromDate(endDate)
    )
  }

  private func save() {
    Task { await store.saveWorkingHours(pendingHours) }
  }

  private func dateFromMinute(_ minute: Int) -> Date {
    var components = DateComponents()
    components.hour = minute / 60
    components.minute = minute % 60
    return Calendar.current.date(from: components) ?? Date()
  }

  private func minuteFromDate(_ date: Date) -> Int {
    let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
  }
}

// MARK: - Alerts

/// Default alert offsets editor (INITIAL-PLAN §8.3). Two independent
/// offset lists for reminders and deadline tasks. Wrapped in Form so the
/// chrome matches General + Working Hours.
struct AlertsSettingsTab: View {
  @Environment(AppStore.self) private var store

  @State private var reminderOffsets: [Int] = []
  @State private var deadlineTaskOffsets: [Int] = []
  @State private var loaded: Bool = false

  /// Canonical buckets the "Add offset" picker offers, in minutes.
  /// Mirrors what §8.3 calls out plus a few intermediate values.
  private static let bucketChoices: [Int] = [
    0,
    15,
    30,
    60,
    2 * 60,
    4 * 60,
    24 * 60,
    2 * 24 * 60,
  ]

  var body: some View {
    Form {
      Section {
        offsetEditor(
          label: "Reminders",
          offsets: $reminderOffsets,
          empty: "No alerts will fire."
        )
        offsetEditor(
          label: "Deadline tasks",
          offsets: $deadlineTaskOffsets,
          empty: "No alerts will fire."
        )
      } header: {
        Text("Default alert offsets")
      } footer: {
        Text("New reminders and deadline tasks get these offsets when first captured. Changes apply to future items; existing notifications keep their original schedule.")
      }

      Section {
        HStack {
          Spacer()
          Button("Save", action: save)
            .buttonStyle(.borderedProminent)
            .disabled(!hasChanges)
        }
      }
    }
    .formStyle(.grouped)
    .scrollBounceBehavior(.basedOnSize)
    .onAppear(perform: prefillIfNeeded)
  }

  @ViewBuilder
  private func offsetEditor(
    label: String,
    offsets: Binding<[Int]>,
    empty: String
  ) -> some View {
    LabeledContent(label) {
      HStack(spacing: 6) {
        if offsets.wrappedValue.isEmpty {
          Text(empty)
            .font(.caption)
            .foregroundStyle(.tertiary)
        } else {
          ForEach(offsets.wrappedValue.indices, id: \.self) { idx in
            OffsetChip(
              minutes: offsets.wrappedValue[idx],
              onRemove: { offsets.wrappedValue.remove(at: idx) }
            )
          }
        }
        Menu {
          ForEach(Self.bucketChoices, id: \.self) { choice in
            Button(AlertOffsetLabel.describe(minutes: choice)) {
              if !offsets.wrappedValue.contains(choice) {
                offsets.wrappedValue.append(choice)
                offsets.wrappedValue.sort(by: >)
              }
            }
          }
        } label: {
          Label("Add", systemImage: "plus.circle")
            .labelStyle(.titleAndIcon)
            .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Add \(label.lowercased()) offset")
      }
    }
  }

  private func prefillIfNeeded() {
    guard !loaded else { return }
    loaded = true
    reminderOffsets = store.preferences.reminderOffsetsMinutes
    deadlineTaskOffsets = store.preferences.deadlineTaskOffsetsMinutes
  }

  private var hasChanges: Bool {
    reminderOffsets != store.preferences.reminderOffsetsMinutes
      || deadlineTaskOffsets != store.preferences.deadlineTaskOffsetsMinutes
  }

  private func save() {
    Task {
      var copy = store.preferences
      copy.reminderOffsetsMinutes = reminderOffsets
      copy.deadlineTaskOffsetsMinutes = deadlineTaskOffsets
      await store.saveUserPreferences(copy)
    }
  }
}

// MARK: - Backup

/// SQLite snapshot + Markdown bundle export (INITIAL-PLAN §18). Same
/// underlying ExportService as before — only the chrome changes.
struct BackupSettingsTab: View {
  @Environment(AppStore.self) private var store

  @State private var status: ExportStatus = .idle
  @State private var isWorking: Bool = false

  enum ExportStatus: Equatable {
    case idle
    case success(String)
    case failure(String)
  }

  var body: some View {
    Form {
      Section {
        LabeledContent("SQLite snapshot") {
          Button("Export…", action: exportSnapshot)
            .disabled(isWorking)
        }
        LabeledContent("Markdown bundle") {
          Button("Export…", action: exportMarkdown)
            .disabled(isWorking)
        }
      } header: {
        Text("Backup & export")
      } footer: {
        Text("SQLite snapshot is the canonical backup. The Markdown bundle is a human-readable copy that round-trips with Markdown import for regimented threads.")
      }

      if isWorking {
        Section {
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text("Exporting…")
              .foregroundStyle(.secondary)
            Spacer()
          }
        }
      }

      switch status {
      case .idle:
        EmptyView()
      case .success(let path):
        Section {
          Label("Export complete · \(path)", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .textSelection(.enabled)
        }
      case .failure(let message):
        Section {
          Label("Export failed · \(message)", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
        }
      }
    }
    .formStyle(.grouped)
    .scrollBounceBehavior(.basedOnSize)
  }

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

// MARK: - Shared chip

private struct OffsetChip: View {
  let minutes: Int
  let onRemove: () -> Void

  var body: some View {
    HStack(spacing: 4) {
      Text(AlertOffsetLabel.describe(minutes: minutes))
        .font(.caption)
      Button(action: onRemove) {
        Image(systemName: "xmark.circle.fill")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Remove offset \(AlertOffsetLabel.describe(minutes: minutes))")
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(
      Capsule().fill(Color(nsColor: .controlBackgroundColor))
    )
    .overlay(
      Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
    )
  }
}
