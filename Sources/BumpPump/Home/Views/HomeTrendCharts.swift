import SwiftUI
import Charts

struct HomeChartReveal: ViewModifier {
  let token: String
  let reduced: Bool
  @State private var progress = 0.0
  func body(content: Content) -> some View {
    content.mask(alignment: .leading) { Rectangle().scaleEffect(x: reduced ? 1 : progress, y: 1, anchor: .leading) }
      .opacity(reduced ? progress : 1)
      .modifier(HomeRevealWhenVisible(progress: $progress, token: "chart|" + token,
        animation: .easeOut(duration: reduced ? 0.15 : 0.75)))
  }
}
struct HomeChartTableSwitch: View {
  @Binding var table: Bool
  var body: some View {
    Button { table.toggle() } label: { Label(table ? "图表" : "数据表", systemImage: table ? "chart.xyaxis.line" : "list.bullet") }
      .modifier(AppGlassButton()).font(.system(size: 11)).foregroundStyle(.secondary).frame(minHeight: 32)
      .accessibilityLabel(table ? "切换为图表" : "切换为数据表")
  }
}
struct HomeWeightChart: View {
  @ObservedObject var state: HomeState
  let palette: SetupPalette
  let reduced: Bool
  let compact: Bool
  @State private var hovered: DemoWeight?
  @State private var table = false
  private var values: [DemoWeight] { state.weights }
  private var domain: ClosedRange<Double> {
    let numbers = values.map(\.jin)
    return ((numbers.min() ?? 120)-0.8)...((numbers.max() ?? 125)+0.8)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 19) {
      ViewThatFits(in: .horizontal) {
        HStack { heading; Spacer(minLength: 20); controls }
        VStack(alignment: .leading, spacing: 12) { heading; controls }
      }
      if values.isEmpty {
        ContentUnavailableView("这段时间没有体重测量", systemImage: "scalemass", description: Text("缺少的测量不会补零，也不会生成趋势。"))
          .frame(height: 200)
      } else if table {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(values) { point in
              Button { state.showWeight(point) } label: {
                HStack { Text(HomeFormat.date(point.date)); Spacer(); Text(HomeFormat.number(point.jin, digits: 1) + " 斤") }
                  .font(.system(size: 13)).padding(.vertical, 12).contentShape(Rectangle())
              }.modifier(AppGlassButton())
              Divider().opacity(0.3)
            }
          }
        }.frame(height: 220)
      } else {
        chart.frame(height: compact ? 205 : 230)
          .modifier(HomeChartReveal(token: "weight|\(state.range)|\(state.selectedDate)|" + values.map { "\($0.date.timeIntervalSinceReferenceDate):\($0.jin.bitPattern)" }.joined(separator: ";"), reduced: reduced))
          .overlay(alignment: .topLeading) {
            if let point = hovered { tooltip(HomeFormat.date(point.date) + " · " + HomeFormat.number(point.jin, digits: 1) + " 斤") }
          }
      }
    }.onChange(of: state.range) { _, _ in hovered = nil }.onChange(of: state.selectedDate) { _, _ in hovered = nil }
  }
  private var heading: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 7) {
        Text("体重变化").font(.system(size: 20, weight: .medium)).tracking(-0.4)
        HomeHelpButton(title: "体重变化", message: "仅连接已记录的测量点，单位为斤。缺少的日期不补零，单个测量点不会制造趋势。同一天有多次测量时显示最新值；原始测量保留在记录中。点击测量点可查看详情。时间范围以所选日期为终点。")
      }
      if let last = values.last {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
          Text(HomeFormat.number(last.jin, digits: 1)).font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
          Text("斤 · " + HomeFormat.date(last.date) + "测量").font(.system(size: 11)).foregroundStyle(palette.secondary)
        }
      }
    }
  }
  private var controls: some View {
    HStack(spacing: 14) {
      Picker("趋势时间范围", selection: $state.range) {
        Text("7天").tag(7); Text("30天").tag(30); Text("90天").tag(90)
      }.pickerStyle(.segmented).labelsHidden().frame(width: 180).help("同时调整体重与摄入热量的时间范围，以所选日期为终点")
      HomeAddButton(label: "新增体重", palette: palette) { state.entry = .weight }
      HomeChartTableSwitch(table: $table)
    }
  }
  private var chart: some View {
    Chart {
      ForEach(values) { point in
        LineMark(x: .value("日期", point.date), y: .value("体重（斤）", point.jin))
          .foregroundStyle(palette.accent).lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round)).interpolationMethod(.linear)
        PointMark(x: .value("日期", point.date), y: .value("体重（斤）", point.jin))
          .foregroundStyle(palette.accent).symbolSize(hovered?.date == point.date ? 48 : 16)
          .accessibilityLabel(HomeFormat.date(point.date)).accessibilityValue(HomeFormat.number(point.jin, digits: 1) + " 斤")
      }
      if let point = hovered {
        RuleMark(x: .value("所选日期", point.date)).foregroundStyle(palette.secondary.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
      }
    }.chartYScale(domain: domain)
      .chartXScale(domain: dateDomain(state.history.map(\.date), fallback: state.selectedDate))
      .chartXAxis { AxisMarks(values: .automatic(desiredCount: compact ? 3 : 5)) { _ in AxisValueLabel(format: .dateTime.month(.twoDigits).day(.twoDigits)).font(.system(size: 10)).foregroundStyle(palette.secondary) } }
      .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in AxisGridLine().foregroundStyle(palette.line.opacity(0.16)); AxisValueLabel().font(.system(size: 10)).foregroundStyle(palette.secondary) } }
      .chartOverlay { proxy in
        GeometryReader { geometry in
          Rectangle().fill(.clear).contentShape(Rectangle())
            .onContinuousHover { phase in
              switch phase { case .active(let position): hovered = point(at: position, proxy: proxy, geometry: geometry); case .ended: hovered = nil }
            }
            .gesture(SpatialTapGesture().onEnded { event in if let point = point(at: event.location, proxy: proxy, geometry: geometry) { state.showWeight(point) } })
        }
      }
      .accessibilityLabel("过去\(state.range)天的体重测量折线图，单位斤，可切换数据表查看")
  }
  private func point(at position: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> DemoWeight? {
    guard let anchor = proxy.plotFrame else { return nil }
    let plot = geometry[anchor]
    guard plot.contains(position), let date = proxy.value(atX: position.x-plot.minX, as: Date.self) else { return nil }
    return values.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
  }
  private func tooltip(_ text: String) -> some View {
    Text(text + " · 点击查看").font(.system(size: 11)).padding(.horizontal, 12).padding(.vertical, 8)
      .background(palette.surface, in: RoundedRectangle(cornerRadius: 8)).padding(.leading, 42).allowsHitTesting(false)
  }
}
struct HomeEnergyChart: View {
  @ObservedObject var state: HomeState
  let palette: SetupPalette
  let reduced: Bool
  let compact: Bool
  @State private var hovered: DemoEnergy?
  @State private var table = false
  var body: some View {
    VStack(alignment: .leading, spacing: 19) {
      HomeSectionHeading(title: "摄入热量", subtitle: "", help: "截至" + HomeFormat.date(state.selectedDate) + "，近\(state.range)天，单位 kcal。按早餐、午餐、晚餐和加餐堆叠显示，加餐合并展示。缺项时仅合计已知热量，不代表全天完整摄入，未知项不补零。黄色线表示当前目标参考，不代表历史目标。点击柱图查看当天记录，点击加号记录饮食或更改目标。") { HStack(spacing: 14) { HomeAddButton(label: "新增饮食或更改热量目标", palette: palette) { state.entryMeal = nil; state.entry = .energy }; HomeChartTableSwitch(table: $table) } }
      if let goal = state.energyGoal { Label("当前目标参考 · " + HomeFormat.number(goal) + " kcal", systemImage: "minus").font(.system(size: 11)).foregroundStyle(palette.dark ? Color(hex: 0xF2CF63) : Color(hex: 0x9B7210)) }
      HStack(spacing: compact ? 13 : 24) {
        ForEach(DemoMealKind.allCases) { kind in
          HStack(spacing: 6) { Circle().fill(kind.color(dark: palette.dark)).frame(width: 6, height: 6); Text(kind.rawValue).font(.system(size: 11)).foregroundStyle(palette.secondary) }
        }
      }
      if !table && state.energy.isEmpty && state.energyGoal == nil {
        ContentUnavailableView(state.history.contains { !$0.meals.isEmpty } ? "饮食已记录，热量待补充" : "这段时间没有饮食记录", systemImage: "fork.knife", description: Text("缺少热量的食物保留在餐次明细中，可以稍后补充。" )).frame(height: 230)
      } else if table {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(state.history) { day in
              Button { state.showEnergy(day.date) } label: {
                HStack { Text(HomeFormat.date(day.date)); Spacer(); Text((day.meals.isEmpty ? "—" : day.nutrition.energyText) + " kcal") }
                  .font(.system(size: 13)).padding(.vertical, 12).contentShape(Rectangle())
              }.modifier(AppGlassButton())
              Divider().opacity(0.3)
            }
          }
        }.frame(height: 230)
      } else {
        chart.frame(height: 230)
          .modifier(HomeChartReveal(token: "energy|\(state.range)|\(state.selectedDate)|\(state.energyGoal ?? 0)|" + state.energy.map { "\($0.date.timeIntervalSinceReferenceDate):\($0.kind.rawValue):\($0.kcal.bitPattern)" }.joined(separator: ";"), reduced: reduced))
          .overlay(alignment: .topLeading) {
            if let point = hovered {
              Text(HomeFormat.date(point.date) + " · " + point.kind.rawValue + " " + HomeFormat.number(point.kcal) + " kcal · 点击查看当天")
                .font(.system(size: 11)).padding(.horizontal, 12).padding(.vertical, 8).background(palette.surface, in: RoundedRectangle(cornerRadius: 8)).padding(.leading, 42).allowsHitTesting(false)
            }
          }
      }
    }.onChange(of: state.range) { _, _ in hovered = nil }.onChange(of: state.selectedDate) { _, _ in hovered = nil }
  }
  private var chart: some View {
    Chart {
      ForEach(state.energy) { point in
      BarMark(x: .value("日期", point.date, unit: .day), y: .value("热量", point.kcal), stacking: .standard)
        .foregroundStyle(by: .value("餐次", point.kind.rawValue))
        .opacity(hovered == nil || hovered?.date == point.date ? 1 : 0.55)
        .accessibilityLabel(HomeFormat.date(point.date) + point.kind.rawValue).accessibilityValue(HomeFormat.number(point.kcal) + " 千卡")
      }
      if let goal = state.energyGoal {
        RuleMark(y: .value("当前目标参考", goal)).foregroundStyle(palette.dark ? Color(hex: 0xF2CF63) : Color(hex: 0x9B7210)).lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
          .accessibilityLabel("当前热量目标参考").accessibilityValue(HomeFormat.number(goal) + " 千卡")
      }
    }.chartForegroundStyleScale(domain: DemoMealKind.allCases.map(\.rawValue), range: DemoMealKind.allCases.map { $0.color(dark: palette.dark) })
      .chartLegend(.hidden).chartXScale(domain: dateDomain(state.history.map(\.date), fallback: state.selectedDate)).chartYScale(domain: 0...max(2500, max(state.energyGoal ?? 0, state.history.map { $0.nutrition.energy }.max() ?? 0) * 1.15))
      .chartXAxis { AxisMarks(values: .automatic(desiredCount: compact ? 3 : 6)) { _ in AxisValueLabel(format: .dateTime.month(.twoDigits).day(.twoDigits)).font(.system(size: 10)).foregroundStyle(palette.secondary) } }
      .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in AxisGridLine().foregroundStyle(palette.line.opacity(0.16)); AxisValueLabel().font(.system(size: 10)).foregroundStyle(palette.secondary) } }
      .chartOverlay { proxy in
        GeometryReader { geometry in
          Rectangle().fill(.clear).contentShape(Rectangle())
            .onContinuousHover { phase in
              switch phase { case .active(let position): hovered = point(at: position, proxy: proxy, geometry: geometry); case .ended: hovered = nil }
            }
            .gesture(SpatialTapGesture().onEnded { event in if let point = point(at: event.location, proxy: proxy, geometry: geometry) { state.showEnergy(point.date) } })
        }
      }.accessibilityLabel("按餐次堆叠的每日摄入热量，近\(state.range)天，可切换数据表查看")
  }
  private func point(at position: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> DemoEnergy? {
    guard let anchor = proxy.plotFrame else { return nil }
    let plot = geometry[anchor]
    guard plot.contains(position), let date = proxy.value(atX: position.x-plot.minX, as: Date.self), let energy = proxy.value(atY: position.y-plot.minY, as: Double.self) else { return nil }
    guard let day = state.history.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) else { return nil }
    let segments = state.energy.filter { $0.date == day.date }
    let total = segments.reduce(0) { $0 + $1.kcal }
    guard energy >= 0, energy <= total else { return nil }
    var sum = 0.0
    for segment in segments { sum += segment.kcal; if energy <= sum { return segment } }
    return segments.last
  }
}
private func dateDomain(_ dates: [Date], fallback: Date) -> ClosedRange<Date> {
  guard let first = dates.min(), let last = dates.max(), first < last else { let centre = dates.first ?? fallback; return centre.addingTimeInterval(-43200)...centre.addingTimeInterval(43200) }
  return first...last
}
