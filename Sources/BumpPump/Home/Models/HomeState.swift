import SwiftUI

enum HomeDestination: Hashable, Identifiable {
  case overview, meal(DemoMealKind), foods, strength(String), cardio(String)
  var id: String { title }
  var title: String {
    switch self { case .overview: return "主页 · 概览"; case .meal(let kind): return kind.rawValue; case .foods: return "已知食物营养成分"; case .strength(let name), .cardio(let name): return name }
  }
  var group: String {
    switch self { case .overview: return ""; case .meal, .foods: return "饮食"; case .strength: return "力量训练"; case .cardio: return "有氧训练" }
  }
  static let strengthNames = ["小臂", "大臂", "肩", "胸", "背", "腹", "大腿", "小腿"]
  static let cardioNames = ["篮球", "羽毛球", "跑步", "足球", "乒乓球", "其他"]
  static var all: [Self] { [.overview] + DemoMealKind.allCases.map(Self.meal) + [.foods] + strengthNames.map(Self.strength) + cardioNames.map(Self.cardio) }
}
struct HomeSearchResult: Identifiable {
  let title: String
  let subtitle: String
  let destination: HomeDestination
  var catalogFoodID: String? = nil
  var id: String { (catalogFoodID ?? title) + subtitle + destination.id }
}
@MainActor final class HomeState: ObservableObject {
  @Published var destination = HomeDestination.overview
  @Published var selectedDate: Date
  @Published var range = 30
  @Published var query = ""
  @Published var days: [DemoDay] = []
  @Published var isLoading = true
  @Published var expandedMealID: String?
  @Published var detail: HomeRecordDetail?
  @Published var entry: HomeEntryKind?
  @Published var showRecords = false
  @Published var catalogQuery = ""
  @Published var selectedPackagedFood: HomePackagedFood?
  @Published var energyGoal: Double?
  @Published var entryMeal: DemoMealKind?
  @Published var packagedFoods: [HomePackagedFood] = []
  @Published var catalogLoading = false
  @Published var catalogLoaded = false
  @Published var catalogMessage = ""
  @Published var catalogPath: String?
  @Published var entryStorageError: String?
  var entries = HomeDemoEntries()
  let entryStore: HomeDemoEntryStore?
  let usesExamples: Bool
  private var entryStorageBlocked = false
  @Published private(set) var anchor: Date
  private var loadingTask: Task<Void, Never>?
  init(anchor: Date = Date(), preload: Bool = false, entryStore: HomeDemoEntryStore? = nil, usesExamples: Bool = false) {
    self.usesExamples = usesExamples
    self.entryStore = entryStore
    self.anchor = Calendar.current.startOfDay(for: anchor)
    selectedDate = Calendar.current.startOfDay(for: anchor)
    if let entryStore {
      do { entries = try entryStore.read() }
      catch { entryStorageError = "本机记录暂时无法读取，原文件已保留。"; entryStorageBlocked = true }
    }
    packagedFoods = entries.foodLibrary ?? []
    if preload { rebuildDays(); isLoading = false }
  }
  var day: DemoDay? { days.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) } ?? DemoDay(date: selectedDate, meals: [], activities: [], weightJin: nil) }
  var availableDates: ClosedRange<Date> { Calendar.current.date(from: DateComponents(year: 1900, month: 1, day: 1))!...anchor }
  var history: [DemoDay] {
    let start = Calendar.current.date(byAdding: .day, value: -(range-1), to: selectedDate)!
    return days.filter { $0.date >= start && $0.date <= selectedDate }
  }
  var weights: [DemoWeight] { history.compactMap { day in day.weightJin.map { DemoWeight(date: day.date, jin: $0) } } }
  var energy: [DemoEnergy] { history.flatMap { day in DemoMealKind.allCases.compactMap { kind in
    let meals = day.meals.filter { $0.kind == kind }
    return meals.isEmpty || meals.allSatisfy({ !$0.nutrition.isKnown("kcal") && $0.nutrition.energy == 0 }) ? nil : DemoEnergy(date: day.date, kind: kind, kcal: meals.reduce(0) { $0 + $1.nutrition.energy })
  } } }
  var searchResults: [HomeSearchResult] {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return [] }
    let destinations = HomeDestination.all.filter { $0.title.localizedCaseInsensitiveContains(text) || $0.group.localizedCaseInsensitiveContains(text) }
      .map { HomeSearchResult(title: $0.title, subtitle: $0.group.isEmpty ? "页面" : $0.group, destination: $0) }
    let foodResults = (day?.meals ?? []).flatMap { meal in meal.foods.filter { $0.name.localizedCaseInsensitiveContains(text) }.map {
      HomeSearchResult(title: $0.name, subtitle: meal.title + " · " + $0.amount, destination: .meal(meal.kind))
    } }
    let products = packagedFoods.filter { ($0.name + $0.brand + ($0.fields["aliases"] ?? "")).localizedCaseInsensitiveContains(text) }.map {
      HomeSearchResult(title: $0.name, subtitle: "预包装食品 · " + $0.basis + " · " + $0.brand, destination: .foods, catalogFoodID: $0.id)
    }
    var seen = Set<String>()
    return (destinations + foodResults + products).filter { seen.insert($0.id).inserted }
  }
  func load() {
    guard loadingTask == nil, days.isEmpty else { return }
    isLoading = true
    let anchor = self.anchor, examples = self.usesExamples
    loadingTask = Task {
      let values = await Task.detached(priority: .userInitiated) { (examples ? HomeDemoData.make(anchor: anchor) : []) }.value
      guard !Task.isCancelled else { return }
      rebuildDays(base: values); isLoading = false; loadingTask = nil
    }
  }
  func updateEntries(_ edit: (inout HomeDemoEntries) throws -> Void) throws {
    try updateEntries(commandID: nil, payload: "", edit)
  }
  func updateEntries(commandID: String?, payload: String, _ edit: (inout HomeDemoEntries) throws -> Void) throws {
    guard !entryStorageBlocked else { throw HomeEntryError("原有记录读取失败，为避免覆盖，暂时无法保存。") }
    if let entryStore { entries=try entryStore.update(commandID:commandID,payload:payload,edit) }
    else { var next=entries;try edit(&next);entries=next }
    packagedFoods=entries.foodLibrary ?? packagedFoods
    rebuildDays()
  }
  func refreshLocalEntries() {
    guard entry == nil, let entryStore else { return }
    do { entries = try entryStore.read(); entryStorageBlocked = false; entryStorageError = nil; rebuildDays() }
    catch { entryStorageBlocked = true; entryStorageError = "本机记录暂时无法读取。原文件已保留，修复后可重新刷新。" }
  }
  func refreshCalendar(now: Date = Date()) {
    let today = Calendar.current.startOfDay(for: now)
    guard today > anchor else { return }
    let followedToday = selectedDate == anchor
    anchor = today
    if followedToday { selectedDate = today }
    rebuildDays()
  }
  func beginEntry(_ kind: HomeEntryKind) { entryMeal = nil; entry = kind }
  func beginContextEntry() {
    switch destination {
    case .meal(let meal): recordMeal(meal)
    case .strength, .cardio: beginEntry(.activity)
    default: beginEntry(.food)
    }
  }
  func recordMeal(_ kind: DemoMealKind) { entryMeal = kind; entry = .food }
  func select(_ destination: HomeDestination) { self.destination = destination; query = ""; expandedMealID = nil }
  func selectSearchResult(_ result: HomeSearchResult) {
    select(result.destination)
    if let id = result.catalogFoodID { catalogQuery = ""; selectedPackagedFood = packagedFoods.first { $0.id == id } }
  }
  func showMeal(_ meal: DemoMeal, date: Date) {
    detail = HomeRecordDetail(title: meal.title, date: date, rows: meal.foods.map { .init(title: $0.name + " · " + $0.amount, value: $0.nutrition.energyText + " kcal") } + meal.foods.compactMap { food in
      entries.foods.first(where: { $0.id == food.id })?.origin.map { HomeDetailRow(title: food.name + " · 来源", value: $0.source + " · " + $0.note) }
    } + [
      .init(title: "热量合计", value: meal.nutrition.energyText + " kcal"),
      .init(title: "蛋白质 / 碳水 / 脂肪", value: "\(meal.nutrition.text("protein_g", value: meal.nutrition.protein)) / \(meal.nutrition.text("carbs_g", value: meal.nutrition.carbs)) / \(meal.nutrition.text("fat_g", value: meal.nutrition.fat)) g")])
  }
  func showWeight(_ weight: DemoWeight) {
    let conditions = entries.weights.last(where: { Calendar.current.isDate($0.date, inSameDayAs: weight.date) }).map { $0.conditions.isEmpty ? "未填写" : $0.conditions } ?? "未填写"
    detail = .init(title: "身体测量", date: weight.date, rows: [.init(title: "体重", value: HomeFormat.number(weight.jin, digits: 1) + " 斤"), .init(title: "换算为千克", value: HomeFormat.number(weight.jin/2, digits: 2) + " kg"), .init(title: "测量条件", value: conditions)])
  }
  func showActivity(_ activity: DemoActivity) {
    detail = .init(title: activity.title, date: selectedDate, rows: [.init(title: "时间 / 时长", value: activity.time + (activity.minutes > 0 ? " · \(activity.minutes) 分钟" : " · 时长未记录")), .init(title: "活动消耗", value: activity.kcal.map { HomeFormat.number($0) + " kcal · " + activity.energySource } ?? "未记录，不按训练组数估算")] + activity.details.enumerated().map { .init(title: "详情 \($0.offset+1)", value: $0.element) })
  }
  func showEnergy(_ date: Date) {
    guard let day = days.first(where: { $0.date == date }) else { return }
    detail = .init(title: "饮食记录", date: date, rows: day.meals.map { .init(title: $0.title + " · " + $0.time, value: $0.nutrition.energyText + " kcal") } + day.meals.flatMap(\.foods).compactMap { food in
      entries.foods.first(where: { $0.id == food.id })?.origin.map { HomeDetailRow(title: food.name + " · 来源", value: $0.source + " · " + $0.note) }
    } + [.init(title: "已记录热量合计", value: day.nutrition.energyText + " kcal")])
  }
}
