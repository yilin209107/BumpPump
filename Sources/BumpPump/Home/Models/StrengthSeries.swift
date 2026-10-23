import Foundation

struct StrengthSegment: Identifiable {
  var id: String
  var day: String
  var group: String
  var value: Double
}
struct StrengthSeries: Identifiable {
  var id: String
  var title: String
  var timed: Bool
  var segments: [StrengthSegment]
  var records: [HomeAddedActivity]
  var totals: [String: Double] { Dictionary(grouping: segments, by: \.day).mapValues { $0.reduce(0) { $0 + $1.value } } }
  var groups: [String] { var seen = Set<String>(); return segments.map(\.group).filter { seen.insert($0).inserted } }
  static func make(_ records: [HomeAddedActivity]) -> [Self] {
    var result: [String: Self] = [:]
    for record in records.sorted(by: { $0.date < $1.date }) {
      let day = HomeFormat.date(record.date, pattern: "yyyy-MM-dd")
      for (index, set) in (record.sets ?? []).enumerated() where !set.warmup {
        let timed = set.seconds != nil
        guard let value = timed ? set.seconds : set.reps.map(Double.init), value > 0 else { continue }
        let side = set.side ?? "未注明侧别"
        let key = [record.title, set.basis, side, timed ? "seconds" : "reps", set.weightUnit].joined(separator: "|")
        let title = record.title + " · " + HomeExercise.basisTitle(set.basis) + " · " + (side == "left" ? "左侧" : side == "right" ? "右侧" : side == "both" ? "双侧" : side)
        if result[key] == nil { result[key] = .init(id: key, title: title, timed: timed, segments: [], records: []) }
        let group = "第\(set.group ?? index+1)组"
        result[key]!.segments.append(.init(id: record.id + set.id, day: day, group: group, value: value))
        if !result[key]!.records.contains(where: { $0.id == record.id }) { result[key]!.records.append(record) }
      }
      if let reps = record.unassignedReps, reps > 0 {
        let key = record.title + "|unassigned"
        if result[key] == nil { result[key] = .init(id: key, title: record.title + " · 分组未提供", timed: false, segments: [], records: []) }
        result[key]!.segments.append(.init(id: record.id, day: day, group: "未分组总次数", value: Double(reps)))
        result[key]!.records.append(record)
      }
    }
    return result.values.sorted { lhs, rhs in
      let left = lhs.records.map(\.date).max() ?? .distantPast, right = rhs.records.map(\.date).max() ?? .distantPast
      return left == right ? lhs.title < rhs.title : left > right
    }
  }
}
