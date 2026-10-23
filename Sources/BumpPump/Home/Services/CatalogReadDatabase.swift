import CSQLite
import Foundation

public enum Cell: Equatable, Sendable {
  case text(String)
  case number(Double)
  case null
  public var string: String {
    switch self {
    case .text(let v): return v
    case .number(let v): return v == v.rounded() ? String(format: "%.0f", v) : String(v)
    case .null: return ""
    }
  }
  public var number: Double? {
    switch self {
    case .number(let v): return v
    case .text(let v): return Double(v)
    case .null: return nil
    }
  }
}
public struct Row: Identifiable, Equatable, Sendable {
  public var cells: [String: Cell]
  public var id: String {
    text("id").isEmpty
      ? (text("request_key").isEmpty
        ? (text("log_date").isEmpty ? text("key") : text("log_date")) : text("request_key"))
      : text("id")
  }
  public init(_ cells: [String: Cell]) { self.cells = cells }
  public func text(_ key: String) -> String { cells[key]?.string ?? "" }
  public func number(_ key: String) -> Double? { cells[key]?.number }
  public func flag(_ key: String) -> Bool { number(key) == 1 }
  public func exists(_ key: String) -> Bool {
    if let v = cells[key], v != .null { return true }
    return false
  }
  public func object(_ key: String) -> [String: Any] {
    guard let data = text(key).data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return obj
  }
  public func pretty(_ key: String) -> String {
    let value = text(key)
    if let data = value.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
      JSONSerialization.isValidJSONObject(obj),
      let result = try? JSONSerialization.data(
        withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
      let s = String(data: result, encoding: .utf8)
    {
      return s
    }
    return value.isEmpty ? "—" : value
  }
}
public enum DataError: LocalizedError {
  case message(String)
  public var errorDescription: String? {
    if case .message(let s) = self { return s }
    return nil
  }
}
public final class ReadDatabase {
  private var handle: OpaquePointer?
  public init(path: String) throws {
    guard FileManager.default.fileExists(atPath: path) else {
      throw DataError.message("找不到数据库。请在设置中选择现有食品库数据库。")
    }
    guard
      sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK
    else {
      let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "打开失败"
      if handle != nil { sqlite3_close(handle) }
      handle = nil
      throw DataError.message("打开数据库失败（\(path)）：\(message)")
    }
    sqlite3_busy_timeout(handle, 5000)
    do { _ = try query("PRAGMA query_only = ON") } catch {
      sqlite3_close(handle)
      handle = nil
      throw error
    }
  }
  deinit { sqlite3_close(handle) }
  public func query(_ sql: String, parameters: [Cell] = []) throws -> [Row] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
      throw DataError.message("SQLite \(sqlite3_extended_errcode(handle)) (OS \(sqlite3_system_errno(handle)))，\(sql)：" + String(cString: sqlite3_errmsg(handle)))
    }
    defer { sqlite3_finalize(statement) }
    for (i, p) in parameters.enumerated() {
      switch p {
      case .null: sqlite3_bind_null(statement, Int32(i + 1))
      case .number(let v): sqlite3_bind_double(statement, Int32(i + 1), v)
      case .text(let v):
        v.withCString { ptr in
          _ = sqlite3_bind_text(
            statement, Int32(i + 1), ptr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
      }
    }
    var result: [Row] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { break }
      guard status == SQLITE_ROW else {
        throw DataError.message("SQLite \(sqlite3_extended_errcode(handle)) (OS \(sqlite3_system_errno(handle)))，\(sql)：" + String(cString: sqlite3_errmsg(handle)))
      }
      var cells: [String: Cell] = [:]
      for i in 0..<sqlite3_column_count(statement) {
        let key = String(cString: sqlite3_column_name(statement, i))
        switch sqlite3_column_type(statement, i) {
        case SQLITE_NULL: cells[key] = .null
        case SQLITE_INTEGER, SQLITE_FLOAT: cells[key] = .number(sqlite3_column_double(statement, i))
        default:
          cells[key] = sqlite3_column_text(statement, i).map { .text(String(cString: $0)) } ?? .null
        }
      }
      result.append(Row(cells))
    }
    return result
  }
}
