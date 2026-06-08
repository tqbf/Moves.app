import SwiftUI

/// Throwaway phase-1 detail. Phase 4 replaces this with the real thread
/// detail view (segments, Markdown editor, items, time log).
struct ThreadDetail: View {
  let thread: Thread
  @Environment(AppStore.self) private var store
  @State private var editingTitle: String = ""
  @State private var editingBreadcrumb: String = ""

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        header

        GroupBox("Title") {
          TextField("Title", text: $editingTitle)
            .textFieldStyle(.roundedBorder)
            .onSubmit(commitTitle)
            .onChange(of: thread.id) { _, _ in syncFields() }
        }

        GroupBox("Breadcrumb") {
          TextField("Next move…", text: $editingBreadcrumb, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...4)
            .onSubmit(commitBreadcrumb)
            .onChange(of: thread.id) { _, _ in syncFields() }
        }

        GroupBox("Status") {
          HStack {
            Label(
              thread.status.rawValue.capitalized,
              systemImage: statusIcon
            )
            .foregroundStyle(thread.status == .done ? Color.accentColor : .secondary)
            .font(.headline)

            Spacer()

            Picker("Status", selection: pickerBinding) {
              ForEach(ThreadStatus.allCases, id: \.self) { status in
                Text(status.rawValue.capitalized).tag(status)
              }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .labelsHidden()
          }
          .padding(.vertical, 4)
        }

        GroupBox("Created") {
          Text(createdDate, format: .dateTime.weekday(.wide).month().day().hour().minute())
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 0)
      }
      .padding(24)
      .frame(maxWidth: 640, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .onAppear { syncFields() }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(thread.title)
        .font(.largeTitle)
        .fontWeight(.semibold)
      Text("Thread")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .kerning(0.6)
    }
  }

  private var statusIcon: String {
    switch thread.status {
    case .active: return "circle.dashed"
    case .parked: return "pause.circle"
    case .done: return "checkmark.seal.fill"
    }
  }

  private var pickerBinding: Binding<ThreadStatus> {
    Binding(
      get: { thread.status },
      set: { store.setStatus(thread, to: $0) }
    )
  }

  private var createdDate: Date {
    Date(timeIntervalSince1970: TimeInterval(thread.createdAt))
  }

  private func syncFields() {
    editingTitle = thread.title
    editingBreadcrumb = thread.breadcrumb
  }

  private func commitTitle() {
    store.rename(thread, to: editingTitle)
  }

  private func commitBreadcrumb() {
    store.updateBreadcrumb(thread, to: editingBreadcrumb)
  }
}
