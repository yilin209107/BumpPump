import SwiftUI

struct HomeSetDraft: Identifiable {
  var id = UUID().uuidString
  var count = ""
  var weight = ""
  var side = ""
  var warmup = false
  var original: HomeStrengthSet? = nil
  var oppositeCount = ""
  var oppositeWeight = ""
  var oppositeOriginal: HomeStrengthSet? = nil
}
@MainActor final class HomeEntryDraft: ObservableObject {
  @Published var date: Date
  @Published var time = Date()
  @Published var meal = DemoMealKind.breakfast
  @Published var name = ""
  @Published var amount = ""
  @Published var foodID = ""
  @Published var quantity = ""
  @Published var quantityUnit = "g"
  @Published var energyUnit = "kcal"
  @Published var foodBasis = "portion"
  @Published var exerciseID = ""
  @Published var aggregateReps = ""
  @Published var timed = false
  @Published var loadBasis = "per_hand"
  @Published var sets: [HomeSetDraft] = [.init()]
  var originalRevision: Int? = nil
  var originalFood: HomeAddedFood?
  var originalActivity: HomeAddedActivity?
  var originalWeight: HomeAddedWeight?
  @Published var protein = ""
  @Published var carbs = ""
  @Published var fat = ""
  @Published var category = "有氧训练"
  @Published var sport = "跑步"
  @Published var muscles = Set<String>()
  @Published var minutes = ""
  @Published var kcal = ""
  @Published var notes = ""
  @Published var weight = ""
  @Published var unit = "kg"
  @Published var goal = ""
  @Published var changingGoal: Bool
  @Published var error: String?
  @Published var submitted = false
  let id: String
  let isEditing: Bool
  let kind: HomeEntryKind
  init(kind: HomeEntryKind, date: Date, goal: Double?, id: String = UUID().uuidString, editing: Bool = false) {
    self.id = id; self.isEditing = editing
    self.kind = kind; self.date = date; changingGoal = kind == .energy
    self.goal = goal.map { $0.rounded() == $0 ? HomeFormat.number($0) : String($0) } ?? "2000"
  }
  convenience init(record: HomeLocalRecord, goal: Double?) {
    self.init(kind: record.kind, date: record.date, goal: goal, id: record.storageID, editing: true)
    func numeric(_ value: Double) -> String { value.rounded() == value ? HomeFormat.number(value) : String(value) }
    func clock(_ text: String) -> Date {
      let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"; formatter.locale = Locale(identifier: "en_US_POSIX")
      return formatter.date(from: text) ?? Date()
    }
    switch record {
    case .food(let r):
      originalFood = r; foodID = r.foodID ?? "other"; quantity = r.quantity.map(numeric) ?? ""; quantityUnit = r.quantityUnit ?? "g"; kcal = r.nutrition.isKnown("kcal") ? numeric(r.nutrition.energy) : ""
      meal = r.kind; name = r.name; amount = r.amount; time = clock(r.time)
      protein = r.nutrition.isKnown("protein_g") ? numeric(r.nutrition.protein) : ""; carbs = r.nutrition.isKnown("carbs_g") ? numeric(r.nutrition.carbs) : ""; fat = r.nutrition.isKnown("fat_g") ? numeric(r.nutrition.fat) : ""
    case .activity(let r):
      aggregateReps = r.unassignedReps.map(String.init) ?? ""
      originalActivity = r; sets = []
      var consumed = Set<String>()
      for item in r.sets ?? [] where !consumed.contains(item.id) {
        consumed.insert(item.id)
        var draft = HomeSetDraft(id: item.id, count: item.reps.map(String.init) ?? item.seconds.map(numeric) ?? "", weight: item.weight.map(numeric) ?? "", side: item.side ?? "", warmup: item.warmup, original: item)
        if let pair = item.pairID, let opposite = r.sets?.first(where: { $0.pairID == pair && $0.id != item.id }) {
          consumed.insert(opposite.id); draft.oppositeCount = opposite.reps.map(String.init) ?? opposite.seconds.map(numeric) ?? ""; draft.oppositeWeight = opposite.weight.map(numeric) ?? ""; draft.oppositeOriginal = opposite
        }
        sets.append(draft)
      }
      if sets.isEmpty { sets = [.init()] }; timed = r.sets?.contains { $0.seconds != nil } ?? false; loadBasis = r.sets?.first?.basis ?? "unknown"
      category = r.category; sport = HomeDestination.cardioNames.contains(r.title) ? r.title : "其他"; name = r.title; muscles = Set(r.muscles)
      time = clock(r.time); minutes = String(r.minutes); kcal = r.kcal.map(numeric) ?? ""; notes = r.notes
    case .weight(let r): originalWeight = r; weight = numeric(r.jin); unit = "斤"; notes = r.conditions
    }
  }
  var title: String {
    if isEditing { switch kind { case .food, .energy: return "修改饮食记录"; case .activity: return "修改运动记录"; case .weight: return "修改体重记录" } }
    switch kind { case .food: return "记下这一餐"; case .activity: return "留下这次运动"; case .weight: return "记录身体的变化"; case .energy: return changingGoal ? "更改每日热量目标" : "记下这一餐" }
  }
  var icon: String {
    switch kind { case .food: return "fork.knife"; case .activity: return "figure.run"; case .weight: return "scalemass"; case .energy: return changingGoal ? "target" : "fork.knife" }
  }
  var goalValue: Double { guard let value = Double(goal.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else { return 2000 }; return value }
  func adjustGoal(by delta: Int) {
    let value = min(20000, max(50, goalValue + Double(delta)))
    goal = value.rounded() == value ? HomeFormat.number(value) : String(value)
    error = nil
  }
  private func number(_ text: String, title: String) throws -> Double {
    guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else { throw HomeEntryError("请填写有效的" + title + "数值。") }
    return value
  }
  func selectFood(_ food: HomePackagedFood?) {
    guard let food else { return }
    name = food.name; quantityUnit = food.amountUnits.first ?? "g"
  }
  func selectExercise(_ exercise: HomeExercise) {
    exerciseID = exercise.id; name = exercise.name; muscles = [exercise.muscle]; timed = exercise.timed; loadBasis = exercise.basis
  }
  func changeSetCount(_ count: Int) {
    let count = min(50, max(1, count))
    while sets.count < count { sets.append(.init(weight: sets.last?.weight ?? "")) }
    if sets.count > count { sets.removeLast(sets.count-count) }
  }
  func foodRecord(in state: HomeState) throws -> HomeAddedFood {
    let clock = HomeFormat.date(time, pattern: "HH:mm")
    let food = originalFood?.labelSnapshot.flatMap { $0.id == foodID ? $0 : nil } ?? state.packagedFoods.first { $0.id == foodID }
    if let food {
      let value = try number(quantity, title: "份量")
      return .init(id: id, date: date, kind: meal, time: clock, name: food.name, amount: HomeFormat.number(value, digits: value.rounded() == value ? 0 : 1) + " " + quantityUnit,
        nutrition: try food.nutrition(quantity: value, unit: quantityUnit), origin: .init(source: food.source, recordID: food.id, note: "按保存时的标签与实际份量换算"), mealID: originalFood?.mealID, foodID: food.id, quantity: value, quantityUnit: quantityUnit, labelSnapshot: food)
    }
    guard foodID == "other" || (foodID.isEmpty && !name.isEmpty) else { throw HomeEntryError("请选择库内食物，或选择其他并填写。") }
    var factor = 1.0
    if foodBasis != "portion" { factor = try number(quantity, title: "实际食用量") / (foodBasis == "serving" ? 1 : 100) }
    guard factor.isFinite, factor > 0, factor <= 10000 else { throw HomeEntryError("实际食用量必须大于 0。") }
    var missing = Set<String>()
    func optional(_ text: String, _ key: String) throws -> Double {
      if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.insert(key); return 0 }
      let n = try number(text, title: key); guard n >= 0 else { throw HomeEntryError("营养数值不能为负数。") }; return n * factor
    }
    let p = try optional(protein, "protein_g"), c = try optional(carbs, "carbs_g"), f = try optional(fat, "fat_g")
    let energy: Double
    if kcal.isEmpty {
      if missing.isEmpty { energy = p*4 + c*4 + f*9 }
      else if isEditing && originalFood?.nutrition.isKnown("kcal") == false { missing.insert("kcal"); energy = 0 }
      else { throw HomeEntryError("请填写热量；如果填写完整三大营养素，也可自动换算。") }
    } else { let n = try number(kcal, title: "热量"); guard n >= 0 else { throw HomeEntryError("热量不能为负数。") }; energy = n * factor / (energyUnit == "kJ" ? 4.184 : 1) }
    let portion = foodBasis == "portion" ? amount : quantity + " " + (foodBasis == "100g" ? "g" : foodBasis == "100ml" ? "ml" : "份")
    return .init(id: id, date: date, kind: meal, time: clock, name: name.trimmingCharacters(in: .whitespacesAndNewlines), amount: portion.trimmingCharacters(in: .whitespacesAndNewlines),
      nutrition: .init(protein: p, carbs: c, fat: f, recordedEnergy: energy, missing: missing), origin: originalFood?.origin ?? .init(source: "手动填写", recordID: id, note: energyUnit == "kJ" ? "kJ ÷ 4.184 换算为 kcal" : "用户填写"), mealID: originalFood?.mealID)
  }
  func strengthSets() throws -> [HomeStrengthSet] {
    if !aggregateReps.isEmpty && sets.allSatisfy({ $0.count.isEmpty }) {
      let n = try number(aggregateReps, title: "未分组总次数")
      guard n > 0, n <= 100000, n.rounded() == n else { throw HomeEntryError("未分组总次数须为有效正整数。") }
      return []
    }
    return try sets.enumerated().flatMap { index, draft -> [HomeStrengthSet] in
      @MainActor func saved(countText: String, weightText: String, side: String, original: HomeStrengthSet?, id: String) throws -> HomeStrengthSet {
        let count = try number(countText, title: (side == "left" ? "左侧" : side == "right" ? "右侧" : "") + (timed ? "秒数" : "每组次数"))
        guard count > 0, count <= 100000, timed || count.rounded() == count else { throw HomeEntryError("每组次数须为正整数，计时动作请填写有效秒数。") }
        let load = weightText.isEmpty ? nil : try number(weightText, title: "重量")
        guard load.map({ $0 >= 0 && $0 <= 2000 }) ?? true else { throw HomeEntryError("请填写有效重量，未知时可以留空。") }
        var result = original ?? HomeStrengthSet()
        result.id = id; result.reps = timed ? nil : Int(count); result.seconds = timed ? count : nil
        result.weight = load; result.basis = loadBasis; result.side = side.isEmpty ? nil : side; result.warmup = draft.warmup; result.group = index+1
        result.pairID = draft.side == "left" || draft.side == "right" ? (draft.original?.pairID ?? draft.id) : nil
        return result
      }
      let first = try saved(countText: draft.count, weightText: draft.weight, side: draft.side, original: draft.original, id: draft.id)
      guard draft.side == "left" || draft.side == "right" else { return [first] }
      let second = try saved(countText: draft.oppositeCount, weightText: draft.oppositeWeight, side: draft.side == "left" ? "right" : "left", original: draft.oppositeOriginal, id: draft.oppositeOriginal?.id ?? draft.id + "-opposite")
      return [first, second]
    }
  }

  @discardableResult func submit(to state: HomeState, removeGoal: Bool = false) -> Bool {
    guard !submitted else { return false }
    error = nil
    do {
      if isEditing,let originalRevision,let store=state.entryStore,store.isDatabase,try store.read().revision != originalRevision {throw HomeEntryError("编辑期间记录已有更新。请取消并重新打开这条记录，再保存修改。")}
      guard state.availableDates.contains(Calendar.current.startOfDay(for: date)) else { throw HomeEntryError("请选择今天或过去的有效日期。") }
      if kind == .energy && changingGoal {
        try state.setEnergyGoal(removeGoal ? nil : number(goal, title: "目标热量"))
      } else {
        let time = HomeFormat.date(self.time, pattern: "HH:mm")
        switch kind {
        case .food, .energy:
          let result = try foodRecord(in: state)
          try state.addFood(result, editing: isEditing)
        case .activity:
          let duration = minutes.isEmpty && category == "力量训练" ? 0 : try number(minutes, title: "运动时长")
          guard duration.rounded() == duration, duration >= (category == "力量训练" ? 0 : 1), duration <= 1440 else { throw HomeEntryError("有氧请填写 1～1440 分钟，力量训练的时长可以留空。") }
          if category == "力量训练" && muscles.isEmpty { throw HomeEntryError("请选择本次训练涉及的肌群。") }
          let energy = kcal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : try number(kcal, title: "活动消耗")
          let title = category == "力量训练" || sport == "其他" ? name : sport
          let savedSets = category == "力量训练" ? try strengthSets() : nil
          try state.addActivity(.init(id: id, date: date, title: title.trimmingCharacters(in: .whitespacesAndNewlines), category: category, time: time, minutes: Int(duration), kcal: energy, muscles: HomeDestination.strengthNames.filter { muscles.contains($0) }, notes: notes, sets: savedSets, origin: originalActivity?.origin, unassignedReps: savedSets?.isEmpty == true && !aggregateReps.isEmpty ? Int(aggregateReps) : nil), editing: isEditing)
        case .weight:
          let value = try number(weight, title: "体重")
          try state.addWeight(.init(id: id, date: date, jin: unit == "kg" ? value*2 : value, conditions: notes, origin: originalWeight?.origin), editing: isEditing)
        }
      }
      submitted = true
      return true
    } catch { self.error = (error as? HomeEntryError)?.localizedDescription ?? "未能保存到本机，请检查 App 数据目录的访问权限。"; return false }
  }
}
