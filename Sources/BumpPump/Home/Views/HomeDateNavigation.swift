import SwiftUI

struct HomeDateNavigation: View {
  @ObservedObject var state: HomeState
  var body: some View {
    HStack(spacing: 5) {
      DatePicker("选择年月日", selection: $state.selectedDate, in: state.availableDates, displayedComponents: .date)
        .datePickerStyle(.field).labelsHidden().environment(\.locale, Locale(identifier: "zh_CN")).frame(width: 124).padding(5).accessibilityLabel("直接选择年月日")
      HomeIconButton(symbol: "chevron.left", label: "前一天") { change(-1) }.disabled(state.selectedDate <= state.availableDates.lowerBound)
      Button("今天") { withAnimation(.easeOut(duration: 0.2)) { state.selectedDate = state.anchor } }.font(.system(size: 12)).modifier(AppGlassButton()).frame(minWidth: 40, minHeight: 36)
      HomeIconButton(symbol: "chevron.right", label: "后一天") { change(1) }.disabled(state.selectedDate >= state.anchor)
    }
  }
  private func change(_ offset: Int) {
    guard let day = Calendar.current.date(byAdding: .day, value: offset, to: state.selectedDate), state.availableDates.contains(day) else { return }
    withAnimation(.easeOut(duration: 0.2)) { state.selectedDate = day }
  }
}
