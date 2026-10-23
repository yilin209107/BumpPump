import Foundation

struct AgentAttachment: Codable, Identifiable, Equatable {
  var id = UUID().uuidString
  var name: String
  var mime: String
  var text: String? = nil
  var image: Data? = nil
  var isImage: Bool { image != nil }
}
struct AgentToolCall: Codable, Equatable {
  var id: String
  var name: String
  var arguments: String
}
struct AgentMessage: Codable, Identifiable {
  var id = UUID().uuidString
  var role: String
  var text: String
  var date = Date()
  var attachments: [AgentAttachment] = []
  var calls: [AgentToolCall] = []
  var callID: String? = nil
  var toolName: String? = nil
  var interrupted = false
  // Provider-native assistant payload preserves tool signatures and reasoning items.
  var native: Data? = nil
  var nativeProvider: String? = nil
}
struct AgentTurn {
  var text = ""
  var calls: [AgentToolCall] = []
  var native: Data? = nil
}
struct AgentFailure: LocalizedError {
  var message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}
struct AgentToolDefinition {
  let name: String
  let description: String
  let parameters: [String: Any]
}
protocol AgentTransport {
  func stream(configuration: APIConnectionConfiguration, system: String, messages: [AgentMessage], tools: [AgentToolDefinition], delta: @escaping @MainActor (String) -> Void) async throws -> AgentTurn
}
extension JSONSerialization {
  static func agentString(_ value: Any) throws -> String { String(decoding: try data(withJSONObject: value, options: [.sortedKeys,.fragmentsAllowed]),as: UTF8.self) }
}
