import SwiftUI
import Charts

struct HomeStrengthChart: View {
  @ObservedObject var state: HomeState
  let muscle: String
  let palette: SetupPalette
  let reduced: Bool
  @State private var selection = ""
  @State private var hovered: String?
  @State private var hoverPoint: CGPoint = .zero
  @State private var table = false
  private var series: [StrengthSeries] { StrengthSeries.make(state.entries.activities.filter { $0.muscles.contains(muscle) && $0.date < Calendar.current.date(byAdding: .day, value: 1, to: state.selectedDate)! }) }
  private var chosen: StrengthSeries? { series.first { $0.id == selection } ?? series.first }
  private var colors: [Color] { DemoMealKind.allCases.map { $0.color(dark: palette.dark) } + [Color(hex: 0xADA5CE), Color(hex: 0xB7AA92), Color(hex: 0x93ADB3), Color(hex: 0xC69EA7)] }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HomeSectionHeading(title: "逐组训练记录", subtitle: "", help: "每根柱子代表一个训练日期，颜色区分组次，柱高为当天总次数或秒数；没有训练的日期不补零。同动作、同负重口径及侧别分别比较，热身组保留在明细中但不计入柱图。将鼠标放在柱子上可查看逐组数据，点击下方记录可核对重量与原始组。") { HStack(spacing: 14) { HomeAddButton(label: "记录力量训练", palette: palette) { state.beginContextEntry() }; HomeChartTableSwitch(table: $table) } }
      if series.isEmpty {
        ContentUnavailableView("还没有可绘图的逐组记录", systemImage: "chart.bar", description: Text("点击右上角加号，选择动作并填写每组次数或秒数。"))
      } else {
        Picker("查看动作与口径", selection: Binding(get: { chosen?.id ?? "" }, set: { selection = $0; hovered = nil })) {
          ForEach(series) { Text($0.title).tag($0.id) }
        }.pickerStyle(.menu).frame(maxWidth: 500, alignment: .leading)
        if let chosen {
          if !table {
            ScrollView(.horizontal) {
              Chart {
                ForEach(chosen.segments) { segment in
                  BarMark(x: .value("日期", segment.day), y: .value(chosen.timed ? "秒数" : "次数", segment.value), width: .ratio(0.52))
                    .foregroundStyle(by: .value("组次", segment.group)).cornerRadius(3)
                    .accessibilityLabel(segment.day + " · " + segment.group).accessibilityValue(HomeFormat.number(segment.value) + (chosen.timed ? " 秒" : " 次"))
                }
                ForEach(chosen.totals.keys.sorted(), id: \.self) { day in
                  PointMark(x: .value("日期", day), y: .value("合计", chosen.totals[day]!)).symbolSize(0).foregroundStyle(.clear).accessibilityHidden(true)
                    .annotation(position: .top) { Text(HomeFormat.number(chosen.totals[day]!)).font(.system(size: 11, design: .rounded)).foregroundStyle(palette.secondary) }
                }
                if let hovered { RuleMark(x: .value("日期", hovered)).foregroundStyle(palette.secondary.opacity(0.3)) }
              }.chartForegroundStyleScale(domain: chosen.groups, range: chosen.groups.enumerated().map { $0.element == "未分组总次数" ? Color.gray : colors[$0.offset % colors.count] })
                .chartYScale(domain: 0...max(1, (chosen.totals.values.max() ?? 1)*1.15))
                .chartXAxis { AxisMarks { _ in AxisTick(); AxisValueLabel() } }
                .chartYAxisLabel(chosen.timed ? "秒" : "次")
                .chartOverlay { proxy in
                  GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                      .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                          guard let frame = proxy.plotFrame else { hovered = nil; return }
                          let plot = geometry[frame]
                          guard plot.contains(point) else { hovered = nil; return }
                          hovered = proxy.value(atX: point.x-plot.minX, as: String.self)
                          hoverPoint = point
                        case .ended: hovered = nil
                        }
                      }
                    if let hovered, let total = chosen.totals[hovered] {
                      VStack(alignment: .leading, spacing: 8) {
                        Text(hovered).font(.system(size: 13, weight: .medium))
                        Text("合计 " + HomeFormat.number(total) + (chosen.timed ? " 秒" : " 次")).font(.system(size: 17, weight: .medium, design: .rounded))
                        Text(chosen.segments.filter { $0.day == hovered }.map { $0.group + " " + HomeFormat.number($0.value) }.joined(separator: " / ")).font(.system(size: 12)).foregroundStyle(palette.secondary)
                      }.padding(14).frame(width: 270, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .position(x: min(max(150, hoverPoint.x), geometry.size.width-150), y: max(64, hoverPoint.y-85)).allowsHitTesting(false)
                    }
                  }
                }
                .frame(width: max(520, CGFloat(chosen.totals.count)*78), height: 250)
                .modifier(HomeChartReveal(token: "strength|" + chosen.id + "|" + chosen.segments.map { $0.id + ":" + $0.day + ":" + $0.group + ":" + String($0.value.bitPattern) }.joined(separator: ";"), reduced: reduced))
            }.modifier(HomeScrollViewport())
          }
          ForEach(chosen.records.sorted { $0.date > $1.date }) { record in
            Button {
              state.detail = .init(title: record.title, date: record.date, rows: (record.sets ?? []).enumerated().map { .init(title: "第\($0.element.group ?? $0.offset+1)组" + ($0.element.side == "left" ? " · 左侧" : $0.element.side == "right" ? " · 右侧" : ""), value: $0.element.summary) } + [HomeDetailRow(title: "来源", value: record.origin.map { $0.source + " · " + $0.note } ?? "本机手动记录"), .init(title: "备注", value: record.notes.isEmpty ? "—" : record.notes)])
            } label: {
              HStack {
                Text(HomeFormat.date(record.date, pattern: "yyyy-MM-dd"))
                Spacer()
                Text((record.sets ?? []).enumerated().map { "\($0.element.group ?? $0.offset+1)组 " + ($0.element.side == "left" ? "左 " : $0.element.side == "right" ? "右 " : "") + ($0.element.reps.map { "\($0)次" } ?? $0.element.seconds.map { HomeFormat.number($0)+"秒" } ?? "—") }.joined(separator: " · ")).lineLimit(2)
                Image(systemName: "chevron.right").font(.system(size: 10))
              }.font(.system(size: 16)).padding(.vertical, 12).contentShape(Rectangle())
            }.modifier(AppGlassButton())
          }
        }
      }
    }
  }
}
