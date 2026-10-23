import Foundation

struct HomeRecordOrigin: Codable {
  var source: String
  var recordID: String
  var note: String
  var fields: [String: String]? = nil
}
struct HomeStrengthSet: Codable, Identifiable {
  var id = UUID().uuidString
  var reps: Int? = nil
  var seconds: Double? = nil
  var weight: Double? = nil
  var weightUnit = "kg"
  var basis = "unknown"
  var side: String? = nil
  var pairID: String? = nil
  var group: Int? = nil
  var warmup = false
  var rir: Double? = nil
  var rpe: Double? = nil
  var restSeconds: Double? = nil
  var notes: String? = nil
  var summary: String {
    let count = reps.map { "\($0) 次" } ?? seconds.map { HomeFormat.number($0) + " 秒" } ?? "次数未记录"
    let load = weight.map { HomeFormat.number($0, digits: 1) + " " + weightUnit + " · " + HomeExercise.basisTitle(basis) + " · " } ?? ""
    return load + count + (warmup ? " · 热身" : "")
  }
}
struct HomeExercise: Codable, Identifiable, Hashable {
  var id: String
  var name: String
  var muscle: String
  var basis: String
  var timed = false
  var notes: String? = nil
  static let defaults: [Self] = [
    .init(id: "curl", name: "哑铃弯举", muscle: "大臂", basis: "per_hand"),
    .init(id: "triceps", name: "双手哑铃臂屈伸", muscle: "大臂", basis: "total"),
    .init(id: "fly", name: "哑铃飞鸟", muscle: "胸", basis: "per_hand"),
    .init(id: "squat", name: "哑铃深蹲", muscle: "大腿", basis: "per_hand"),
    .init(id: "plank", name: "平板支撑", muscle: "腹", basis: "bodyweight", timed: true),
    .init(id: "sidebend", name: "负重体侧屈", muscle: "腹", basis: "per_side"),
    .init(id: "power", name: "臂力棒下压", muscle: "胸", basis: "resistance_rating"),
    .init(id: "row", name: "单臂哑铃划船", muscle: "背", basis: "per_side"),
    .init(id: "lateral", name: "侧平举", muscle: "肩", basis: "per_hand"),
    .init(id: "wrist", name: "腕弯举", muscle: "小臂", basis: "per_hand"),
    .init(id: "calf", name: "站姿提踵", muscle: "小腿", basis: "bodyweight")
  ]
  static let bases = ["per_hand", "per_side", "total", "machine_stack", "bodyweight", "assisted", "resistance_rating", "unknown"]
  static func basisTitle(_ value: String) -> String {
    switch value { case "per_hand": return "每只手"; case "per_side": return "单侧"; case "total": return "合计"; case "machine_stack": return "器械配重"; case "bodyweight": return "自重"; case "assisted": return "辅助重量"; case "resistance_rating": return "器材标称阻力"; default: return "负重口径未确认" }
  }
}
@MainActor extension HomeState {
  var exercises: [HomeExercise] {
    var imported = entries.exerciseLibrary ?? []
    for record in entries.activities where record.category == "力量训练" && !imported.contains(where: { $0.name == record.title }) {
      imported.append(.init(id: "record-exercise-" + record.title, name: record.title, muscle: record.muscles.first ?? "其他", basis: record.sets?.first?.basis ?? "unknown", timed: record.sets?.first?.seconds != nil))
    }
    return (imported + HomeExercise.defaults.filter { item in !imported.contains { $0.name == item.name } }).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}

extension Array where Element == HomeStrengthSet {
  var logicalGroupCount: Int { Set(map { $0.pairID ?? $0.id }).count }
}
