import SwiftUI

/// The seven-chip rough-time row from INITIAL-PLAN §14. Used by Stop and
/// Switch sheets (Park does not use it — parking ≠ stopping).
///
/// Modeled as a single-select segmented control rendered as flat chips so
/// it looks at home in a sheet next to the breadcrumb editor. Default
/// selection is `.none` — the user explicitly opts into recording time.
struct RoughTimePicker: View {
  @Binding var selection: RoughTimeBucket

  var body: some View {
    HStack(spacing: 6) {
      ForEach(RoughTimeBucket.allCases, id: \.self) { bucket in
        chip(for: bucket)
      }
    }
  }

  private func chip(for bucket: RoughTimeBucket) -> some View {
    let isSelected = selection == bucket
    return Button {
      selection = bucket
    } label: {
      Text(bucket.label)
        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: isSelected ? 0 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Rough time \(bucket.label)")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
