import SwiftUI

struct HomeEntryView: View {
  @ObservedObject var state: HomeState
  let kind: HomeEntryKind
  let palette: SetupPalette
  var preview = false
  @StateObject private var draft: HomeEntryDraft
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduced
  @Environment(\.scenePhase) private var scenePhase
  @State private var arrived = false
  @FocusState private var cancelFocused: Bool
  init(state: HomeState, kind: HomeEntryKind, palette: SetupPalette, preview: Bool = false, draft: HomeEntryDraft? = nil) {
    self.state = state; self.kind = kind; self.palette = palette; self.preview = preview
    let initial = draft ?? HomeEntryDraft(kind: kind, date: state.selectedDate, goal: state.energyGoal)
    if draft == nil, kind == .food, let meal = state.entryMeal { initial.meal = meal }
    if draft == nil, kind == .activity {
      switch state.destination {
      case .strength(let muscle): initial.category = "力量训练"; initial.muscles = [muscle]
      case .cardio(let sport): initial.category = "有氧训练"; initial.sport = sport
      default: break
      }
    }
    if draft == nil, kind == .activity, initial.category == "力量训练" {
      let recentNames = state.entries.activities.filter { !$0.muscles.allSatisfy { !initial.muscles.contains($0) } }.sorted { $0.date > $1.date }.map(\.title)
      let recent = recentNames.compactMap { name in state.exercises.first { $0.name == name } }.first
      if let exercise = recent ?? state.exercises.first(where: { initial.muscles.contains($0.muscle) }) { initial.selectExercise(exercise) }
    }
    if draft != nil, initial.category == "力量训练" { initial.exerciseID = state.exercises.first(where: { $0.name == initial.name })?.id ?? "other" }
    if initial.isEditing,initial.originalRevision==nil{initial.originalRevision=state.entries.revision}
    _draft = StateObject(wrappedValue: initial)
  }
  var body: some View {
    ZStack {
      palette.background
      VStack { Spacer(minLength: 0); AuroraBackground(dark: palette.dark, reducedMotion: reduced, active: scenePhase == .active || preview, fixedTime: preview ? 8 : nil).frame(height: 260).opacity(0.7) }.allowsHitTesting(false)
      if draft.submitted {
        VStack(spacing: 20) {
          Image(systemName: "checkmark.circle").font(.system(size: 58, weight: .ultraLight))
          Text(draft.isEditing ? "修改已保存。" : "已保存。").font(.system(size: 30, weight: .medium))
          Text(kind == .energy && draft.changingGoal ? "目标参考已更新到图表。" : "主页与图表已同步更新。").font(.system(size: 13)).foregroundStyle(palette.secondary)
        }.transition(.opacity).task { if !preview { try? await Task.sleep(for: .milliseconds(reduced ? 450 : 800)); dismiss() } }
      } else {
        VStack(spacing: 0) {
          HStack {
            Color.clear.frame(width: 44, height: 44)
            Spacer()
            if kind == .energy {
              Picker("摄入热量操作", selection: $draft.changingGoal) { Text("记录饮食").tag(false); Text("更改目标").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 250)
            }
            Spacer()
            HomeIconButton(symbol: "xmark", label: draft.isEditing ? "取消修改记录" : "取消新增记录") { dismiss() }.keyboardShortcut(.cancelAction).focusable().focused($cancelFocused)
          }.padding(.bottom, 14)
          ScrollViewReader { scroll in
          ScrollView {
            VStack(spacing: 0) {
              Image(systemName: draft.icon).font(.system(size: 29, weight: .light)).frame(height: 37).padding(.top, 8).padding(.bottom, 13).accessibilityHidden(true)
              HStack(spacing: 8) {
                Text(draft.title).font(.system(size: 29, weight: .medium)).tracking(-0.8).multilineTextAlignment(.center)
                HomeHelpButton(title: draft.title, message: subtitle + "\n记录仅保存在本机；保存后会同步更新主页和图表。")
              }.padding(.bottom, 23)
              fields
              if let error = draft.error {
                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(palette.error).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 16).id("entry-error").accessibilityAddTraits(.updatesFrequently)
              }
            }.frame(maxWidth: 600).padding(.horizontal, 5).padding(.bottom, 14).frame(maxWidth: .infinity)
          }.scrollIndicators(.visible)
            .onChange(of: draft.error) { _, error in
              if error != nil { withAnimation(.easeOut(duration: 0.2)) { scroll.scrollTo("entry-error", anchor: .bottom) } }
            }
          }
          HStack {
            if kind == .energy && draft.changingGoal && state.energyGoal != nil {
              Button("移除目标线") { save(removeGoal: true) }.modifier(AppGlassButton(tint: .red)).font(.system(size: 12)).frame(minHeight: 44)
            }
            Spacer()
            Text("保存").font(.system(size: 14)).padding(.trailing, 9)
            ForwardArrow(palette: palette, label: "保存" + draft.title) { save() }
          }.frame(maxWidth: 600).padding(.top, 15).padding(.bottom, 5)
        }.padding(.horizontal, 30).padding(.top, 14).padding(.bottom, 22)
          .opacity(arrived ? 1 : 0).offset(y: arrived || reduced ? 0 : 8).transition(.opacity)
      }
    }.environment(\.usesGlassControls, true).frame(width: 740, height: 720).foregroundStyle(palette.foreground).tint(palette.accent)
      .defaultFocus($cancelFocused, true)
      .onAppear { cancelFocused = true; withAnimation(.easeOut(duration: reduced ? 0.1 : 0.35)) { arrived = true } }
      .animation(.easeOut(duration: reduced ? 0.12 : 0.25), value: draft.submitted)
      .preferredColorScheme(preview ? (palette.dark ? .dark : .light) : nil)
  }
  private var subtitle: String {
    if kind == .energy && draft.changingGoal { return "为自己设定一个热量参考。每次加减调整 50 kcal，也可以直接输入数值。保存后，图表会显示黄色目标参考线。\n这是当前目标，不代表历史目标；已有目标也可以移除。" }
    switch kind { case .food, .energy: return "选择已有食物和份量，或手动记录其他食物。"; case .activity: return "选择动作，逐组记录次数或秒数；有氧可填写时长。"; case .weight: return "可以使用 kg 或斤记录体重。主页以斤展示，kg 会自动换算。同一天有多次输入时展示最新值，原始输入全部保留。" }
  }
  @ViewBuilder private var fields: some View {
    VStack(alignment: .leading, spacing: 17) {
      if kind == .energy && draft.changingGoal {
        goalControl
      } else {
        HStack(spacing: 18) {
          HomeLabeledField(title: "日期", palette: palette) { DatePicker("记录日期", selection: $draft.date, in: state.availableDates, displayedComponents: .date).datePickerStyle(.field).labelsHidden().modifier(FieldSurface(palette: palette)).environment(\.locale, Locale(identifier: "zh_CN")).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 36) }
          if kind != .weight { HomeLabeledField(title: "时间", palette: palette) { DatePicker("记录时间", selection: $draft.time, displayedComponents: .hourAndMinute).labelsHidden().modifier(FieldSurface(palette: palette)).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 36) } }
        }
        switch kind {
        case .food, .energy: foodFields
        case .activity: activityFields
        case .weight: weightFields
        }
      }
    }
  }
  private var goalControl: some View {
    AppGlassGroup(spacing: 20) {
      HStack(spacing: 20) {
        Button { draft.adjustGoal(by: -50) } label: { Image(systemName: "minus").font(.system(size: 19, weight: .medium)).frame(width: 40, height: 40) }
          .modifier(AppGlassButton(prominent: true, tint: .red, circle: true)).disabled(draft.goalValue <= 50).accessibilityLabel("目标减少 50 千卡")
        VStack(spacing: 12) {
          TextField("2000", text: $draft.goal).textFieldStyle(.plain).multilineTextAlignment(.center).font(.system(size: 58, weight: .medium, design: .rounded)).monospacedDigit()
            .frame(width: 230, height: 100).modifier(AppGlassSurface(radius: 24)).accessibilityLabel("每日热量目标，千卡").onSubmit { save() }
          Text("kcal / 天").font(.system(size: 13)).foregroundStyle(palette.secondary)
        }
        Button { draft.adjustGoal(by: 50) } label: { Image(systemName: "plus").font(.system(size: 19, weight: .medium)).frame(width: 40, height: 40) }
          .modifier(AppGlassButton(prominent: true, tint: .blue, circle: true)).disabled(draft.goalValue >= 20000).accessibilityLabel("目标增加 50 千卡")
      }.frame(maxWidth: .infinity).padding(.vertical, 20)
    }
  }
  private var foodFields: some View {
    VStack(alignment: .leading, spacing: 17) {
      HomeLabeledField(title: "餐次", palette: palette) { Picker("餐次", selection: $draft.meal) { ForEach(DemoMealKind.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().pickerStyle(.menu).modifier(FieldSurface(palette: palette)) }
      HomeLabeledField(title: "食物名称", palette: palette, help: "选择本机食品库中已有的预包装食品后，填写实际食用重量、体积或份数，应用会按标签计算本次热量。其他食物可选择手动填写。按当前标签计算并保留标签快照；缺项保留未知，g 与 ml 不假定互相换算。") {
        Picker("选择食物", selection: $draft.foodID) {
          Text("请选择食物").tag("")
          ForEach(state.packagedFoods) { food in Text((food.brand.isEmpty ? "" : food.brand + " · ") + food.name).tag(food.id) }
          if let saved = draft.originalFood?.labelSnapshot, !state.packagedFoods.contains(where: { $0.id == saved.id }) { Text(saved.name + "（历史标签）").tag(saved.id) }
          Divider(); Text("其他 · 手动填写").tag("other")
        }.labelsHidden().modifier(FieldSurface(palette: palette))
          .onChange(of: draft.foodID) { _, id in draft.selectFood(state.packagedFoods.first { $0.id == id }) }
      }
      if let food = state.packagedFoods.first(where: { $0.id == draft.foodID }) ?? draft.originalFood?.labelSnapshot.flatMap({ $0.id == draft.foodID ? $0 : nil }) {
        HStack(alignment: .bottom, spacing: 14) {
          numberField("实际食用量", placeholder: "输入份量", value: $draft.quantity)
          if food.amountUnits.count == 1 {
            Text(food.amountUnits[0]).font(.system(size: 18, weight: .medium)).frame(width: 62, height: 48).modifier(AppGlassSurface()).accessibilityLabel("份量单位 " + food.amountUnits[0])
          } else {
            Picker("份量单位", selection: $draft.quantityUnit) { ForEach(food.amountUnits, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 100).modifier(FieldSurface(palette: palette))
          }
        }
        Text(food.basis + " · " + food.source).font(.system(size: 12)).foregroundStyle(palette.secondary)
        if let value = Double(draft.quantity), let nutrition = try? food.nutrition(quantity: value, unit: draft.quantityUnit) {
          Text("本次热量  " + nutrition.energyText + " kcal").font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit().padding(.vertical, 7)
          Text("蛋白质 " + nutrition.text("protein_g", value: nutrition.protein) + " g · 碳水 " + nutrition.text("carbs_g", value: nutrition.carbs) + " g · 脂肪 " + nutrition.text("fat_g", value: nutrition.fat) + " g").font(.system(size: 12)).foregroundStyle(palette.secondary)
        }
      } else if draft.foodID == "other" {
        textField("食物名称", placeholder: "吃了什么？", value: $draft.name)
        HomeLabeledField(title: "营养数值基准", palette: palette, help: "选择数值对应本次总量、每 100 g、每 100 ml 或每份，再填写实际食用量。kJ ÷ 4.184 会换算为 kcal。未知营养素留空；三大营养素齐全时，可按蛋白质 4、碳水 4、脂肪 9 kcal/g 自动计算热量。") {
          Picker("营养数值基准", selection: $draft.foodBasis) { Text("本次总量").tag("portion"); Text("每 100 g").tag("100g"); Text("每 100 ml").tag("100ml"); Text("每份").tag("serving") }.labelsHidden().modifier(FieldSurface(palette: palette))
        }
        if draft.foodBasis == "portion" { textField("本次份量", placeholder: "例如：1 碗、150 g", value: $draft.amount) }
        else { numberField(draft.foodBasis == "100g" ? "实际食用克数 · g" : draft.foodBasis == "100ml" ? "实际饮用体积 · ml" : "实际食用份数", placeholder: "输入食用量", value: $draft.quantity) }
        HStack(alignment: .bottom, spacing: 14) {
          numberField("热量", placeholder: "输入标签或已知热量", value: $draft.kcal)
          Picker("热量单位", selection: $draft.energyUnit) { Text("kcal").tag("kcal"); Text("kJ").tag("kJ") }.pickerStyle(.segmented).frame(width: 125).padding(.bottom, 12)
        }
        HStack(spacing: 12) {
          numberField("蛋白质 · g（可选）", placeholder: "未知留空", value: $draft.protein)
          numberField("碳水 · g（可选）", placeholder: "未知留空", value: $draft.carbs)
          numberField("脂肪 · g（可选）", placeholder: "未知留空", value: $draft.fat)
        }
        if let record = try? draft.foodRecord(in: state) { Text("本次摄入  " + record.nutrition.energyText + " kcal").font(.system(size: 20, weight: .medium, design: .rounded)) }
      }

    }
  }
  private var activityFields: some View {
    VStack(alignment: .leading, spacing: 17) {
      Picker("运动类别", selection: $draft.category) { Text("有氧训练").tag("有氧训练"); Text("力量训练").tag("力量训练") }.pickerStyle(.segmented).labelsHidden()
      if draft.category == "有氧训练" {
        HomeLabeledField(title: "运动类型", palette: palette) { Picker("运动类型", selection: $draft.sport) { ForEach(HomeDestination.cardioNames, id: \.self) { Text($0).tag($0) } }.labelsHidden().modifier(FieldSurface(palette: palette)) }
      }
      if draft.category == "力量训练" {
        HomeLabeledField(title: "健身动作", palette: palette) {
          Picker("健身动作", selection: $draft.exerciseID) {
            Text("选择动作").tag("")
            ForEach(state.exercises) { exercise in Text(exercise.name + " · " + exercise.muscle).tag(exercise.id) }
            Text("其他动作").tag("other")
          }.labelsHidden().modifier(FieldSurface(palette: palette))
            .onChange(of: draft.exerciseID) { _, id in if let exercise = state.exercises.first(where: { $0.id == id }) { draft.selectExercise(exercise) } }
        }
        if draft.exerciseID == "other" || draft.exerciseID.isEmpty { textField("动作名称", placeholder: "输入动作名称", value: $draft.name) }
        strengthFields
      } else if draft.sport == "其他" { textField("运动名称", placeholder: "这次做了什么运动？", value: $draft.name) }
      if draft.category == "力量训练" {
        HomeLabeledField(title: "涉及肌群", palette: palette) {
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
            ForEach(HomeDestination.strengthNames, id: \.self) { name in
              Toggle(name, isOn: Binding(get: { draft.muscles.contains(name) }, set: { if $0 { draft.muscles.insert(name) } else { draft.muscles.remove(name) } })).toggleStyle(.checkbox).font(.system(size: 16))
            }
          }
        }
      }
      HStack(spacing: 12) { numberField(draft.category == "力量训练" ? "时长 · 分钟（可选）" : "时长 · 分钟", placeholder: "填写分钟数", value: $draft.minutes); numberField("活动消耗 · kcal（可选）", placeholder: "无设备数据可留空", value: $draft.kcal, help: "填写设备数据或已有依据的活动消耗；没有数据可以留空。应用不会根据训练时长或重量自动推算消耗。") }
      textField("备注（可选）", placeholder: "训练细节或感受", value: $draft.notes)
    }
  }
  private var strengthFields: some View {
    VStack(alignment: .leading, spacing: 16) {
      if draft.originalActivity?.unassignedReps != nil {
        numberField("未分组总次数", placeholder: "保留原始总数", value: $draft.aggregateReps, help: "原记录没有分组。可以只保留总数；补齐每组次数后将以分组记录替代总数，避免重复计入。")
      }
      Picker("记录方式", selection: $draft.timed) { Text("次数").tag(false); Text("计时 · 秒").tag(true) }.pickerStyle(.segmented)
      HomeLabeledField(title: "重量口径", palette: palette, help: "请区分双手总重量、单只重量、自重、器材标称阻力等口径。每组独立保存，热身组保留在明细中但不计入正式次数图；器材标称阻力不与哑铃重量比较。选择左侧或右侧时，同一组会出现另一侧输入框，分别保存。") {
        Picker("重量口径", selection: $draft.loadBasis) { ForEach(HomeExercise.bases, id: \.self) { Text(HomeExercise.basisTitle($0)).tag($0) } }.labelsHidden().modifier(FieldSurface(palette: palette))
      }
      HStack(spacing: 14) {
        Text("共")
        HomeQuantityControl(value: Binding(get: { String(draft.sets.count) }, set: { if let n = Int($0), (1...50).contains(n) { draft.changeSetCount(n) } }), title: "组数", step: 1, minimum: 1, maximum: 50)
        Text("组")
      }.font(.system(size: 22, weight: .medium)).padding(.vertical, 8)
      ForEach(Array(draft.sets.indices), id: \.self) { index in
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Text("第 \(index+1) 组").font(.system(size: 22, weight: .medium))
            Spacer()
            Toggle("热身组", isOn: $draft.sets[index].warmup).toggleStyle(.checkbox).font(.system(size: 16))
            Picker("第\(index+1)组侧别", selection: $draft.sets[index].side) { Text("侧别未注明").tag(""); Text("左侧").tag("left"); Text("右侧").tag("right"); Text("双侧").tag("both") }.labelsHidden().font(.system(size: 16)).frame(width: 140)
          }
          setInputs(index: index, opposite: false)
          if draft.sets[index].side == "left" || draft.sets[index].side == "right" { setInputs(index: index, opposite: true) }
        }.padding(.vertical, 12)
        if index < draft.sets.count-1 { Divider().opacity(0.35) }
      }
    }
  }
  private func setInputs(index: Int, opposite: Bool) -> some View {
    let side = draft.sets[index].side
    let label = side == "left" ? (opposite ? "右侧" : "左侧") : side == "right" ? (opposite ? "左侧" : "右侧") : ""
    return VStack(alignment: .leading, spacing: 12) {
      if !label.isEmpty { Text(label).font(.system(size: 17, weight: .medium)).foregroundStyle(palette.secondary) }
      HStack(spacing: 14) {
        Text(draft.timed ? "时长" : "次数").frame(width: 48, alignment: .leading)
        HomeQuantityControl(value: opposite ? $draft.sets[index].oppositeCount : $draft.sets[index].count, title: "第\(index+1)组" + label + (draft.timed ? "秒数" : "次数"), step: 1, minimum: 1, maximum: 100000)
        Text(draft.timed ? "秒" : "次")
      }
      HStack(spacing: 14) {
        Text("共").frame(width: 48, alignment: .leading)
        HomeQuantityControl(value: opposite ? $draft.sets[index].oppositeWeight : $draft.sets[index].weight, title: "第\(index+1)组" + label + "重量", step: 0.5, minimum: 0, maximum: 2000)
        Text("kg")
      }
    }.font(.system(size: 19))
  }
  private var weightFields: some View {
    VStack(alignment: .leading, spacing: 17) {
      HStack(alignment: .bottom, spacing: 18) {
        numberField("体重", placeholder: "填写测量值", value: $draft.weight)
        Picker("体重单位", selection: $draft.unit) { Text("kg").tag("kg"); Text("斤").tag("斤") }.pickerStyle(.segmented).labelsHidden().frame(width: 120).padding(.bottom, 9)
      }
      textField("测量条件（可选）", placeholder: "例如：晨起、空腹", value: $draft.notes)
    }
  }
  private func textField(_ title: String, placeholder: String, value: Binding<String>, help: String = "") -> some View {
    HomeLabeledField(title: title, palette: palette, help: help) { TextField(placeholder, text: value).textFieldStyle(.plain).modifier(FieldSurface(palette: palette)).accessibilityLabel(title) }
  }
  private func numberField(_ title: String, placeholder: String, value: Binding<String>, help: String = "") -> some View { textField(title, placeholder: placeholder, value: value, help: help) }
  private func save(removeGoal: Bool = false) { draft.submit(to: state, removeGoal: removeGoal) }
}
