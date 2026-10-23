import Foundation
import CSQLite
import CryptoKit

/// Private application database. No SQL supplied by a model is ever executed.
/// The versioned document preserves every imported field while services own its schema.
struct AppRecordDatabase {
  let url: URL
  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  private func connect() throws -> OpaquePointer {
    try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path,&db,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE|SQLITE_OPEN_FULLMUTEX,nil)==SQLITE_OK, let db else { if let db { sqlite3_close(db) }; throw HomeEntryError("无法打开本机数据库，原记录已保留。") }
    sqlite3_busy_timeout(db,5000)
    do {
      // Refuse a foreign database before making any schema changes.
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(db,"SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",-1,&statement,nil)==SQLITE_OK else {throw HomeEntryError("数据库文件无法识别，原文件未修改。")}
      var tables=Set<String>()
      while sqlite3_step(statement)==SQLITE_ROW {tables.insert(String(cString:sqlite3_column_text(statement,0)))}
      sqlite3_finalize(statement)
      guard tables.isSubset(of:["app_state","change_journal","command_receipts"]) else {throw HomeEntryError("这个文件不是App自己的记录库，未修改。请使用导入功能读取历史数据。")}
      sqlite3_prepare_v2(db,"PRAGMA user_version",-1,&statement,nil);sqlite3_step(statement)
      let version=sqlite3_column_int(statement,0);sqlite3_finalize(statement)
      guard version<=1 else{throw HomeEntryError("本机数据库来自更新版本，请更新App后再打开。")}
      try run(db,"PRAGMA foreign_keys=ON")
      try run(db,"BEGIN IMMEDIATE")
      try run(db,"CREATE TABLE IF NOT EXISTS app_state (id INTEGER PRIMARY KEY CHECK(id=1), revision INTEGER NOT NULL, payload BLOB NOT NULL)")
      try run(db,"CREATE TABLE IF NOT EXISTS change_journal (revision INTEGER PRIMARY KEY, change_id TEXT UNIQUE NOT NULL, created_at REAL NOT NULL, previous_payload BLOB NOT NULL)")
      try run(db,"CREATE TABLE IF NOT EXISTS command_receipts (command_id TEXT PRIMARY KEY, payload_hash TEXT NOT NULL, revision INTEGER NOT NULL)")
      try run(db,"PRAGMA application_id=1179210817")
      try run(db,"PRAGMA user_version=1")
      try run(db,"COMMIT")
      try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
      return db
    } catch {try? run(db,"ROLLBACK");sqlite3_close(db);throw error}
  }
  private func run(_ db: OpaquePointer,_ sql: String,_ values: [Data] = []) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db,sql,-1,&statement,nil)==SQLITE_OK,let statement else { throw HomeEntryError("数据库结构暂时无法读取。") }
    defer { sqlite3_finalize(statement) }
    for (index,data) in values.enumerated() { _ = data.withUnsafeBytes { sqlite3_bind_blob(statement,Int32(index+1),$0.baseAddress,Int32(data.count),transient) } }
    guard sqlite3_step(statement)==SQLITE_DONE else { throw HomeEntryError("未能提交记录；请稍后重试。") }
  }
  private func row(_ db: OpaquePointer) throws -> HomeDemoEntries? {
    var s: OpaquePointer?; guard sqlite3_prepare_v2(db,"SELECT revision,payload FROM app_state WHERE id=1",-1,&s,nil)==SQLITE_OK,let s else { throw HomeEntryError("无法读取本机数据。") };defer{sqlite3_finalize(s)}
    let result=sqlite3_step(s);if result==SQLITE_DONE{return nil};guard result==SQLITE_ROW,let bytes=sqlite3_column_blob(s,1) else { throw HomeEntryError("本机数据不完整，未覆盖原文件。") }
    var entries=try JSONDecoder().decode(HomeDemoEntries.self,from:Data(bytes:bytes,count:Int(sqlite3_column_bytes(s,1))))
    entries.revision=Int(sqlite3_column_int64(s,0));return entries
  }
  private func seed(_ db: OpaquePointer) throws -> HomeDemoEntries {
    if let entries=try row(db){return entries}
    let original=url.deletingLastPathComponent().appendingPathComponent("entries.json")
    let entries=FileManager.default.fileExists(atPath:original.path) ? try JSONDecoder().decode(HomeDemoEntries.self,from:Data(contentsOf:original)) : HomeDemoEntries()
    guard [1,2,3].contains(entries.version) else { throw HomeEntryError("原记录版本不兼容，未迁移。") }
    let encoded=try JSONEncoder().encode(entries)
    try run(db,"INSERT INTO app_state(id,revision,payload) VALUES(1,0,?)",[encoded])
    // Migration is checked by decoding the exact committed payload; original JSON is retained.
    guard var saved=try row(db) else {throw HomeEntryError("迁移核对未通过，原记录已保留。")}
    let revision=saved.revision;saved.revision=entries.revision
    let verifier=JSONEncoder();verifier.outputFormatting=[.sortedKeys]
    guard try verifier.encode(saved)==verifier.encode(entries) else{throw HomeEntryError("迁移字段核对未通过，原记录已保留。")}
    saved.revision=revision;return saved
  }
  func read() throws -> HomeDemoEntries {
    let db=try connect();defer{sqlite3_close(db)}
    try run(db,"BEGIN IMMEDIATE");do { let value=try seed(db);try run(db,"COMMIT");return value } catch {try? run(db,"ROLLBACK");throw error}
  }
  func update(commandID: String? = nil, payload: String = "", _ edit: (inout HomeDemoEntries) throws -> Void) throws -> HomeDemoEntries {
    try updateInTransaction(commandID:commandID,payload:payload){current,_ in try edit(&current)}
  }
  private func updateInTransaction(commandID:String?=nil,payload:String="",_ edit:(inout HomeDemoEntries,OpaquePointer)throws->Void)throws->HomeDemoEntries {
    let db=try connect();defer{sqlite3_close(db)}
    try run(db,"BEGIN IMMEDIATE")
    do {
      var current=try seed(db)
      if let commandID {
        var s: OpaquePointer?;sqlite3_prepare_v2(db,"SELECT payload_hash FROM command_receipts WHERE command_id=?",-1,&s,nil);defer{sqlite3_finalize(s)}
        sqlite3_bind_text(s,1,commandID,-1,transient)
        if sqlite3_step(s)==SQLITE_ROW {
          let existing=String(cString:sqlite3_column_text(s,0));guard existing==Self.hash(payload) else {throw HomeEntryError("相同请求标识的内容不一致，未执行。")}
          try run(db,"COMMIT");return current
        }
      }
      let before=try JSONEncoder().encode(current),revision=(current.revision ?? 0)+1
      try edit(&current,db);current.revision=revision
      let after=try JSONEncoder().encode(current)
      var s: OpaquePointer?
      sqlite3_prepare_v2(db,"UPDATE app_state SET revision=?,payload=? WHERE id=1",-1,&s,nil)
      sqlite3_bind_int64(s,1,Int64(revision));_ = after.withUnsafeBytes {sqlite3_bind_blob(s,2,$0.baseAddress,Int32(after.count),transient)}
      guard sqlite3_step(s)==SQLITE_DONE else {sqlite3_finalize(s);throw HomeEntryError("记录保存失败。")};sqlite3_finalize(s)
      sqlite3_prepare_v2(db,"INSERT INTO change_journal VALUES(?,?,?,?)",-1,&s,nil)
      sqlite3_bind_int64(s,1,Int64(revision));sqlite3_bind_text(s,2,commandID ?? UUID().uuidString,-1,transient);sqlite3_bind_double(s,3,Date().timeIntervalSince1970)
      _ = before.withUnsafeBytes{sqlite3_bind_blob(s,4,$0.baseAddress,Int32(before.count),transient)}
      guard sqlite3_step(s)==SQLITE_DONE else {sqlite3_finalize(s);throw HomeEntryError("无法保存修改历史，记录未提交。")};sqlite3_finalize(s)
      if let commandID {
        sqlite3_prepare_v2(db,"INSERT INTO command_receipts VALUES(?,?,?)",-1,&s,nil)
        sqlite3_bind_text(s,1,commandID,-1,transient);sqlite3_bind_text(s,2,Self.hash(payload),-1,transient);sqlite3_bind_int64(s,3,Int64(revision))
        guard sqlite3_step(s)==SQLITE_DONE else {sqlite3_finalize(s);throw HomeEntryError("无法保存执行回执，记录未提交。")};sqlite3_finalize(s)
      }
      try run(db,"DELETE FROM change_journal WHERE revision < (SELECT MAX(revision)-99 FROM change_journal)")
      try run(db,"COMMIT");return current
    } catch {try? run(db,"ROLLBACK");throw error}
  }
  func undoLatest() throws -> HomeDemoEntries {
    return try updateInTransaction {current,db in
      var s: OpaquePointer?;sqlite3_prepare_v2(db,"SELECT previous_payload FROM change_journal WHERE revision=?",-1,&s,nil);defer{sqlite3_finalize(s)}
      sqlite3_bind_int64(s,1,Int64(current.revision ?? 0))
      guard sqlite3_step(s)==SQLITE_ROW,let bytes=sqlite3_column_blob(s,0) else {throw HomeEntryError("暂无可以撤销的修改。")}
      let snapshot=try JSONDecoder().decode(HomeDemoEntries.self,from:Data(bytes:bytes,count:Int(sqlite3_column_bytes(s,0))))
      current=snapshot
    }
  }
  private static func hash(_ value:String)->String{SHA256.hash(data:Data(value.utf8)).map{String(format:"%02x",$0)}.joined()}
}
