import SwiftUI

struct HomeCategoryView: View {
  @ObservedObject var state: HomeState
  let palette: SetupPalette
  let reduced: Bool
  @StateObject private var animationLedger = HomePageAnimationLedger()
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 26) {
        HStack {
          VStack(alignment: .leading, spacing: 9) {
            Text(state.destination.group + " / " + state.destination.title).font(.system(size: 12)).foregroundStyle(palette.secondary)
            HStack(spacing: 7) {
              Text(state.destination.title).font(.system(size: 32, weight: .medium)).tracking(-0.7)
              if state.destination == .foods {
                HomeHelpButton(title: "食品库", message: "这里展示本机数据库中已有的预包装食品，不是当天吃过的菜肴。点击食品查看标签营养、品牌、计算基准和来源。记录饮食时可选择这些食品，并填写实际食用量。缺失的营养字段显示 —，不按三大营养素反推标签热量。可以刷新或从已有数据库导入食品库。")
              }
            }
            if state.destination != .foods { Text(HomeFormat.date(state.selectedDate, pattern: "yyyy年M月d日")).font(.system(size: 12)).foregroundStyle(palette.secondary) }
          }
          Spacer()
          if case .cardio = state.destination { HomeAddButton(label: "记录有氧训练", palette: palette) { state.beginContextEntry() } }
          Button("返回概览") { withAnimation(.easeOut(duration: 0.22)) { state.select(.overview) } }.modifier(AppGlassButton())
        }
        if state.destination != .foods { HomeDateNavigation(state: state) }
        switch state.destination {
        case .meal(let kind):
          HomeMacroChart(state: state, palette: palette, reduced: reduced, compact: true, fixedMeal: kind)
            .modifier(HomeEntrance(index: 0, reduced: reduced, token: "category:macro:" + kind.rawValue + "\(state.selectedDate):" + (state.day?.nutrition.animationKey ?? "empty")))
          let meals = (state.day?.meals ?? []).filter { $0.kind == kind }
          ForEach(meals) { meal in
            VStack(alignment: .leading, spacing: 16) {
              HomeSectionHeading(title: meal.title + "明细", subtitle: meal.time) { Text(meal.nutrition.energyText + " kcal").font(.system(size: 14, design: .rounded)) }
              HomeMealExpansion(meal: meal, palette: palette) { state.showMeal(meal, date: state.selectedDate) }
            }.modifier(HomeEntrance(index: 1, reduced: reduced, token: "category:meal:" + meal.id + ":" + meal.nutrition.animationKey))
          }
        case .foods:
          HomeFoodLibraryView(state: state, palette: palette)
        case .strength(let muscle):
          HomeStrengthChart(state: state, muscle: muscle, palette: palette, reduced: reduced)
          Divider().opacity(0.3)
          Text("所选日期的训练").font(.system(size: 19, weight: .medium))
          activityList((state.day?.activities ?? []).filter { $0.muscles.contains(muscle) })
        case .cardio(let sport):
          activityList((state.day?.activities ?? []).filter { $0.category == "有氧训练" && (sport == "其他" ? !HomeDestination.cardioNames.dropLast().contains($0.title) : $0.title == sport) })
        default: EmptyView()
        }

      }.padding(32).frame(maxWidth: 980, alignment: .leading).frame(maxWidth: .infinity)
    }.modifier(HomeScrollViewport())
      .environment(\.homePageAnimationLedger, animationLedger)
      .background(alignment: .bottom) {
      AuroraBackground(dark: palette.dark, reducedMotion: reduced, active: scenePhase == .active).frame(height: 280).opacity(0.32).allowsHitTesting(false)
    }
  }
  @ViewBuilder private func activityList(_ activities: [DemoActivity]) -> some View {
    if activities.isEmpty {
      AppEmptyState("这一天没有相关记录", systemImage: "calendar", description: Text("可以在上方切换日期，或点击加号记录这次运动。"))
        .frame(maxWidth: .infinity).padding(.vertical, 50)
    } else {
      ForEach(activities) { activity in
        VStack(alignment: .leading, spacing: 14) {
          HomeActivityCard(activity: activity, palette: palette) { state.showActivity(activity) }
          ForEach(activity.details, id: \.self) { Text($0).font(.system(size: 14)).foregroundStyle(palette.secondary) }
        }.modifier(HomeEntrance(index: 1, reduced: reduced, token: "category:activity:" + activity.id + ":" + activity.detailLine + ":" + String(activity.kcal ?? -1)))
      }
    }
  }
}
