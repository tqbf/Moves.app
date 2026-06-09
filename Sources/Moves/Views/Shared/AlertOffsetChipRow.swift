import SwiftUI

/// Multi-select chip row over the canonical alert-offset buckets
/// (`[0, 15, 30, 60, 120, 24*60]`). Each chip is an independent toggle.
/// Used by:
///
///   - the capture palette (`CapturePaletteView`), shown only when the
///     live parse recognized a deadline,
///   - the captured-row "Edit due time" sheet, shown only when the user
///     has the deadline toggle on.
///
/// Idiom: `Toggle(isOn:)` + `.toggleStyle(.button)` + `.controlSize(.small)`.
/// This is the native macOS multi-select chip pattern — System Settings
/// uses the same shape for "Filter by" pills in Mail. Selected chips read
/// as filled buttons (the OS handles the accent tint); unselected chips
/// are bordered/secondary. Accessibility comes for free: each chip is an
/// announced toggle with its label.
struct AlertOffsetChipRow: View {

  /// Canonical chip set: "At due", "15m", "30m", "1h", "2h", "Morning of".
  /// Mirrors the offsets the Settings → Alerts pane writes out as
  /// `reminderOffsetsMinutes` / `deadlineTaskOffsetsMinutes` defaults.
  static let canonicalOffsets: [Int] = [0, 15, 30, 60, 120, 24 * 60]

  /// Short chip label, distinct from the verbose `AlertOffsetLabel.describe`
  /// shape used in Settings ("15m before", "morning of"). The chip surface
  /// is tight; the row's leading "Alert me:" carries the "before" framing.
  static func chipLabel(for minutes: Int) -> String {
    switch minutes {
    case 0: return "At due"
    case 15: return "15m"
    case 30: return "30m"
    case 60: return "1h"
    case 120: return "2h"
    case 24 * 60: return "Morning of"
    default:
      // Fallback covers any future bucket the canonical list grows to
      // carry without forcing a UI update.
      return AlertOffsetLabel.describe(minutes: minutes)
    }
  }

  /// The currently selected offsets, as a Set of minutes-before-due. The
  /// parent owns this — `editDueAt` / `capture` read it on save.
  @Binding var selection: Set<Int>

  /// Optional leading label. When nil, the chip row renders without one
  /// (used inside the edit-due sheet where a Form `LabeledContent` provides
  /// the label).
  var leadingLabel: String? = "Alert me:"

  var body: some View {
    HStack(alignment: .center, spacing: 6) {
      if let leadingLabel {
        Text(leadingLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
      ForEach(Self.canonicalOffsets, id: \.self) { offset in
        Toggle(
          isOn: Binding(
            get: { selection.contains(offset) },
            set: { isOn in
              if isOn {
                selection.insert(offset)
              } else {
                selection.remove(offset)
              }
            }
          )
        ) {
          // No explicit font — `.toggleStyle(.button)` +
          // `.controlSize(.small)` resolves to the system's small-control
          // typography, which Dynamic Type scales correctly. Forcing
          // size: 11 / weight: .medium fought both the system metric
          // and the Mail / System Settings filter-pill idiom this row
          // intentionally mirrors.
          Text(Self.chipLabel(for: offset))
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .accessibilityLabel("Alert \(Self.chipLabel(for: offset)) before due")
      }
    }
  }
}
