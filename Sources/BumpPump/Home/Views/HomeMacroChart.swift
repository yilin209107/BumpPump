import SwiftUI
import Charts

struct HomeMacroEntry: Identifiable {
  let name: String
  let grams: Double
  let factor: Double
  let color: Color
  var kcal: Double { grams * factor }
  var id: String { name }
}
struct HomeMacroChart: View {
  @ObservedObject var state: HomeState
  let palette: SetupPalette
  let reduced: Bool
  let compact: Bool
  var fixedMeal: DemoMealKind? = nil
  private var selectedMeal: String { fixedMeal?.rawValue ?? meal }
  @State private var meal = "全天"
  @State private var hovered: String?
  @State private var table = false
  private var nutrition: DemoNutrition {
    let selected = state.day?.meals.filter { selectedMeal == "全天" || $0.kind.rawValue == selectedMeal } ?? []
    return selected.reduce(.init()) { $0 + $1.nutrition }
  }
  private var entries: [HomeMacroEntry] {
    [.init(name: "蛋白质", grams: nutrition.protein, factor: 4, color: DemoMealKind.breakfast.color(dark: palette.dark)),
     .init(name: "碳水", grams: nutrition.carbs, factor: 4, color: DemoMealKind.lunch.color(dark: palette.dark)),
     .init(name: "脂肪", grams: nutrition.fat, factor: 9, color: DemoMealKind.dinner.color(dark: palette.dark))]
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      HomeSectionHeading(title: fixedMeal == nil ? "摄入热量组成" : fixedMeal!.rawValue + "营养组成", subtitle: "", help: "所选日期：" + HomeFormat.date(state.selectedDate) + "。环图展示三大营养素的供能比例：蛋白质与碳水按每克 4 kcal，脂肪按每克 9 kcal 计算，因此环图供能合计可能与标签热量有差异。缺失营养素不补零。将鼠标放在扇区上可查看对应热量，右侧列出克数；可切换数据表核对。") {
        if fixedMeal == nil { Picker("营养组成的餐次", selection: $meal) { Text("全天").tag("全天"); ForEach(DemoMealKind.allCases) { Text($0.rawValue).tag($0.rawValue) } }
          .labelsHidden().frame(width: 92) }
        HomeAddButton(label: fixedMeal.map { "记录" + $0.rawValue } ?? "新增饮食", palette: palette) {
          if let fixedMeal { state.recordMeal(fixedMeal) } else { state.entryMeal = nil; state.entry = .food }
        }
        HomeChartTableSwitch(table: $table)
      }
      if entries.reduce(0, { $0 + $1.kcal }) <= 0 {
        let hasMeals = state.day?.meals.contains { selectedMeal == "全天" || $0.kind.rawValue == selectedMeal } == true
        ContentUnavailableView(hasMeals ? "已记录，暂无完整营养组成" : "这一天没有该餐次的记录", systemImage: "fork.knife", description: Text(hasMeals ? "热量与已知内容保留在明细；没有数据的营养素不会补零。" : "可以点击加号，记录这一餐。" )).frame(height: 200)
      } else {
        HStack(spacing: compact ? 24 : 54) {
          if !table {
            Chart(entries) { entry in
              SectorMark(angle: .value("热量", entry.kcal), innerRadius: .ratio(0.72), outerRadius: .ratio(0.96), angularInset: 2.5)
                .cornerRadius(3).foregroundStyle(entry.color).opacity(hovered == nil || hovered == entry.name ? 1 : 0.35)
                .accessibilityLabel(entry.name).accessibilityValue("\(HomeFormat.number(entry.grams, digits: 1)) 克，\(HomeFormat.number(entry.kcal)) 千卡")
            }.chartLegend(.hidden)
              .chartOverlay { proxy in
                GeometryReader { geometry in
                  Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                      switch phase { case .active(let point): hovered = segment(at: point, size: geometry.size); case .ended: hovered = nil }
                    }
                    .gesture(SpatialTapGesture().onEnded { event in hovered = segment(at: event.location, size: geometry.size) })
                }
              }
              .overlay {
                let selected = entries.first { $0.name == hovered }
                VStack(spacing: 6) {
                  Text(selected.map { HomeFormat.number($0.kcal) } ?? (nutrition.energy > 0 || nutrition.isKnown("kcal") ? HomeFormat.number(nutrition.energy) : "—")).font(.system(size: compact ? 27 : 32, weight: .medium, design: .rounded)).monospacedDigit()
                  Text(selected.map { $0.name + " · kcal" } ?? ("kcal")).font(.system(size: 10)).foregroundStyle(palette.secondary)
                }.allowsHitTesting(false)
              }.frame(width: compact ? 178 : 224, height: compact ? 178 : 224)
              .modifier(HomeRingReveal(token: "\(state.selectedDate)-\(selectedMeal)-\(nutrition.animationKey)", identity: "macro:" + (fixedMeal?.rawValue ?? "all")))
          }
          VStack(spacing: 20) {
            ForEach(entries) { entry in
              Button { hovered = hovered == entry.name ? nil : entry.name } label: {
                HStack(spacing: 10) {
                  Circle().fill(entry.color).frame(width: 7, height: 7)
                  VStack(alignment: .leading, spacing: 5) {
                    Text(entry.name).font(.system(size: 13))
                    Text("\(HomeFormat.number(entry.kcal / max(1, entries.reduce(0) { $0 + $1.kcal }) * 100))% · \(HomeFormat.number(entry.kcal)) kcal").font(.system(size: 10)).foregroundStyle(palette.secondary)
                  }
                  Spacer(minLength: 10)
                  Text(nutrition.text(entry.name == "蛋白质" ? "protein_g" : entry.name == "碳水" ? "carbs_g" : "fat_g", value: entry.grams) + " g").font(.system(size: compact ? 16 : 20, weight: .medium, design: .rounded)).monospacedDigit()
                }.frame(minHeight: 36).contentShape(Rectangle())
              }.modifier(AppGlassButton()).help(entry.name + "的克数与热量占比")
            }
          }.frame(maxWidth: 370)
          if !compact { Spacer(minLength: 0) }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
    }.onChange(of: meal) { _, _ in hovered = nil }.onChange(of: state.selectedDate) { _, _ in hovered = nil }
  }
  private func segment(at point: CGPoint, size: CGSize) -> String? {
    let dx = point.x-size.width/2, dy = point.y-size.height/2
    let radius = min(size.width, size.height)/2
    let distance = hypot(dx, dy)
    guard distance >= radius * 0.72, distance <= radius * 0.96 else { return nil }
    var angle = atan2(dy, dx) + .pi/2
    if angle < 0 { angle += .pi*2 }
    let selectedEnergy = angle / (.pi*2) * entries.reduce(0) { $0 + $1.kcal }
    var sum = 0.0
    for entry in entries { sum += entry.kcal; if selectedEnergy <= sum { return entry.name } }
    return entries.last?.name
  }
}
