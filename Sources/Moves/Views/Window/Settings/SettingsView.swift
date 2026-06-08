import SwiftUI

/// Main-window Settings pane. Phase 4 shipped the working-hours editor;
/// Phase 6 adds default alert offsets (§8.3), the menu-bar badge toggle,
/// the capture-shortcut rebind, an onboarding-rerun affordance, and the
/// SQLite + Markdown export buttons.
///
/// One vertical scroll with explicit sub-sections. The cards share a
/// padded-rounded-rect background so the pane reads as several discrete
/// settings groups without resorting to a SwiftUI `Form` (which on macOS
/// is heavier than this pane needs).
struct SettingsView: View {
  var body: some View {
    PaneShell(title: "Settings", subtitle: "Working hours · alerts · backup · onboarding") {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          card { WorkingHoursSection() }
          card { AlertOffsetsSection() }
          card { BadgeAndOnboardingSection() }
          card { ExportSection() }
        }
        .padding(.vertical, 4)
      }
    }
  }

  @ViewBuilder
  private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(.background.secondary)
      )
  }
}

/// Working-hours editor — pulled out of the old monolithic `SettingsView`
/// so Phase 6's additions are siblings rather than appended to one giant
/// pile. Behavior is unchanged from Phase 4.
struct WorkingHoursSection: View {
  @Environment(AppStore.self) private var store

  @State private var days: Set<Int> = []
  @State private var startDate: Date = Date()
  @State private var endDate: Date = Date()
  @State private var loaded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader("Working hours")

      weekdayPicker
      timeRow

      HStack {
        Text(currentStateLine)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Save working hours", action: save)
          .buttonStyle(.borderedProminent)
          .disabled(!hasChanges)
      }
    }
    .onAppear(perform: prefillIfNeeded)
  }

  private var weekdayPicker: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Days")
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
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
              .frame(minWidth: 38)
              .padding(.vertical, 6)
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

  private var timeRow: some View {
    HStack(spacing: 20) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Start")
          .font(.caption)
          .fontWeight(.medium)
          .foregroundStyle(.secondary)
        DatePicker("", selection: $startDate, displayedComponents: .hourAndMinute)
          .labelsHidden()
      }
      VStack(alignment: .leading, spacing: 6) {
        Text("End")
          .font(.caption)
          .fontWeight(.medium)
          .foregroundStyle(.secondary)
        DatePicker("", selection: $endDate, displayedComponents: .hourAndMinute)
          .labelsHidden()
      }
      Spacer()
    }
  }

  private var currentStateLine: String {
    let state = store.isWorkTime ? "Inside working hours" : "Outside working hours"
    let dayCount = store.workingHours.days.count
    return "\(state) · \(dayCount) day\(dayCount == 1 ? "" : "s") active"
  }

  // MARK: - State sync

  private func prefillIfNeeded() {
    guard !loaded else { return }
    loaded = true
    days = store.workingHours.days
    startDate = dateFromMinute(store.workingHours.startMinute)
    endDate = dateFromMinute(store.workingHours.endMinute)
  }

  private var hasChanges: Bool {
    let pending = pendingHours
    return pending != store.workingHours
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
