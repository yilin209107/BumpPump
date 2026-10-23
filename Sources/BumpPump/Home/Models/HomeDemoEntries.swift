import Foundation

enum HomeEntryKind: String, Identifiable { case food, activity, weight, energy; var id: String { rawValue } }
struct HomeAddedFood: Codable, Identifiable {
  var id = UUID().uuidString
  let date: Date
  let kind: DemoMealKind
  let time: String
  let name: String
  let amount: String
  let nutrition: DemoNutrition
  var origin: HomeRecordOrigin? = nil
  var mealID: String? = nil
  var foodID: String? = nil
  var quantity: Double? = nil
  var quantityUnit: String? = nil
  var labelSnapshot: HomePackagedFood? = nil
}
struct HomeAddedActivity: Codable, Identifiable {
  var id = UUID().uuidString
  let date: Date
  let title: String
  let category: String
  let time: String
  let minutes: Int
  let kcal: Double?
  let muscles: [String]
  let notes: String
  var sets: [HomeStrengthSet]? = nil
  var origin: HomeRecordOrigin? = nil
  var unassignedReps: Int? = nil
}
struct HomeAddedWeight: Codable, Identifiable {
  var id = UUID().uuidString
  let date: Date
  let jin: Double
  let conditions: String
  var order: Double? = nil
  var origin: HomeRecordOrigin? = nil
}
struct HomeDemoEntries: Codable {
  var version = 3
  var revision: Int? = nil
  var documents: [String: [[String: String]]]? = nil
  var removedLibrary: [String: [Data]]? = nil
  var foods: [HomeAddedFood] = []
  var activities: [HomeAddedActivity] = []
  var weights: [HomeAddedWeight] = []
  var energyGoal: Double?
  var trash: [HomeLocalRecord]? = nil
  var foodLibrary: [HomePackagedFood]? = nil
  var exerciseLibrary: [HomeExercise]? = nil
  var importNotes: [String]? = nil
  var sourceArchive: [String: [[String: String]]]? = nil
}
struct HomeDemoEntryStore {
  let url: URL
  static var local: HomeDemoEntryStore {
    let args = CommandLine.arguments
    if let index = args.firstIndex(of: "--isolated-records"), args.count > index+1 {
      return .init(url: URL(fileURLWithPath: args[index+1]))
    }
    return .init(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("app.bumppump.mac/Records/fitness.sqlite"))
  }
  var isDatabase: Bool { url.pathExtension == "sqlite" }
  func update(commandID: String? = nil, payload: String = "", _ edit: (inout HomeDemoEntries) throws -> Void) throws -> HomeDemoEntries {
    if isDatabase { return try AppRecordDatabase(url:url).update(commandID:commandID,payload:payload,edit) }
    var entries=try read();try edit(&entries);try save(entries);return entries
  }
  func read() throws -> HomeDemoEntries {
    if isDatabase { return try AppRecordDatabase(url:url).read() }
    guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
    var entries = try JSONDecoder().decode(HomeDemoEntries.self, from: Data(contentsOf: url))
    guard [1, 2, 3].contains(entries.version) else { throw HomeEntryError("本机记录版本不兼容，原文件已保留。") }
    for index in entries.weights.indices where entries.weights[index].order == nil { entries.weights[index].order = Double(index) }
    entries.version = 3
    return entries
  }
  func save(_ entries: HomeDemoEntries) throws {
    if isDatabase { _ = try AppRecordDatabase(url:url).update { value in
      guard entries.revision == value.revision else { throw HomeEntryError("数据已更新，请刷新后重试。") }; value=entries
    };return }
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    if let original = try? Data(contentsOf: url), let previous = try? JSONDecoder().decode(HomeDemoEntries.self, from: original), previous.version == 1 {
      let backup = directory.appendingPathComponent("entries-v1.backup.json")
      if !FileManager.default.fileExists(atPath: backup.path) { try original.write(to: backup, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path) }
    }
    try JSONEncoder().encode(entries).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}
struct HomeEntryError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}
extension HomeState {
  func addFood(_ record: HomeAddedFood, editing: Bool = false) throws {
    guard !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !record.amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      [record.nutrition.protein, record.nutrition.carbs, record.nutrition.fat, record.nutrition.energy].allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 10000 }), record.nutrition.energy >= 0 else { throw HomeEntryError("请填写食物、份量和有效的营养数值；确认为零的营养素请填 0。") }
    try updateEntries { entries in
      if editing && !entries.foods.contains(where: { $0.id == record.id }) { throw HomeEntryError("这条记录已被移除，请关闭后刷新记录列表。") }
      if let i = entries.foods.firstIndex(where: { $0.id == record.id }) { entries.foods[i] = record } else { entries.foods.append(record) } }
    selectedDate = Calendar.current.startOfDay(for: record.date)
  }
  func addActivity(_ record: HomeAddedActivity, editing: Bool = false) throws {
    guard !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, (0...1440).contains(record.minutes) && (record.minutes > 0 || record.category == "力量训练" || record.origin != nil), record.kcal.map({ $0.isFinite && $0 >= 0 && $0 <= 20000 }) ?? true else { throw HomeEntryError("请填写运动名称与有效时长；消耗没有依据时可留空。") }
    try updateEntries { entries in
      if editing && !entries.activities.contains(where: { $0.id == record.id }) { throw HomeEntryError("这条记录已被移除，请关闭后刷新记录列表。") }
      if let i = entries.activities.firstIndex(where: { $0.id == record.id }) { entries.activities[i] = record } else { entries.activities.append(record) } }
    selectedDate = Calendar.current.startOfDay(for: record.date)
  }
  func addWeight(_ record: HomeAddedWeight, editing: Bool = false) throws {
    guard record.jin.isFinite && record.jin > 0 && record.jin <= 2000 else { throw HomeEntryError("请输入有效的体重数值。") }
    try updateEntries { entries in
      if editing && !entries.weights.contains(where: { $0.id == record.id }) { throw HomeEntryError("这条记录已被移除，请关闭后刷新记录列表。") }
      var saved = record
      if let i = entries.weights.firstIndex(where: { $0.id == record.id }) { saved.order = entries.weights[i].order; entries.weights[i] = saved }
      else {
        let removedOrders = (entries.trash ?? []).compactMap { item -> Double? in if case .weight(let weight) = item { return weight.order }; return nil }
        saved.order = ((entries.weights.compactMap(\.order) + removedOrders).max() ?? -1) + 1
        entries.weights.append(saved)
      } }
    selectedDate = Calendar.current.startOfDay(for: record.date)
  }
  func setEnergyGoal(_ value: Double?) throws {
    guard value.map({ $0.isFinite && $0 > 0 && $0 <= 20000 }) ?? true else { throw HomeEntryError("请输入大于 0 的有效目标热量。") }
    try updateEntries { $0.energyGoal = value }
  }
  func rebuildDays(base: [DemoDay]? = nil) {
    var result = base ?? (usesExamples ? HomeDemoData.make(anchor: anchor) : [])
    func ensure(_ date: Date) -> Int {
      let day = Calendar.current.startOfDay(for: date)
      if let index = result.firstIndex(where: { $0.date == day }) { return index }
      result.append(.init(date: day, meals: [], activities: [], weightJin: nil)); return result.count-1
    }
    for food in entries.foods {
      let index = ensure(food.date), old = result[index]
      var meals = old.meals
      let value = DemoFood(id: food.id, name: food.name, amount: food.amount, nutrition: food.nutrition)
      let groupID = food.mealID ?? (food.kind.rawValue + "-" + food.time)
      if let mealIndex = meals.firstIndex(where: { $0.id == groupID }) {
        let meal = meals[mealIndex]
        meals[mealIndex] = .init(id: meal.id, kind: meal.kind, title: meal.title, time: meal.time, foods: meal.foods + [value])
      } else { meals.append(.init(id: groupID, kind: food.kind, title: food.kind.rawValue, time: food.time, foods: [value])) }
      result[index] = .init(date: old.date, meals: meals.sorted { $0.time < $1.time }, activities: old.activities, weightJin: old.weightJin)
    }
    for activity in entries.activities {
      let index = ensure(activity.date), old = result[index]
      let value = DemoActivity(id: activity.id, title: activity.title, category: activity.category, time: activity.time, minutes: activity.minutes, kcal: activity.kcal, muscles: activity.muscles, details: ([activity.notes, activity.origin.map { $0.source + " · " + $0.note } ?? ""] + (activity.sets ?? []).enumerated().map { "第\($0.element.group ?? $0.offset + 1)组" + ($0.element.side == "left" ? " · 左侧" : $0.element.side == "right" ? " · 右侧" : "") + " · " + $0.element.summary }).filter { !$0.isEmpty }, manuallyAdded: true, sets: activity.sets, source: activity.origin?.source)
      result[index] = .init(date: old.date, meals: old.meals, activities: old.activities + [value], weightJin: old.weightJin)
    }
    for weight in entries.weights.sorted(by: { ($0.order ?? 0) < ($1.order ?? 0) }) {
      let index = ensure(weight.date), old = result[index]
      result[index] = .init(date: old.date, meals: old.meals, activities: old.activities, weightJin: weight.jin)
    }
    days = result.sorted { $0.date < $1.date }
    energyGoal = entries.energyGoal
    isLoading = false
  }
}
