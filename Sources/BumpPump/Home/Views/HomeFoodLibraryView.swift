import SwiftUI
import UniformTypeIdentifiers

struct HomeFoodLibraryView: View {
  @ObservedObject var state: HomeState
  let palette: SetupPalette
  @State private var chooseDatabase = false
  private var foods: [HomePackagedFood] {
    state.packagedFoods.filter { state.catalogQuery.isEmpty || ($0.name + $0.brand + ($0.fields["aliases"] ?? "")).localizedCaseInsensitiveContains(state.catalogQuery) }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack(spacing: 12) {
        TextField("搜索品牌或预包装食品", text: $state.catalogQuery).textFieldStyle(.plain).modifier(FieldSurface(palette: palette)).accessibilityLabel("搜索预包装食品")
        Button { Task { await state.loadPackagedFoods(force: true) } } label: { Image(systemName: "arrow.clockwise").frame(width: 36, height: 36) }
          .modifier(AppGlassButton(circle: true)).disabled(state.catalogLoading).accessibilityLabel("刷新食品库")
        Button("导入食品库") { chooseDatabase = true }.modifier(AppGlassButton()).controlSize(.large)
      }
      if state.catalogLoading { ProgressView("正在读取食品库…").frame(maxWidth: .infinity).padding(35) }
      else if !state.catalogMessage.isEmpty && foods.isEmpty {
        AppEmptyState("食品库暂无条目", systemImage: "shippingbox", description: Text(state.catalogMessage)).frame(maxWidth: .infinity).padding(.vertical, 30)
      } else if foods.isEmpty {
        AppEmptyState(state.catalogQuery.isEmpty ? "食品库里还没有条目" : "没有找到匹配的食品", systemImage: "shippingbox", description: Text("这里展示数据库中的预包装食品，不展示当天的菜肴。" )).frame(maxWidth: .infinity).padding(.vertical, 30)
      } else {
        Text("\(foods.count) 种食品").font(.system(size: 12)).foregroundStyle(palette.secondary)
        ForEach(foods) { food in
          Button { state.selectedPackagedFood = food } label: {
            HStack(alignment: .center, spacing: 18) {
              Image(systemName: "shippingbox").font(.system(size: 23, weight: .light)).frame(width: 34).accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 7) {
                Text(food.name).font(.system(size: 16, weight: .medium))
                Text([food.brand, food.basis, food.source].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(palette.secondary)
              }
              Spacer(minLength: 10)
              Text(food.value("kcal", unit: "kcal")).font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit()
              Image(systemName: "chevron.right").font(.system(size: 11))
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
          }.modifier(AppGlassButton()).appRoundedButtonBorder(radius:16)
        }
      }
    }.fileImporter(isPresented: $chooseDatabase, allowedContentTypes: [.database, .data]) { result in
      if case .success(let url) = result {
        Task {
          let accessed = url.startAccessingSecurityScopedResource()
          defer { if accessed { url.stopAccessingSecurityScopedResource() } }
          await state.loadPackagedFoods(path: url.path, force: true)
        }
      }
    }.sheet(item: $state.selectedPackagedFood) { HomeFoodLabelSheet(food: $0, palette: palette) }
  }
}
private struct HomeFoodLabelSheet: View {
  let food: HomePackagedFood
  let palette: SetupPalette
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduced
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    ZStack {
      palette.background
      VStack { Spacer(); AuroraBackground(dark: palette.dark, reducedMotion: reduced, active: scenePhase == .active).frame(height: 240).opacity(0.65) }.allowsHitTesting(false)
      VStack(spacing: 20) {
        HStack { Text("食品标签 · " + food.source).font(.system(size: 12)).foregroundStyle(palette.secondary); Spacer(); HomeIconButton(symbol: "xmark", label: "关闭食品标签") { dismiss() }.keyboardShortcut(.cancelAction) }
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "shippingbox").font(.system(size: 30, weight: .light)).frame(maxWidth: .infinity)
            Text(food.name).font(.system(size: 27, weight: .medium)).frame(maxWidth: .infinity).multilineTextAlignment(.center)
            Text([food.brand, food.basis].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 13)).foregroundStyle(palette.secondary).frame(maxWidth: .infinity)
            ForEach([("热量", "kcal", "kcal"), ("蛋白质", "protein_g", "g"), ("碳水", "carbs_g", "g"), ("脂肪", "fat_g", "g"), ("膳食纤维", "fiber_g", "g"), ("糖", "sugar_g", "g"), ("钠", "sodium_mg", "mg")], id: \.0) { title, key, unit in
              HStack { Text(title).foregroundStyle(palette.secondary); Spacer(); Text(food.value(key, unit: unit)).monospacedDigit() }.font(.system(size: 15))
              Divider().opacity(0.25)
            }
            DisclosureGroup("原始字段与扩展营养") {
              VStack(spacing: 15) {
                ForEach(food.fields.keys.sorted(), id: \.self) { key in
                  HStack(alignment: .top) { Text(key).font(.system(size: 11, design: .monospaced)).frame(width: 140, alignment: .leading); Text(food.fields[key] ?? "—").font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                }
              }.padding(.top, 16)
            }.font(.system(size: 13))
          }.padding(.horizontal, 12).padding(.vertical, 8)
        }
      }.padding(28)
    }.environment(\.usesGlassControls, true).frame(width: 620, height: 590).foregroundStyle(palette.foreground)
  }
}
