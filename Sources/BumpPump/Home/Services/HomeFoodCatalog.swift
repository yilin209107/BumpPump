import Foundation

struct HomeFoodCatalogResult: Sendable {
  let path: String?
  let foods: [HomePackagedFood]
  let message: String
}
enum HomeFoodCatalog {
  static func read(path: String) throws -> [HomePackagedFood] {
    let database = try ReadDatabase(path: path)
    _ = try database.query("BEGIN")
    defer { _ = try? database.query("ROLLBACK") }
    let version = try database.query("SELECT value FROM meta WHERE key = ?", parameters: [.text("schema_version")]).first?.text("value")
    guard ["4", "5"].contains(version ?? "") else { throw DataError.message("食品库数据库版本不兼容，支持版本 4／5。") }
    return try database.query("SELECT * FROM food_products WHERE is_current = ? ORDER BY brand COLLATE NOCASE, name COLLATE NOCASE", parameters: [.number(1)]).map { row in
      HomePackagedFood(id: row.id, fields: row.cells.reduce(into: [:]) { values, item in
        if item.value != .null { values[item.key] = item.value.string }
      })
    }
  }
  static func load(path: String?) -> HomeFoodCatalogResult {
    do {
      if let path, !path.isEmpty { return .init(path: path, foods: try read(path: path), message: "") }
      return .init(path: nil, foods: [], message: "请选择要导入的食品库数据库。")
    } catch { return .init(path: nil, foods: [], message: "食品库暂时无法读取，请重新选择已有数据库。") }
  }
}
extension HomeState {
  func loadPackagedFoods(path: String? = nil, force: Bool = false) async {
    guard !catalogLoading, force || !catalogLoaded else { return }
    catalogLoading = true
    guard let path else {
      packagedFoods = entries.foodLibrary ?? []; catalogPath = nil
      catalogMessage = packagedFoods.isEmpty ? "尚无食品标签。可以先选择其他手动记录，或导入已有食品库。" : ""
      catalogLoading = false; catalogLoaded = true; return
    }
    let result = await Task.detached(priority: .userInitiated) { HomeFoodCatalog.load(path: path) }.value
    if result.path != nil {
      do { try updateEntries { entries in var byID = Dictionary(uniqueKeysWithValues: (entries.foodLibrary ?? []).map { ($0.id, $0) }); for food in result.foods { byID[food.id] = food }; entries.foodLibrary = byID.values.sorted { $0.name < $1.name } }; packagedFoods = entries.foodLibrary ?? []; catalogMessage = "已将食品标签保存到 App 本机数据。" }
      catch { catalogMessage = "未能保存食品库，原数据已保留。" }
    } else { catalogMessage = result.message }
    catalogPath = nil; catalogLoading = false; catalogLoaded = true

  }
}
