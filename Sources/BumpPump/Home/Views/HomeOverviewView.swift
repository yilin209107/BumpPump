import SwiftUI
import Charts

struct HomeOverviewView: View {
  @ObservedObject var state: HomeState
  let palette: SetupPalette
  let reduced: Bool
  @StateObject private var animationLedger = HomePageAnimationLedger()
  @State private var showingDate = false
  @State private var mealPage = 0
  @State private var editingMeal:DemoMeal?
  var body: some View {
    GeometryReader { geo in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 32) {
          dateHeader.modifier(HomeEntrance(index: 0, reduced: reduced, token: "overview:date:\(state.selectedDate)"))
          if let error = state.entryStorageError { Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(palette.error) }
          if let day = state.day {
            mealSection(day).modifier(HomeEntrance(index: 1, reduced: reduced, token: "overview:meals:\(day.date):" + day.meals.map { $0.id + $0.nutrition.animationKey }.joined(separator: ";")))
            activitySection(day).modifier(HomeEntrance(index: 2, reduced: reduced, token: "overview:activities:\(day.date):" + day.activities.map { $0.id + $0.detailLine + String($0.kcal ?? -1) }.joined(separator: ";")))
          }
          Divider().opacity(0.35)
          HomeWeightChart(state: state, palette: palette, reduced: reduced, compact: geo.size.width < 650)
            .modifier(HomeEntrance(index: 3, reduced: reduced, token: "overview:weight:\(state.selectedDate):\(state.range):" + state.weights.map { "\($0.date):\($0.jin)" }.joined(separator: ";")))
          Divider().opacity(0.35)
          HomeEnergyChart(state: state, palette: palette, reduced: reduced, compact: geo.size.width < 650)
            .modifier(HomeEntrance(index: 4, reduced: reduced, token: "overview:energy:\(state.selectedDate):\(state.range):" + state.energy.map { "\($0.date):\($0.kind.rawValue):\($0.kcal)" }.joined(separator: ";")))
          Divider().opacity(0.35)
          HomeMacroChart(state: state, palette: palette, reduced: reduced, compact: geo.size.width < 650)
            .modifier(HomeEntrance(index: 5, reduced: reduced, token: "overview:macro:\(state.selectedDate):" + (state.day?.nutrition.animationKey ?? "empty")))
        }.frame(width:max(1,min(1120,geo.size.width)-2*(geo.size.width < 600 ? 24:36)),alignment:.leading)
          .padding(.horizontal,geo.size.width < 600 ? 24:36).padding(.top,26).padding(.bottom,40)
          .frame(maxWidth:.infinity)
      }.modifier(HomeScrollViewport())
        .onChange(of: state.selectedDate) { _, _ in state.expandedMealID = nil; mealPage = 0 }
    }.environment(\.homePageAnimationLedger, animationLedger)
      .sheet(item:$editingMeal){meal in HomeRecordsView(state:state,palette:palette,recordIDs:Set(meal.foods.map(\.id)),scopeTitle:meal.title)}
  }
  private var dateHeader: some View {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .center) { dateButton; Spacer(); dayControls }
        VStack(alignment: .leading, spacing: 12) { dateButton; dayControls }
      }
  }
  private var dateButton: some View {
    Button { showingDate.toggle() } label: {
      HStack(spacing: 11) {
        Text(HomeFormat.date(state.selectedDate, pattern: "yyyy年M月d日"))
          .font(.system(size: 30, weight: .medium)).tracking(-0.7)
        Image(systemName: "chevron.down").font(.system(size: 12)).foregroundStyle(palette.secondary)
      }.contentShape(Rectangle()).modifier(HomeGlowShield(soft:true,strength:0.3))
    }.modifier(AppGlassButton()).accessibilityLabel("选择日期，当前为" + HomeFormat.date(state.selectedDate, pattern: "yyyy年M月d日"))
      .popover(isPresented: $showingDate, arrowEdge: .bottom) {
        VStack(alignment: .leading, spacing: 16) {
          Text("查看哪一天？").font(.headline)
          DatePicker("日期", selection: $state.selectedDate, in: state.availableDates, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
            .environment(\.locale, Locale(identifier: "zh_CN"))
          Button("完成") { showingDate = false }.modifier(AppGlassButton()).frame(maxWidth: .infinity, alignment: .trailing)
        }.padding(20).frame(width: 300)
      }
  }
  private var dayControls: some View { HomeDateNavigation(state: state) }
  private func mealSection(_ day: DemoDay) -> some View {
    let displayedMeals = DemoMealKind.allCases.flatMap { kind -> [DemoMeal] in
      let matches = day.meals.filter { $0.kind == kind }
      return matches.isEmpty ? [.init(id: "empty-" + kind.rawValue, kind: kind, title: kind.rawValue, time: "未记录", foods: [])] : matches
    }
    return VStack(alignment: .leading, spacing: 17) {
      HomeSectionHeading(title: Calendar.current.isDateInToday(day.date) ? "今日饮食" : "当日饮食", subtitle: "", help: "餐次卡片显示已记录的热量和三大营养素组成。点击卡片展开食物，点击加号添加记录；未记录的餐次不会按零计算。") {
        HStack(spacing: 14) {
          Text(day.meals.isEmpty ? "暂无记录" : day.nutrition.energyText + " kcal").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(palette.secondary)
          HomeAddButton(label: "新增饮食", palette: palette) { state.entryMeal = nil; state.entry = .food }
        }
      }
      if day.meals.isEmpty { Text("这一天还没有饮食记录。").font(.system(size: 13)).foregroundStyle(palette.secondary).padding(.vertical, 18) }
      ScrollViewReader { proxy in
        VStack(alignment: .leading, spacing: 0) {
          ScrollView(.horizontal) {
            HStack(spacing: 12) {
              ForEach(Array(displayedMeals.enumerated()), id: \.element.id) { index, meal in
                HomeMealCard(meal: meal, palette: palette, expanded: state.expandedMealID == meal.id, edit:{editingMeal=meal}, add: { state.recordMeal(meal.kind) }) {
                  withAnimation(.easeInOut(duration: reduced ? 0.12 : 0.28)) { state.expandedMealID = state.expandedMealID == meal.id ? nil : meal.id }
                }.id(index).modifier(HomeEntrance(index: index, reduced: reduced, token: "meal-card:" + meal.id + ":" + meal.nutrition.animationKey))
              }
            }.padding(.vertical, 3).padding(.horizontal, 1)
          }.modifier(HomeScrollViewport()).scrollIndicators(.hidden)
            .overlay(alignment: .trailing) {
              GeometryReader { geometry in
              if CGFloat(displayedMeals.count) * 164 + CGFloat(max(0, displayedMeals.count-1)) * 12 > geometry.size.width {
                Button {
                  mealPage = mealPage == 0 ? displayedMeals.count - 1 : 0
                  withAnimation(.easeInOut(duration: reduced ? 0.1 : 0.35)) { proxy.scrollTo(mealPage, anchor: mealPage == 0 ? .leading : .trailing) }
                } label: {
                  Image(systemName: mealPage == 0 ? "chevron.right" : "chevron.left").font(.system(size: 12, weight: .semibold)).frame(width: 32, height: 44)

                }.modifier(AppGlassButton()).accessibilityLabel(mealPage == 0 ? "向右翻看餐次" : "回到第一餐").help("点击翻看；也可双指横向滚动")
                  .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
              }
              }
            }
          if let meal = day.meals.first(where: { $0.id == state.expandedMealID }) {
            HomeMealExpansion(meal: meal, palette: palette) { state.showMeal(meal, date: day.date) }
              .padding(.top, 14).transition(.opacity.combined(with: .move(edge: .top)))
          }
        }
      }.id(day.date)
    }
  }
  private func activitySection(_ day: DemoDay) -> some View {
    VStack(alignment: .leading, spacing: 17) {
      HomeSectionHeading(title: Calendar.current.isDateInToday(day.date) ? "今日运动" : "当日运动", subtitle: "", help: "这里显示所选日期的运动记录。消耗仅展示已填写或有来源的数值，不按训练时长或重量自动推算。点击卡片查看原始记录。") {
        HStack(spacing: 14) { Text("\(day.activities.count) 次记录").font(.system(size: 12)).foregroundStyle(palette.secondary); HomeAddButton(label: "新增运动", palette: palette) { state.entry = .activity } }
      }
      if day.activities.isEmpty {
        HStack(spacing: 13) {
          Image(systemName: "figure.cooldown").font(.system(size: 23, weight: .light))
          Text("这一天没有运动记录，休息也是节奏的一部分。").font(.system(size: 13))
        }.foregroundStyle(palette.secondary).padding(.vertical,20).modifier(HomeGlowShield(soft:true,strength:0.3))
      } else {
        ScrollView(.horizontal) {
          HStack(spacing: 12) {
            ForEach(Array(day.activities.enumerated()), id: \.element.id) { index, activity in
              HomeActivityCard(activity: activity, palette: palette) { state.showActivity(activity) }
                .modifier(HomeEntrance(index: index + 1, reduced: reduced, token: "activity-card:" + activity.id + ":" + activity.detailLine + ":" + String(activity.kcal ?? -1)))
            }
          }.padding(.vertical, 3)
        }.modifier(HomeScrollViewport()).scrollIndicators(.hidden)
      }
    }.id(day.date)
  }
}
struct HomeMealCard: View {
  let meal: DemoMeal
  let palette: SetupPalette
  let expanded: Bool
  let edit:()->Void
  let add: () -> Void
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 15) {
        Text(meal.title).font(.system(size: 15, weight: .medium)).padding(.horizontal,28).frame(maxWidth:.infinity,alignment:.center).frame(height:32)
        HomeMealRing(nutrition: meal.nutrition, palette: palette, recorded: !meal.foods.isEmpty, identity: meal.id).frame(width: 118, height: 118).frame(maxWidth: .infinity)
        HStack {
          Text(meal.time).font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.secondary)
          Spacer()
          Image(systemName: "chevron.down").font(.system(size: 11, weight: .medium)).rotationEffect(.degrees(expanded ? 180 : 0))
        }
      }.padding(18).frame(width: 164, alignment: .leading)
    }.modifier(AppGlassButton()).background(palette.surface.opacity(0.58), in: RoundedRectangle(cornerRadius: 15)).modifier(HomeGlowShield(radius:15))
      .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(palette.line.opacity(0.2), lineWidth: 1))
      .accessibilityLabel("\(meal.title)，\(meal.foods.isEmpty ? "未记录" : meal.nutrition.energyText + " 千卡")，\(expanded ? "收起" : "展开")明细")
      .help("点击展开" + meal.title + "明细")
      .overlay(alignment:.topLeading) {
        Button(action:edit){Image(systemName:"pencil").font(.system(size:14,weight:.medium)).frame(width:36,height:36)}
          .modifier(AppGlassButton(prominent:true,tint:.blue,circle:true)).foregroundStyle(.blue)
          .disabled(meal.foods.isEmpty).accessibilityLabel("编辑"+meal.title).help("编辑这餐的食物记录").padding(8)
      }
      .overlay(alignment: .topTrailing) { HomeAddButton(label: "记录" + meal.kind.rawValue, palette: palette, action: add).padding(8) }
  }
}
struct HomeMealRing: View {
  let nutrition: DemoNutrition
  let palette: SetupPalette
  var recorded = true
  var identity = ""
  var body: some View {
    let entries = [HomeMacroEntry(name: "蛋白质", grams: nutrition.protein, factor: 4, color: DemoMealKind.breakfast.color(dark: palette.dark)),
      HomeMacroEntry(name: "碳水", grams: nutrition.carbs, factor: 4, color: DemoMealKind.lunch.color(dark: palette.dark)),
      HomeMacroEntry(name: "脂肪", grams: nutrition.fat, factor: 9, color: DemoMealKind.dinner.color(dark: palette.dark))]
    Chart(entries) { entry in
      SectorMark(angle: .value("热量", entry.kcal), innerRadius: .ratio(0.76), outerRadius: .ratio(0.98), angularInset: 2)
        .foregroundStyle(entry.color).cornerRadius(2)
        .accessibilityLabel(entry.name).accessibilityValue(HomeFormat.number(entry.grams, digits: 1) + " 克")
    }.chartLegend(.hidden).modifier(HomeRingReveal(token: nutrition.animationKey, identity: identity)).background {
      if nutrition.protein + nutrition.carbs + nutrition.fat == 0 { Circle().stroke(palette.line.opacity(0.25), lineWidth: 10).padding(8) }
    }.overlay {
      VStack(spacing: 4) {
        Text(recorded && (nutrition.isKnown("kcal") || nutrition.energy > 0) ? HomeFormat.number(nutrition.energy) : "—").font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
        Text(!recorded ? "未记录" : "kcal").font(.system(size: 9)).foregroundStyle(palette.secondary)
      }
    }
  }
}
struct HomeMealExpansion: View {
  let meal: DemoMeal
  let palette: SetupPalette
  let details: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 13) {
      ForEach(meal.foods) { food in
        HStack {
          Text(food.name).font(.system(size: 13)); Text(food.amount).font(.system(size: 12)).foregroundStyle(palette.secondary)
          Spacer(); Text(food.nutrition.energyText + " kcal").font(.system(size: 12, design: .rounded)).foregroundStyle(palette.secondary)
        }
      }
      Button("查看营养明细", action: details).font(.system(size: 12)).modifier(AppGlassButton()).frame(minHeight: 32)
    }.padding(18).background(palette.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 13)).modifier(HomeGlowShield(radius:13))
  }
}
struct HomeActivityCard: View {
  let activity: DemoActivity
  let palette: SetupPalette
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: 15) {
        Image(systemName: activity.icon).font(.system(size: 23, weight: .light)).foregroundStyle(palette.accent).frame(width: 32, height: 35).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 9) {
          Text(activity.title).font(.system(size: 14, weight: .medium))
          Text(activity.detailLine).font(.system(size: 11)).foregroundStyle(palette.secondary)
          Text(activity.kcal.map { HomeFormat.number($0) + " kcal · " + activity.energySource } ?? "消耗未记录")
            .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(palette.secondary)
        }
        Spacer(minLength: 5)
        Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(palette.secondary)
      }.padding(18).frame(width: 258, alignment: .leading)

        .contentShape(RoundedRectangle(cornerRadius: 15))
    }.modifier(AppGlassButton()).background(palette.surface.opacity(0.56), in: RoundedRectangle(cornerRadius: 15)).modifier(HomeGlowShield(radius:15))
      .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(palette.line.opacity(0.2), lineWidth: 1)).help("查看" + activity.title + "记录")
  }
}
