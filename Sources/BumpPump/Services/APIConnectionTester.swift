import Foundation

struct APIConnectionConfiguration: Sendable {
  let providerID: String
  let key: String
  let model: String
  var endpoint = ""
  var region = "china"
}

protocol APIConnectionTesting: Sendable {
  func test(_ configuration: APIConnectionConfiguration) async throws
}

enum APIConnectionError: LocalizedError, Equatable {
  case invalidAddress, invalidModel, invalidReply, authentication, permission, balance, modelUnavailable, rateLimited, rejected, unavailable, network, timedOut, redirect
  var errorDescription: String? {
    switch self {
    case .invalidAddress: return "请检查 API 地址，使用不含密钥或查询参数的 HTTPS Base URL。"
    case .invalidModel: return "请检查模型 ID，不能包含空格或网址。"
    case .invalidReply: return "服务已响应，但模型没有返回有效文本。请检查型号和接口配置，再重试。"
    case .authentication: return "API Key 验证失败。请重新复制完整密钥，并确认服务商和地区匹配。"
    case .permission: return "此账号暂时没有调用权限。请在服务商平台检查地区、账号状态和模型开通情况。"
    case .balance: return "余额或可用额度不足。请在服务商的开发者平台检查余额、充值或账单额度。"
    case .modelUnavailable: return "找不到所选模型，或此 Key 没有使用权限。请选择其他型号，或核对模型 ID。"
    case .rateLimited: return "服务商暂时限制了请求次数或额度。请检查配额，稍后手动重试。"
    case .rejected: return "服务商没有接受这次测试。请核对模型与 API 地址；套餐专用密钥可能需要不同的连接地址。"
    case .unavailable: return "服务商暂时不可用。请稍后重试，也可以先使用手动记录。"
    case .network: return "暂时无法连接。请检查网络、代理设置，以及该服务在你所在地区是否可用。"
    case .timedOut: return "测试等待超时。请求可能已到达服务商；请检查网络或稍后手动重试。"
    case .redirect: return "API 地址发生了跳转。为保护密钥，本次没有跟随跳转，请核对连接地址。"
    }
  }
}

/// One explicit, bounded generation request. No health data, retries, cookies, or response logging.
struct APIConnectionTester: APIConnectionTesting {
  enum ReplyFormat { case chat, responses, claude, gemini }
  private let session: URLSession
  init(session: URLSession? = nil) { self.session = session ?? Self.liveSession }
  private static let liveSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.urlCache = nil; config.httpShouldSetCookies = false
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.timeoutIntervalForRequest = 90; config.timeoutIntervalForResource = 120
    return URLSession(configuration: config, delegate: NoCredentialRedirect(), delegateQueue: nil)
  }()

  func test(_ configuration: APIConnectionConfiguration) async throws {
    let (request, format) = try Self.request(for: configuration)
    do {
      let (data, response) = try await session.data(for: request)
      try Task.checkCancellation()
      guard let response = response as? HTTPURLResponse else { throw APIConnectionError.invalidReply }
      try Self.validate(data: data, status: response.statusCode, format: format)
    } catch let error as URLError {
      if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
      throw error.code == .timedOut ? APIConnectionError.timedOut : APIConnectionError.network
    }
  }

  static func request(for c: APIConnectionConfiguration) throws -> (URLRequest, ReplyFormat) {
    let prompt = "This is a connection test. Reply with only OK."
    let model = c.model.trimmingCharacters(in: .whitespacesAndNewlines)
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:/")
    guard !model.isEmpty, model.unicodeScalars.allSatisfy({ allowed.contains($0) }), !model.contains("://"), !model.contains("..") else { throw APIConnectionError.invalidModel }
    var url: URL
    var format = ReplyFormat.chat
    var body: [String: Any] = ["model": model, "messages": [["role": "user", "content": prompt]], "max_tokens": 1024, "stream": false]
    switch c.providerID {
    case "deepseek":
      url = URL(string: "https://api.deepseek.com/chat/completions")!
      if ["deepseek-flash", "deepseek-v4-pro"].contains(model) { body["thinking"] = ["type": "disabled"] }
    case "qwen":
      let host: String
      switch c.region {
      case "singapore": host = "dashscope-intl.aliyuncs.com"
      case "us": host = "dashscope-us.aliyuncs.com"
      case "hongkong": host = "cn-hongkong.dashscope.aliyuncs.com"
      default: host = "dashscope.aliyuncs.com"
      }
      url = URL(string: "https://\(host)/compatible-mode/v1/chat/completions")!
      if model.hasPrefix("qwen3.8") || model.hasPrefix("qwen3.7") { body["enable_thinking"] = false }
    case "doubao":
      url = URL(string: "https://ark.cn-beijing.volces.com/api/v3/chat/completions")!
      if model.hasPrefix("doubao-seed") { body["thinking"] = ["type": "disabled"] }
    case "glm":
      url = URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!
      if model.hasPrefix("glm-5.3") { body["thinking"] = ["type": "enabled"]; body["reasoning_effort"] = "low" }
    case "kimi":
      url = URL(string: c.region == "global" ? "https://api.moonshot.ai/v1/chat/completions" : "https://api.moonshot.cn/v1/chat/completions")!
      if model == "kimi-k3" { body["reasoning_effort"] = "low" }
      if model == "kimi-k2.6" { body["thinking"] = ["type": "disabled"] }
    case "openai", "grok":
      format = .responses
      url = URL(string: c.providerID == "openai" ? "https://api.openai.com/v1/responses" : "https://api.x.ai/v1/responses")!
      body = ["model": model, "input": prompt, "max_output_tokens": 1024, "store": false, "stream": false]
      if (c.providerID == "openai" && model.hasPrefix("gpt-6")) || (c.providerID == "grok" && model.hasPrefix("grok-4")) { body["reasoning"] = ["effort": "low"] }
    case "anthropic":
      format = .claude
      url = URL(string: "https://api.anthropic.com/v1/messages")!
      if model.hasPrefix("claude-") && (model.contains("-5-5") || model == "claude-fable-5-1") { body["output_config"] = ["effort": "low"] }
    case "gemini":
      format = .gemini
      // Model ID is a single path segment, not a user-provided URL.
      guard !model.contains("/"), !model.contains(":") else { throw APIConnectionError.invalidModel }
      url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
      var generation: [String: Any] = ["maxOutputTokens": 1024]
      if model.hasPrefix("gemini-4") || model.hasPrefix("gemini-3.8") { generation["thinkingConfig"] = ["thinkingLevel": "LOW"] }
      body = ["contents": [["role": "user", "parts": [["text": prompt]]]], "generationConfig": generation]
    case "custom":
      guard let base = URL(string: c.endpoint), validBase(base) else { throw APIConnectionError.invalidAddress }
      url = base.appendingPathComponent("chat/completions")
    default: throw APIConnectionError.invalidAddress
    }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let key = c.key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty, !key.contains("\n"), !key.contains("\r") else { throw APIConnectionError.authentication }
    switch format {
    case .claude:
      request.setValue(key, forHTTPHeaderField: "x-api-key")
      request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    case .gemini: request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
    default: request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    return (request, format)
  }

  static func validBase(_ url: URL) -> Bool {
    url.scheme == "https" && url.host?.isEmpty == false && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
  }

  static func validate(data: Data, status: Int, format: ReplyFormat) throws {
    guard data.count <= 1_048_576 else { throw APIConnectionError.invalidReply }
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    let error = json?["error"] as? [String: Any]
    // Inspect only for classification. Never show/log a remote message, which may echo credentials.
    let code = [error?["code"] as? String, error?["type"] as? String, error?["message"] as? String, json?["code"] as? String].compactMap { $0 }.joined(separator: " ").lowercased()
    if status == 402 || code.contains("insufficient") || code.contains("balance") || code.contains("arrear") || code.contains("余额不足") || code.contains("额度不足") || code.contains("1113") { throw APIConnectionError.balance }
    if code.contains("api key not valid") || code.contains("invalid_api_key") || code.contains("api_key_invalid") { throw APIConnectionError.authentication }
    switch status {
    case 200..<300: break
    case 300..<400: throw APIConnectionError.redirect
    case 401: throw APIConnectionError.authentication
    case 403: throw APIConnectionError.permission
    case 404: throw APIConnectionError.modelUnavailable
    case 429: throw APIConnectionError.rateLimited
    case 500...599: throw APIConnectionError.unavailable
    default: throw APIConnectionError.rejected
    }
    guard let json, error == nil, json["error"] == nil || json["error"] is NSNull else { throw APIConnectionError.invalidReply }
    var texts: [String] = []
    switch format {
    case .chat:
      let message = ((json["choices"] as? [[String: Any]])?.first?["message"]) as? [String: Any]
      if let text = message?["content"] as? String { texts = [text] }
      else if let blocks = message?["content"] as? [[String: Any]] { texts = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil } }
    case .responses:
      guard json["status"] as? String != "failed", json["status"] as? String != "cancelled" else { throw APIConnectionError.invalidReply }
      let outputs = json["output"] as? [[String: Any]] ?? []
      for output in outputs where output["type"] as? String == "message" {
        for block in output["content"] as? [[String: Any]] ?? [] where block["type"] as? String == "output_text" { if let t = block["text"] as? String { texts.append(t) } }
      }
    case .claude:
      texts = (json["content"] as? [[String: Any]] ?? []).compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
    case .gemini:
      let candidates = json["candidates"] as? [[String: Any]] ?? []
      for candidate in candidates {
        let content = candidate["content"] as? [String: Any]
        for block in content?["parts"] as? [[String: Any]] ?? [] where block["thought"] as? Bool != true { if let t = block["text"] as? String { texts.append(t) } }
      }
    }
    guard texts.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw APIConnectionError.invalidReply }
  }
}

final class NoCredentialRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
