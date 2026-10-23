import Foundation

struct AppSemanticVersion: Comparable, Equatable {
  let parts: [Int]
  let prerelease: Bool
  init?(_ text: String) {
    var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.hasPrefix("v") || raw.hasPrefix("V") { raw.removeFirst() }
    let core = raw.split(separator: "+", maxSplits: 1).first.map(String.init) ?? ""
    let pieces = core.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    let values = (pieces.first.map(String.init) ?? "").split(separator: ".", omittingEmptySubsequences: false)
    guard (2...3).contains(values.count), values.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) && Int($0) != nil }) else { return nil }
    parts = values.compactMap { Int($0) } + Array(repeating: 0, count: 3-values.count)
    prerelease = pieces.count > 1
  }
  static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.parts != rhs.parts { return lhs.parts.lexicographicallyPrecedes(rhs.parts) }
    return lhs.prerelease && !rhs.prerelease
  }
}
struct AppReleaseInfo: Sendable {
  let tag: String
  let url: URL
  let newer: Bool?
}
struct AppUpdateError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}
enum AppReleaseChecker {
  static func repository(_ text: String) -> String? {
    var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.hasPrefix("https://github.com/") { raw = String(raw.dropFirst("https://github.com/".count)) }
    while raw.hasSuffix("/") { raw.removeLast() }
    if raw.hasSuffix(".git") { raw = String(raw.dropLast(4)) }
    let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.count <= 100 && $0 != "." && $0 != ".." && $0.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }) }) else { return nil }
    return raw
  }
  static func check(repository input: String, currentVersion: String, session injected: URLSession? = nil) async throws -> AppReleaseInfo {
    guard let repository = repository(input), let endpoint = URL(string: "https://api.github.com/repos/" + repository + "/releases/latest") else { throw AppUpdateError(message: "请填写项目的 GitHub 仓库，例如 owner/repository。") }
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil; config.urlCache = nil; config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
    let session = injected ?? URLSession(configuration: config)
    defer { if injected == nil { session.finishTasksAndInvalidate() } }
    var request = URLRequest(url: endpoint); request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
    request.setValue("FitnessTracker-VersionCheck", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await session.data(for: request)
    try Task.checkCancellation()
    guard let http = response as? HTTPURLResponse else { throw AppUpdateError(message: "未收到有效的更新响应，请稍后重试。") }
    if http.statusCode == 404 { throw AppUpdateError(message: "没有找到公开的正式发行版，请检查仓库地址及 Releases。") }
    if http.statusCode == 403 || http.statusCode == 429 { throw AppUpdateError(message: "GitHub 暂时限制了检查请求，请稍后再试。") }
    guard http.statusCode == 200, data.count < 1_000_000 else { throw AppUpdateError(message: "检查更新失败，请稍后重试。") }
    struct Release: Decodable { let tag_name: String; let html_url: String; let draft: Bool; let prerelease: Bool }
    guard let release = try? JSONDecoder().decode(Release.self, from: data), !release.draft, !release.prerelease,
      let url = URL(string: release.html_url), let components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.scheme == "https", components.host == "github.com", components.user == nil, components.password == nil, components.port == nil,
      components.path.lowercased().hasPrefix("/" + repository.lowercased() + "/releases/"), !release.tag_name.isEmpty else { throw AppUpdateError(message: "发行信息无法核实，请检查项目仓库地址。") }
    let current = AppSemanticVersion(currentVersion), latest = AppSemanticVersion(release.tag_name)
    return .init(tag: release.tag_name, url: url, newer: current.flatMap { old in latest.map { old < $0 } })
  }
}
