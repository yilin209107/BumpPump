import Foundation

/// Food-product catalogue is independent from meals and demonstration records.
struct HomePackagedFood: Identifiable, Sendable, Codable, Hashable {
  let id: String
  let fields: [String: String]
  var name: String { fields["name"] ?? "未命名食品" }
  var brand: String { fields["brand"] ?? "" }
  var basis: String {
    switch fields["basis"] {
    case "100g": return "每 100 g"
    case "100ml": return "每 100 ml"
    case "serving":
      let size = [fields["serving_size"], fields["serving_unit"]].compactMap { $0 }.joined(separator: " ")
      return size.isEmpty ? "每份 · 份量未注明" : "每份 · " + size
    default: return "营养基准未注明"
    }
  }
  func value(_ key: String, unit: String) -> String {
    guard let raw = fields[key], let number = Double(raw), number.isFinite else { return "—" }
    return HomeFormat.number(number, digits: key == "kcal" ? 0 : 1) + " " + unit
  }
  var source: String {
    switch fields["source"] {
    case "label_text": return "标签文字"
    case "reference": return "参考值"
    case "unverified": return "待核对"
    case "user_reported": return "用户提供"
    case "model_judgment": return "模型估算"
    default: return fields["source"] ?? "来源未注明"
    }
  }
  var amountUnits: [String] {
    if fields["basis"] == "100g" { return ["g"] }
    if fields["basis"] == "100ml" { return ["ml"] }
    return ["份"] + (["g", "ml"].contains(fields["serving_unit"] ?? "") && Double(fields["serving_size"] ?? "") ?? 0 > 0 ? [fields["serving_unit"]!] : [])
  }
  func nutrition(quantity: Double, unit: String) throws -> DemoNutrition {
    guard quantity.isFinite, quantity > 0, quantity <= 100000, amountUnits.contains(unit) else { throw HomeEntryError("请填写有效份量，并使用标签对应的 g／ml／份单位。") }
    let divisor: Double
    if fields["basis"] == "100g" || fields["basis"] == "100ml" { divisor = 100 }
    else if fields["basis"] == "serving", unit == "份" { divisor = 1 }
    else if let size = Double(fields["serving_size"] ?? ""), size > 0 { divisor = size }
    else { throw HomeEntryError("这条标签没有可换算的营养基准，请选择其他并手动填写。") }
    let keys = ["protein_g", "carbs_g", "fat_g", "kcal"]
    let values = keys.reduce(into: [String: Double]()) { result, key in
      if let raw = fields[key], let n = Double(raw), n.isFinite, n >= 0 { result[key] = n * quantity / divisor }
    }
    let missing = Set(keys.filter { values[$0] == nil })
    return .init(protein: values["protein_g"] ?? 0, carbs: values["carbs_g"] ?? 0, fat: values["fat_g"] ?? 0,
      recordedEnergy: values["kcal"] ?? 0, missing: missing)
  }
}
