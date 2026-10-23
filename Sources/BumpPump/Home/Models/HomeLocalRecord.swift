import Foundation

/// Only app-added records are editable. Generated examples and the SQL catalogue stay separate.
enum HomeLocalRecord: Codable, Identifiable {
  case food(HomeAddedFood), activity(HomeAddedActivity), weight(HomeAddedWeight)
  var id: String { kind.rawValue + ":" + storageID }
  var storageID: String {
    switch self { case .food(let r): return r.id; case .activity(let r): return r.id; case .weight(let r): return r.id }
  }
  var kind: HomeEntryKind { switch self { case .food: return .food; case .activity: return .activity; case .weight: return .weight } }
  var date: Date { switch self { case .food(let r): return r.date; case .activity(let r): return r.date; case .weight(let r): return r.date } }
  var title: String { switch self { case .food(let r): return r.name; case .activity(let r): return r.title; case .weight: return "体重测量" } }
  var category: String { switch self { case .food(let r): return r.kind.rawValue; case .activity(let r): return r.category; case .weight: return "身体测量" } }
  var summary: String {
    switch self {
    case .food(let r): return r.amount + " · " + r.nutrition.energyText + " kcal"
    case .activity(let r): return (r.sets.map { "\($0.logicalGroupCount) 组 · " } ?? "") + (r.minutes > 0 ? "\(r.minutes) 分钟 · " : "") + (r.kcal.map { HomeFormat.number($0) + " kcal" } ?? "消耗未记录")
    case .weight(let r): return HomeFormat.number(r.jin/2, digits: 2) + " kg · " + HomeFormat.number(r.jin, digits: 1) + " 斤"
    }
  }
}
extension HomeState {
  var localRecords: [HomeLocalRecord] {
    (entries.foods.map(HomeLocalRecord.food) + entries.activities.map(HomeLocalRecord.activity) + entries.weights.map(HomeLocalRecord.weight))
      .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
  }
  var removedRecords: [HomeLocalRecord] { entries.trash ?? [] }
  func moveToTrash(_ record: HomeLocalRecord) throws {
    try updateEntries { entries in
      var removed: HomeLocalRecord?
      switch record {
      case .food: if let i = entries.foods.firstIndex(where: { $0.id == record.storageID }) { removed = .food(entries.foods.remove(at: i)) }
      case .activity: if let i = entries.activities.firstIndex(where: { $0.id == record.storageID }) { removed = .activity(entries.activities.remove(at: i)) }
      case .weight: if let i = entries.weights.firstIndex(where: { $0.id == record.storageID }) { removed = .weight(entries.weights.remove(at: i)) }
      }
      guard let removed else { throw HomeEntryError("这条记录已被其他窗口更新，请刷新后重试。") }
      var trash = entries.trash ?? []
      trash.removeAll { $0.id == removed.id }; trash.append(removed); entries.trash = trash
    }
  }
  func restoreRecord(_ record: HomeLocalRecord) throws {
    try updateEntries { entries in
      guard let saved = entries.trash?.first(where: { $0.id == record.id }) else { throw HomeEntryError("这条记录已经恢复，请刷新查看。") }
      switch saved {
      case .food(let r): guard !entries.foods.contains(where: { $0.id == r.id }) else { throw HomeEntryError("已有同一条记录，未覆盖。") }; entries.foods.append(r)
      case .activity(let r): guard !entries.activities.contains(where: { $0.id == r.id }) else { throw HomeEntryError("已有同一条记录，未覆盖。") }; entries.activities.append(r)
      case .weight(let r): guard !entries.weights.contains(where: { $0.id == r.id }) else { throw HomeEntryError("已有同一条记录，未覆盖。") }; entries.weights.append(r)
      }
      entries.trash?.removeAll { $0.id == saved.id }
    }
  }
}
