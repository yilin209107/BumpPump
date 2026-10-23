import SwiftUI

/// System Liquid Glass controls, shared by counts and load entry.
struct HomeQuantityControl: View {
  @Binding var value: String
  let title: String
  let step: Double
  let minimum: Double
  let maximum: Double
  private var number: Double? { Double(value).flatMap { $0.isFinite ? $0 : nil } }
  var body: some View {
    AppGlassGroup(spacing: 12) {
      HStack(spacing: 12) {
        Button { adjust(-step) } label: { Image(systemName: "minus").font(.system(size: 17, weight: .medium)).frame(width: 32, height: 32) }
          .modifier(AppGlassButton(prominent: true, tint: .red, circle: true)).disabled(number.map { $0 <= minimum } ?? false).accessibilityLabel(title + "减少 " + HomeFormat.number(step, digits: 1))
        TextField("—", text: $value).textFieldStyle(.plain).multilineTextAlignment(.center).font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
          .frame(width: 86, height: 48).modifier(AppGlassSurface(radius: 14)).accessibilityLabel(title)
        Button { adjust(step) } label: { Image(systemName: "plus").font(.system(size: 17, weight: .medium)).frame(width: 32, height: 32) }
          .modifier(AppGlassButton(prominent: true, tint: .blue, circle: true)).disabled(number.map { $0 >= maximum } ?? false).accessibilityLabel(title + "增加 " + HomeFormat.number(step, digits: 1))
      }
    }
  }
  private func adjust(_ delta: Double) {
    let next = min(maximum, max(minimum, (number ?? 0) + delta))
    value = next.rounded() == next ? String(Int(next)) : String(next)
  }
}
