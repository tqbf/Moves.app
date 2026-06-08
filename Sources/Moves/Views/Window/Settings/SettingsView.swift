import SwiftUI

/// Settings pane in the main window (INITIAL-PLAN §4.2, §6). Phase 4 owns
/// working hours only — other settings (hotkey rebind, theme, export)
/// land in Phase 6.
struct SettingsView: View {
  @Environment(AppStore.self) private var store

  @State private var days: Set<Int> = []
  @State private var startDate: Date = Date()
  @State private var endDate: Date = Date()
  @State private var loaded = false

  var body: some View {
    PaneShell(title: "Settings", subtitle: "Working hours · §6 visibility behavior") {
      VStack(alignment: .leading, spacing: 16) {
        weekdayPicker
        timeRow
        HStack {
          Text(currentStateLine)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
          Spacer()
          Button("Save", action: save)
            .buttonStyle(.borderedProminent)
            .disabled(!hasChanges)
        }

        Divider()
        Text("Other settings (hotkey rebind, export, alert reconciliation) land in Phase 6.")
          .font(.system(size: 12))
          .foregroundStyle(.tertiary)
      }
      .padding(20)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(.background.secondary)
      )
    }
    .onAppear(perform: prefillIfNeeded)
  }

  private var weekdayPicker: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Days")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .kerning(0.5)
      HStack(spacing: 6) {
        ForEach(WorkingHoursWeekday.allCases, id: \.self) { day in
          let isOn = days.contains(day.rawValue)
          Button {
            if isOn { days.remove(day.rawValue) } else { days.insert(day.rawValue) }
          } label: {
            Text(day.shortLabel)
              .font(.system(size: 12, weight: isOn ? .semibold : .regular))
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
        }
      }
    }
  }

  private var timeRow: some View {
    HStack(spacing: 20) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Start")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.tertiary)
          .textCase(.uppercase)
          .kerning(0.5)
        DatePicker("", selection: $startDate, displayedComponents: .hourAndMinute)
          .labelsHidden()
      }
      VStack(alignment: .leading, spacing: 6) {
        Text("End")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.tertiary)
          .textCase(.uppercase)
          .kerning(0.5)
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
