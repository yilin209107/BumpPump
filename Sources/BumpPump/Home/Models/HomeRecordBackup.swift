import Foundation

enum HomeRecordBackup {
  /// The export format contains local records only, never credentials or generated examples.
  static func encode(_ entries: HomeDemoEntries) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(entries)
  }
}
