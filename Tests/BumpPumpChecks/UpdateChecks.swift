import Foundation

private final class ReleaseFixtureProtocol: URLProtocol {
  static var status = 200
  static var body = Data()
  static var requests: [URLRequest] = []
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.requests.append(request)
    let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.body); client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
@main struct UpdateChecks {
  static func main() async {
    var assertions = 0, failures: [String] = []
    func check(_ value: Bool, _ message: String) { assertions += 1; if !value { failures.append(message) } }
    check(AppSemanticVersion("0.9.0")! < AppSemanticVersion("v0.10.0")!, "Versions must compare numerically")
    check(AppSemanticVersion("1.0.0-beta")! < AppSemanticVersion("1.0.0")!, "Stable release should supersede beta")
    check(AppSemanticVersion("2.0") == AppSemanticVersion("2.0.0"), "Two-part release version should be comparable")
    check(AppSemanticVersion("release-next") == nil, "Unrecognised version should remain unknown")
    for bad in ["", "owner", "owner/repo/extra", "https://evil.invalid/o/r", "../repo", "owner/repo?key=x", "owner/%2e%2e", "owner/repo#x"] {
      check(AppReleaseChecker.repository(bad) == nil, "Unsafe repository accepted: " + bad)
    }
    check(AppReleaseChecker.repository(" https://github.com/owner/repo.git/ ") == "owner/repo", "Repository URL normalization failed")
    let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ReleaseFixtureProtocol.self]
    let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
    func fixture(tag: String = "v0.7.0", url: String = "https://github.com/owner/repo/releases/tag/v0.7.0", draft: Bool = false, prerelease: Bool = false) -> Data {
      try! JSONSerialization.data(withJSONObject: ["tag_name":tag,"html_url":url,"draft":draft,"prerelease":prerelease])
    }
    do {
      ReleaseFixtureProtocol.body = fixture()
      let newer = try await AppReleaseChecker.check(repository: "owner/repo", currentVersion: "0.6.0", session: session)
      check(newer.newer == true && newer.tag == "v0.7.0", "New release detection failed")
      let request = ReleaseFixtureProtocol.requests.last!
      check(request.url!.absoluteString == "https://api.github.com/repos/owner/repo/releases/latest", "Wrong update endpoint")
      check(request.httpMethod == "GET" && request.httpBody == nil, "Update must only read public release metadata")
      check(request.value(forHTTPHeaderField: "Authorization") == nil, "Update must not send credentials")
      let current = try await AppReleaseChecker.check(repository: "owner/repo", currentVersion: "0.7.0", session: session)
      check(current.newer == false, "Matching release should not offer an update")
      let older = try await AppReleaseChecker.check(repository: "owner/repo", currentVersion: "0.8.0", session: session)
      check(older.newer == false, "A local newer build must not be downgraded")
      ReleaseFixtureProtocol.body = fixture(tag: "next-release")
      let unknown = try await AppReleaseChecker.check(repository: "owner/repo", currentVersion: "0.6.0", session: session)
      check(unknown.newer == nil, "Unknown release tags must not report up-to-date")
      for payload in [fixture(url: "https://evil.invalid/download"), fixture(url: "https://github.com/other/project/releases/tag/v9.0.0"), fixture(draft: true), fixture(prerelease: true), Data("malformed".utf8)] {
        ReleaseFixtureProtocol.body = payload
        do { _ = try await AppReleaseChecker.check(repository: "owner/repo", currentVersion: "0.6.0", session: session); check(false, "Unverified release accepted") }
        catch { check(true, "Unverified release rejected") }
      }
      for status in [403, 404, 429, 500] {
        ReleaseFixtureProtocol.status = status; ReleaseFixtureProtocol.body = fixture()
        do { _ = try await AppReleaseChecker.check(repository: "owner/repo", currentVersion: "0.6.0", session: session); check(false, "HTTP error reported as update success") }
        catch { check(true, "HTTP error handled") }
      }
      let before = ReleaseFixtureProtocol.requests.count
      do { _ = try await AppReleaseChecker.check(repository: "wrong", currentVersion: "0.6.0", session: session); check(false, "Invalid repo accepted") }
      catch { check(ReleaseFixtureProtocol.requests.count == before, "Invalid repo should not trigger a request") }
    } catch { check(false, error.localizedDescription) }
    let report: [String: Any] = ["ok": failures.isEmpty,"assertions":assertions,"failures":failures,"externalRequests":0,"transport":"isolated URLProtocol fixtures"]
    let bytes = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys])
    if CommandLine.arguments.count > 1 { try! bytes.write(to: URL(fileURLWithPath: CommandLine.arguments[1])) }
    print(String(data: bytes, encoding: .utf8)!); exit(failures.isEmpty ? 0 : 1)
  }
}
