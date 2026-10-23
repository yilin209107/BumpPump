import AppKit
import SwiftUI

struct APIModelOption: Identifiable, Equatable {
  let id: String
  let title: String
  let hint: String
}

struct APIProvider: Identifiable, Equatable {
  let id: String
  let name: String
  let initials: String
  let modelOptions: [APIModelOption]
  let docs: String
  var models: [String] { modelOptions.map(\.id) }

  // Verified against each provider's current official model catalogue on 2026-10-22.
  static let all: [Self] = [
    .init(id: "deepseek", name: "DeepSeek", initials: "DS", modelOptions: [
      .init(id: "deepseek-flash", title: "DeepSeek V4.1 Flash", hint: "快速 · 支持图片与工具调用"),
      .init(id: "deepseek-v4-pro", title: "DeepSeek V4 Pro", hint: "旗舰 · 支持工具调用")
    ], docs: "https://api-docs.deepseek.com/quick_start/pricing/"),
    .init(id: "qwen", name: "Qwen · 通义千问", initials: "QW", modelOptions: [
      .init(id: "qwen3.8-max", title: "Qwen3.8 Max", hint: "旗舰 · 支持工具调用"),
      .init(id: "qwen3.8-flash", title: "Qwen3.8 Flash", hint: "快速 · 支持工具调用"),
      .init(id: "qwen3.7-plus", title: "Qwen3.7 Plus", hint: "均衡 · 长上下文与工具调用")
    ], docs: "https://www.alibabacloud.com/help/en/model-studio/text-generation-model"),
    .init(id: "doubao", name: "豆包 · 火山方舟", initials: "DB", modelOptions: [
      .init(id: "doubao-seed-evolving", title: "Seed Evolving", hint: "快速迭代别名 · 自动跟进新版"),
      .init(id: "doubao-seed-2-1-pro-260915", title: "Seed 2.1 Pro", hint: "旗舰 · 图像理解与工具调用"),
      .init(id: "doubao-seed-2-1-lite-260915", title: "Seed 2.1 Lite", hint: "轻量 · 图像理解与工具调用"),
      .init(id: "doubao-seed-2-1-turbo-260628", title: "Seed 2.1 Turbo", hint: "快速 · 图像理解与工具调用")
    ], docs: "https://console.volcengine.com/ark/region:cn-beijing/docs/model-list"),
    .init(id: "glm", name: "GLM · 智谱", initials: "GL", modelOptions: [
      .init(id: "glm-5.3", title: "GLM-5.3", hint: "旗舰推理 · 支持工具调用"),
      .init(id: "glm-5.3-flash", title: "GLM-5.3 Flash", hint: "快速 · 支持图片与工具调用"),
      .init(id: "glm-5.3-flashx", title: "GLM-5.3 FlashX", hint: "高速 · 支持图片与工具调用")
    ], docs: "https://docs.bigmodel.cn/cn/guide/models/text/glm-5.3"),
    .init(id: "kimi", name: "Kimi", initials: "KM", modelOptions: [
      .init(id: "kimi-k3", title: "Kimi K3", hint: "旗舰 · 视觉理解与 Agent"),
      .init(id: "kimi-k2.6", title: "Kimi K2.6", hint: "通用 · 视觉理解与 Agent")
    ], docs: "https://platform.kimi.com/docs/models"),
    .init(id: "gemini", name: "Gemini", initials: "GM", modelOptions: [
      .init(id: "gemini-4-argon", title: "Gemini 4 Argon", hint: "旗舰推理与 Agent"),
      .init(id: "gemini-3.8-flash", title: "Gemini 3.8 Flash", hint: "快速均衡 · 支持图片与工具调用")
    ], docs: "https://ai.google.dev/gemini-api/docs/models"),
    .init(id: "grok", name: "Grok", initials: "GK", modelOptions: [
      .init(id: "grok-4.7", title: "Grok 4.7", hint: "旗舰 · 图像输入与 Agent 工具调用")
    ], docs: "https://docs.x.ai/developers/models"),
    .init(id: "openai", name: "OpenAI", initials: "OA", modelOptions: [
      .init(id: "gpt-6-astra", title: "GPT-6 Astra", hint: "旗舰 · 复杂推理与 Agent"),
      .init(id: "gpt-6.1-sol", title: "GPT-6.1 Sol", hint: "均衡 · 能力与成本"),
      .init(id: "gpt-6-luna", title: "GPT-6 Luna", hint: "高效率 · 适合日常高频使用")
    ], docs: "https://developers.openai.com/api/docs/models"),
    .init(id: "anthropic", name: "Anthropic · Claude", initials: "AN", modelOptions: [
      .init(id: "claude-fable-5-1", title: "Claude Fable 5.1", hint: "深度推理与长程 Agent"),
      .init(id: "claude-opus-5-5", title: "Claude Opus 5.5", hint: "复杂任务与长程工作"),
      .init(id: "claude-sonnet-5-5", title: "Claude Sonnet 5.5", hint: "速度与能力均衡"),
      .init(id: "claude-haiku-5-5", title: "Claude Haiku 5.5", hint: "快速 · 适合轻量任务")
    ], docs: "https://platform.claude.com/docs/en/models/overview"),
    .init(id: "custom", name: "自定义提供商", initials: "+", modelOptions: [], docs: "")
  ]
}
enum SetupPage: Int, CaseIterable {
  case welcome, api, preferences
  var caption: String {
    switch self { case .welcome: return "欢迎"; case .api: return "连接 AI"; case .preferences: return "使用教程" }
  }
}
enum ConnectionPhase { case idle, testing, failure, success }
enum RecordingMode: String { case manual, ai }
struct ProviderDraft {
  var key = ""
  var model = ""
  var customModel = false
  var endpoint = ""
  var region = "china"
}
/// Owns onboarding configuration. Verification sends a fixed greeting, never fitness records.
@MainActor final class SetupState: ObservableObject {
  @Published var page = SetupPage.welcome
  @Published var dark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
  @Published var provider = APIProvider.all[0]
  @Published var apiKey = ""
  @Published var model = APIProvider.all[0].models[0]
  @Published var customModel = false
  @Published var endpoint = ""
  @Published var region = "china"
  @Published var error: String?
  @Published var skippedAPI = false
  @Published var keySaved = false
  @Published var saving = false
  @Published var connectionPhase = ConnectionPhase.idle
  @Published var shakeID = 0
  @Published var recordingMode = RecordingMode.manual
  @Published var tutorialCompleted = false
  @Published private(set) var onboardingCompleted: Bool
  @Published var reviewingTutorial = false
  private var drafts: [String: ProviderDraft] = [:]
  private let defaults: UserDefaults
  private var activeRequest: UUID?
  init(defaults: UserDefaults = .standard, page: SetupPage = .welcome) {
    self.defaults = defaults
    onboardingCompleted = defaults.bool(forKey: "setup.completed")
    self.page = page
    restoreSelection()
  }
  var presentsOnboarding: Bool { !onboardingCompleted || reviewingTutorial }
  var palette: SetupPalette { SetupPalette(dark: dark) }
  func selectProvider(_ next: APIProvider) {
    drafts[provider.id] = ProviderDraft(key: apiKey, model: model, customModel: customModel, endpoint: endpoint, region: region)
    provider = next
    keySaved = false
    let draft = drafts[next.id] ?? ProviderDraft(model: next.models.first ?? "", customModel: next.models.isEmpty)
    apiKey = draft.key; model = draft.model; customModel = draft.customModel; endpoint = draft.endpoint; region = draft.region; error = nil
  }
  func validateAPI() -> Bool {
    error = nil
    guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "请填写 API Key，或选择“先用手动记录”。"; return false }
    guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "请填写模型 ID。"; return false }
    if provider.id == "custom" {
      guard let url = URL(string: endpoint), url.scheme == "https", url.host?.isEmpty == false, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
        error = "请填写有效的 HTTPS API 地址。"; return false
      }
    }
    skippedAPI = false
    return true
  }
  func testAndSaveAPI(tester: any APIConnectionTesting = APIConnectionTester(),
    saveKey: @Sendable (String, String) async throws -> Void = { key, account in
      try await Task.detached(priority: .userInitiated) { try LocalAPIKeyStore.shared.save(key, provider: account) }.value
    }) async -> Bool {
    guard !saving else { return false }
    guard validateAPI() else { connectionPhase = .failure; shakeID += 1; return false }
    let requestID = UUID(); activeRequest = requestID
    saving = true; connectionPhase = .testing; keySaved = false
    defer { if activeRequest == requestID { saving = false; activeRequest = nil } }
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let account = provider.id
    let configuration = APIConnectionConfiguration(providerID: account, key: key, model: model.trimmingCharacters(in: .whitespacesAndNewlines), endpoint: endpoint, region: region)
    var modelResponded = false
    do {
      try await tester.test(configuration)
      modelResponded = true
      try Task.checkCancellation()
      guard activeRequest == requestID else { throw CancellationError() }
      try await saveKey(key, account)
      try Task.checkCancellation()
      guard activeRequest == requestID else { throw CancellationError() }
      // Explicit allowlist: never serialize credentials into preferences.
      defaults.set(account, forKey: "setup.provider")
      defaults.set(configuration.model, forKey: "setup.model")
      defaults.set(customModel, forKey: "setup.customModel")
      defaults.set(endpoint, forKey: "setup.endpoint")
      defaults.set(region, forKey: "setup.region")
      defaults.set(RecordingMode.ai.rawValue, forKey: "setup.mode")
      keySaved = true; skippedAPI = false; recordingMode = .ai; tutorialCompleted = false; connectionPhase = .success
      return true
    } catch is CancellationError {
      if activeRequest == requestID { connectionPhase = .idle; error = nil }
      return false
    } catch {
      guard activeRequest == requestID else { return false }
      self.error = (error as? APIConnectionError)?.localizedDescription ?? (modelResponded
        ? "API 已连通，但密钥未能保存到本机。请检查 App 数据目录的访问权限后重试。"
        : "API 测试未完成，请检查连接配置后重试。")
      connectionPhase = .failure; shakeID += 1
      return false
    }
  }
  func cancelTest() {
    activeRequest = nil; saving = false; connectionPhase = .idle; error = nil
  }
  func useManualMode() {
    cancelTest(); skippedAPI = true; keySaved = false; recordingMode = .manual; tutorialCompleted = false
    defaults.set(RecordingMode.manual.rawValue, forKey: "setup.mode")
  }
  func finishTutorial() {
    tutorialCompleted = true
    defaults.set(true, forKey: "setup.completed")
    onboardingCompleted = true
    reviewingTutorial = false
  }
  func reviewTutorial() { tutorialCompleted = false; reviewingTutorial = true; page = .preferences }
  func restoreSelection() {
    recordingMode = RecordingMode(rawValue: defaults.string(forKey: "setup.mode") ?? "manual") ?? .manual
    guard let id = defaults.string(forKey: "setup.provider"), let selected = APIProvider.all.first(where: { $0.id == id }) else { return }
    provider = selected
    let savedModel = defaults.string(forKey: "setup.model") ?? ""
    customModel = defaults.bool(forKey: "setup.customModel")
    model = customModel || selected.models.contains(savedModel) ? savedModel : (selected.models.first ?? "")
    endpoint = defaults.string(forKey: "setup.endpoint") ?? ""
    region = defaults.string(forKey: "setup.region") ?? "china"
  }
  func loadKeyIfNeeded() async {
    guard apiKey.isEmpty else { return }
    let account = provider.id
    do {
      let value = try await Task.detached { try LocalAPIKeyStore.shared.read(provider: account) }.value
      if provider.id == account && apiKey.isEmpty { apiKey = value ?? "" }
    } catch { self.error = "本机保存的密钥暂时无法读取，请重新填写 API Key。" }
  }
  func restart() { cancelTest(); reviewingTutorial = true; tutorialCompleted = false; page = .welcome }
}
