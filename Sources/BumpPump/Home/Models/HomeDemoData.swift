import Foundation

struct DemoNutrition: Equatable, Codable {
  var protein: Double = 0
  var carbs: Double = 0
  var fat: Double = 0
  var recordedEnergy: Double? = nil
  var missing: Set<String>? = nil
  var energy: Double { recordedEnergy ?? (protein * 4 + carbs * 4 + fat * 9) }
  var energyText: String { isKnown("kcal") || energy > 0 ? HomeFormat.number(energy) : "—" }
  var animationKey: String {
    [String(protein.bitPattern), String(carbs.bitPattern), String(fat.bitPattern), String(energy.bitPattern), (missing ?? []).sorted().joined(separator: ",")].joined(separator: "|")
  }
  func isKnown(_ key: String) -> Bool { !(missing ?? []).contains(key) }
  func text(_ key: String, value: Double, digits: Int = 1) -> String { isKnown(key) || value > 0 ? HomeFormat.number(value, digits: digits) : "—" }
  static func + (lhs: Self, rhs: Self) -> Self {
    .init(protein: lhs.protein + rhs.protein, carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat,
      recordedEnergy: lhs.energy + rhs.energy, missing: (lhs.missing ?? []).union(rhs.missing ?? []))
  }
  func scaled(_ factor: Double) -> Self { .init(protein: protein * factor, carbs: carbs * factor, fat: fat * factor, recordedEnergy: recordedEnergy.map { $0 * factor }, missing: missing) }
}
enum DemoMealKind: String, CaseIterable, Identifiable, Codable {
  case breakfast = "早餐", lunch = "午餐", dinner = "晚餐", snack = "加餐"
  var id: String { rawValue }
  var icon: String { switch self { case .breakfast: return "sunrise"; case .lunch: return "sun.max"; case .dinner: return "moon"; case .snack: return "carrot" } }
}
struct DemoFood: Identifiable {
  var id = UUID().uuidString
  let name: String
  let amount: String
  let nutrition: DemoNutrition
}
struct DemoMeal: Identifiable {
  let id: String
  let kind: DemoMealKind
  let title: String
  let time: String
  let foods: [DemoFood]
  var nutrition: DemoNutrition { foods.reduce(.init()) { $0 + $1.nutrition } }
}
struct DemoActivity: Identifiable {
  let id: String
  let title: String
  let category: String
  let time: String
  let minutes: Int
  let kcal: Double?
  let muscles: [String]
  let details: [String]
  var manuallyAdded = false
  var sets: [HomeStrengthSet]? = nil
  var source: String? = nil
  var detailLine: String {
    let parts = [sets.map { "\($0.logicalGroupCount) 组" }, minutes > 0 ? "\(minutes) 分钟" : nil, time.isEmpty ? nil : time].compactMap { $0 }
    return parts.isEmpty ? "时间与时长未记录" : parts.joined(separator: " · ")
  }
  var energySource: String { source ?? (manuallyAdded ? "手动填写" : "设备估算") }
  var icon: String { category == "力量训练" ? "dumbbell" : (title == "篮球" ? "basketball" : "figure.run") }
}
struct DemoDay: Identifiable {
  let date: Date
  let meals: [DemoMeal]
  let activities: [DemoActivity]
  let weightJin: Double?
  var id: Date { date }
  var nutrition: DemoNutrition { meals.reduce(.init()) { $0 + $1.nutrition } }
}
struct DemoWeight: Identifiable { let date: Date; let jin: Double; var id: Date { date } }
struct DemoEnergy: Identifiable {
  let date: Date
  let kind: DemoMealKind
  let kcal: Double
  var id: String { "\(date.timeIntervalSince1970)-\(kind.rawValue)" }
}
struct HomeDetailRow: Identifiable {
  let title: String
  let value: String
  var id: String { title + value }
}
struct HomeRecordDetail: Identifiable {
  let title: String
  let date: Date
  let rows: [HomeDetailRow]
  var id: String { title + String(date.timeIntervalSince1970) }
}
/// Synthetic fixtures only. Never reads a user's fitness database or API credentials.
enum HomeDemoData {
  static func make(anchor: Date, calendar: Calendar = .current) -> [DemoDay] {
    let anchor = calendar.startOfDay(for: anchor)
    return (0..<90).map { index in
      let date = calendar.date(byAdding: .day, value: index - 89, to: anchor)!
      let factor = 0.88 + Double((index * 7) % 13) * 0.019
      func food(_ name: String, _ amount: String, _ protein: Double, _ carbs: Double, _ fat: Double) -> DemoFood {
        .init(name: name, amount: amount, nutrition: .init(protein: protein, carbs: carbs, fat: fat).scaled(factor))
      }
      let key = "demo-\(index)"
      var meals: [DemoMeal] = [
        .init(id: key + "-breakfast", kind: .breakfast, title: "早餐", time: "08:10", foods: [food("燕麦牛奶", "1 碗", 17, 62, 12), food("水煮蛋", "1 个", 7, 1, 5), food("香蕉", "1 根", 1, 25, 0.3)]),
        .init(id: key + "-lunch", kind: .lunch, title: "午餐", time: "12:30", foods: [food("香煎鸡胸肉", "150 g", 38, 2, 8), food("杂粮饭", "200 g", 6, 66, 2), food("清炒时蔬", "1 份", 3, 12, 8)]),
        .init(id: key + "-dinner", kind: .dinner, title: "晚餐", time: "18:45", foods: [food("烤三文鱼", "120 g", 25, 0, 16), food("烤土豆", "200 g", 5, 42, 6), food("蔬菜沙拉", "1 份", 2, 10, 7)]),
        .init(id: key + "-snack-1", kind: .snack, title: "加餐 1", time: "15:40", foods: [food("原味酸奶", "200 g", 10, 16, 6), food("蓝莓", "80 g", 0.6, 12, 0.2)])
      ]
      if index % 3 != 0 { meals.append(.init(id: key + "-snack-2", kind: .snack, title: "加餐 2", time: "20:30", foods: [food("混合坚果", "20 g", 4, 5, 11)])) }
      var activities: [DemoActivity] = []
      if index % 3 != 0 {
        activities.append(.init(id: key + "-strength", title: index % 2 == 0 ? "上肢力量训练" : "下肢力量训练", category: "力量训练", time: "17:00", minutes: 48, kcal: nil,
          muscles: index % 2 == 0 ? ["胸", "肩", "大臂", "背", "小臂"] : ["大腿", "小腿", "腹"],
          details: index % 2 == 0 ? ["哑铃卧推 · 12 kg × 10 次 × 3 组", "坐姿划船 · 25 kg × 12 次 × 3 组", "哑铃弯举 · 6 kg × 12 次 × 3 组"] : ["高脚杯深蹲 · 12 kg × 12 次 × 3 组", "站姿提踵 · 自重 × 15 次 × 3 组", "平板支撑 · 30 秒 × 3 组"]))
      }
      if index % 2 != 0 {
        let basketball = index % 5 == 4
        activities.append(.init(id: key + "-cardio", title: basketball ? "篮球" : "跑步", category: "有氧训练", time: "19:30", minutes: basketball ? 45 : 25, kcal: basketball ? 286 : 182, muscles: [], details: [basketball ? "半场篮球 · 轻至中等强度" : "户外慢跑 · 3.2 km", "消耗数值来自演示设备记录，并非按力量训练重量推算。其他设备与个人情况可能不同。 "]))
      }
      let weight: Double? = index % 3 == 2 ? 125.2 - Double(index) * 0.014 + sin(Double(index) * 0.23) * 0.65 : nil
      return DemoDay(date: date, meals: meals, activities: activities, weightJin: weight)
    }
  }
}
enum HomeFormat {
  static func number(_ value: Double, digits: Int = 0) -> String { String(format: "%.*f", digits, value) }
  static func date(_ date: Date, pattern: String = "M月d日") -> String {
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = pattern
    return formatter.string(from: date)
  }
}
