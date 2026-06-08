import SwiftUI

/// Default alert offsets editor (INITIAL-PLAN §8.3, Phase 6). Two
/// independent offset lists: reminders (`kind = .reminder`) and deadline
/// tasks (`kind = .task` with a `due_at`). Each is a small chip row with
/// a "+ Add offset" picker for one of the canonical buckets.
///
/// v1 defaults:
///   - Reminders: at due time.
///   - Deadline tasks: morning of, 1 hour before, at due time.
///
/// We render labels via `AlertOffsetLabel.describe(minutes:)` so the
/// callsite copy stays consistent.
struct AlertOffsetsSection: View {
  @Environment(AppStore.self) private var store

  /// Local edit buffer for the offset lists. We always re-resolve from
  /// the store at write time (per the Phase-5 gate idiom: don't capture
  /// a snapshot; resolve at click time).
  @State private var reminderOffsets: [Int] = []
  @State private var deadlineTaskOffsets: [Int] = []
  @State private var loaded: Bool = false

  /// Canonical buckets the "Add offset" picker offers, in minutes.
  /// Matches what §8.3 calls out plus a few intermediate values.
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
    VStack(alignment: .leading, spacing: 14) {
      sectionHeader("Default alert offsets")

      Text("New reminders and deadline tasks get these offsets when they’re first captured. Changes apply to future items; existing notifications keep their original schedule.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      offsetRow(
        label: "Reminders",
        offsets: $reminderOffsets,
        empty: "No alerts will fire."
      )
      offsetRow(
        label: "Deadline tasks",
        offsets: $deadlineTaskOffsets,
        empty: "No alerts will fire."
      )

      HStack {
        Spacer()
        Button("Save offsets", action: save)
          .buttonStyle(.borderedProminent)
          .disabled(!hasChanges)
      }
    }
    .onAppear(perform: prefillIfNeeded)
  }

  // MARK: - Rows

  @ViewBuilder
  private func offsetRow(
    label: String,
    offsets: Binding<[Int]>,
    empty: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(.callout)
        .fontWeight(.medium)
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
                offsets.wrappedValue.sort(by: >) // larger offsets first (morning-of, then 1h, then 0)
              }
            }
          }
        } label: {
          Label("Add offset", systemImage: "plus.circle")
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

  // MARK: - State sync

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
      // Phase-5 gate idiom: re-resolve from the store at write time so a
      // concurrent badge-toggle save can't clobber the field we touched.
      var copy = store.preferences
      copy.reminderOffsetsMinutes = reminderOffsets
      copy.deadlineTaskOffsetsMinutes = deadlineTaskOffsets
      await store.saveUserPreferences(copy)
    }
  }
}

// MARK: - Chip

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
    .padding(.vertical, 4)
    .background(
      Capsule().fill(Color(nsColor: .controlBackgroundColor))
    )
    .overlay(
      Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
    )
  }
}
