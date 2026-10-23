import AppKit
import Foundation

final class ConnectionRequestTests {
  let key = "unit-test-not-a-key"
  func testEachProviderUsesItsDocumentedProtocol() throws {
    let cases = [
      ("deepseek", "deepseek-flash", "api.deepseek.com", "/chat/completions", "Authorization"),
      ("qwen", "qwen3.8-max", "dashscope.aliyuncs.com", "/compatible-mode/v1/chat/completions", "Authorization"),
      ("doubao", "doubao-seed-evolving", "ark.cn-beijing.volces.com", "/api/v3/chat/completions", "Authorization"),
      ("glm", "glm-5.3", "open.bigmodel.cn", "/api/paas/v4/chat/completions", "Authorization"),
      ("kimi", "kimi-k3", "api.moonshot.cn", "/v1/chat/completions", "Authorization"),
      ("openai", "gpt-6.1-sol", "api.openai.com", "/v1/responses", "Authorization"),
      ("grok", "grok-4.7", "api.x.ai", "/v1/responses", "Authorization"),
      ("anthropic", "claude-sonnet-5-5", "api.anthropic.com", "/v1/messages", "x-api-key"),
      ("gemini", "gemini-4-argon", "generativelanguage.googleapis.com", "/v1beta/models/gemini-4-argon:generateContent", "x-goog-api-key")
    ]
    for (provider, model, host, path, header) in cases {
      let (request, _) = try APIConnectionTester.request(for: .init(providerID: provider, key: key, model: model))
      checkEqual(request.url?.host, host); checkEqual(request.url?.path, path)
      checkEqual(request.httpMethod, "POST")
      checkTrue(request.value(forHTTPHeaderField: header)?.contains(key) == true)
      checkFalse(request.url!.absoluteString.contains(key))
      checkFalse(String(data: request.httpBody!, encoding: .utf8)!.contains(key))
    }
  }
  func testRegionsAndCustomURL() throws {
    for (region, host) in [("singapore", "dashscope-intl.aliyuncs.com"), ("us", "dashscope-us.aliyuncs.com"), ("hongkong", "cn-hongkong.dashscope.aliyuncs.com")] {
      let (req, _) = try APIConnectionTester.request(for: .init(providerID: "qwen", key: key, model: "qwen3.8-flash", region: region))
      checkEqual(req.url?.host, host)
    }
    let (global, _) = try APIConnectionTester.request(for: .init(providerID: "kimi", key: key, model: "kimi-k3", region: "global"))
    checkEqual(global.url?.host, "api.moonshot.ai")
    for endpoint in ["http://fixture.invalid/v1", "https://u:p@fixture.invalid/v1", "https://fixture.invalid/v1?key=secret", "https://fixture.invalid/v1#fragment"] {
      checkThrows(try APIConnectionTester.request(for: .init(providerID: "custom", key: key, model: "my-model", endpoint: endpoint)))
    }
    let (custom, _) = try APIConnectionTester.request(for: .init(providerID: "custom", key: key, model: "org/model", endpoint: "https://fixture.invalid/v1/"))
    checkEqual(custom.url?.path, "/v1/chat/completions")
    checkThrows(try APIConnectionTester.request(for: .init(providerID: "gemini", key: key, model: "../other")))
  }
  func testRedirectIsNeverFollowed() {
    let original = URLRequest(url: URL(string: "https://fixture.invalid/v1/chat/completions")!)
    let task = URLSession.shared.dataTask(with: original)
    defer { task.cancel() }
    let redirect = HTTPURLResponse(url: original.url!, statusCode: 307, httpVersion: nil, headerFields: ["Location": "https://different.invalid/"])!
    var called = false
    NoCredentialRedirect().urlSession(URLSession.shared, task: task, willPerformHTTPRedirection: redirect, newRequest: URLRequest(url: URL(string: "https://different.invalid/")!)) { next in
      called = true; checkNil(next)
    }
    checkTrue(called)
  }
  func testThinkingAndTokenLimitsAreProviderSpecific() throws {
    func body(_ provider: String, _ model: String) throws -> [String: Any] {
      let (r, _) = try APIConnectionTester.request(for: .init(providerID: provider, key: key, model: model))
      return try JSONSerialization.jsonObject(with: r.httpBody!) as! [String: Any]
    }
    checkEqual(try (body("deepseek", "deepseek-flash")["thinking"] as? [String: String])?["type"], "disabled")
    checkEqual(try body("qwen", "qwen3.8-max")["enable_thinking"] as? Bool, false)
    checkEqual(try body("kimi", "kimi-k3")["reasoning_effort"] as? String, "low")
    checkEqual(try (body("glm", "glm-5.3")["thinking"] as? [String: String])?["type"], "enabled")
    checkEqual(try body("openai", "gpt-6-astra")["max_output_tokens"] as? Int, 1024)
    checkEqual(try body("openai", "gpt-6-astra")["store"] as? Bool, false)
    checkNil(try body("anthropic", "claude-sonnet-5-5")["temperature"])
  }
}

final class ConnectionResponseTests {
  private func validate(_ json: String, _ format: APIConnectionTester.ReplyFormat, status: Int = 200) throws {
    try APIConnectionTester.validate(data: Data(json.utf8), status: status, format: format)
  }
  func testSuccessRequiresActualAssistantText() throws {
    try validate(#"{"choices":[{"message":{"role":"assistant","content":"OK"}}]}"#, .chat)
    try validate(#"{"status":"completed","error":null,"output":[{"type":"message","content":[{"type":"output_text","text":"OK"}]}]}"#, .responses)
    try validate(#"{"content":[{"type":"thinking","thinking":"..."},{"type":"text","text":"OK"}]}"#, .claude)
    try validate(#"{"candidates":[{"content":{"parts":[{"text":"OK"}]}}]}"#, .gemini)
    for bad in ["{}", "<html>Login</html>", #"{"choices":[{"message":{"reasoning_content":"Thinking only","content":null}}]}"#, #"{"error":{"message":"secret echoed"}}"#] {
      checkThrows(try validate(bad, .chat))
    }
    checkThrows(try validate(#"{"candidates":[{"content":{"parts":[{"text":"thought only","thought":true}]}}]}"#, .gemini))
    checkThrows(try validate(#"{"status":"failed","output":[]}"#, .responses))
  }
  func testFailureClassificationNeverLeaksRemoteMessage() {
    let cases: [(Int, String, APIConnectionError)] = [
      (401, "", .authentication), (402, "", .balance), (403, "", .permission), (404, "", .modelUnavailable),
      (429, "", .rateLimited), (429, "insufficient_quota", .balance), (500, "", .unavailable), (307, "", .redirect), (400, "", .rejected),
      (400, "API key not valid", .authentication), (400, "余额不足", .balance)
    ]
    for (status, code, expected) in cases {
      let data = try! JSONSerialization.data(withJSONObject: ["error": ["code": code, "message": "remote echoed unit-test-not-a-key"]])
      checkThrows(try APIConnectionTester.validate(data: data, status: status, format: .chat)) { error in
        checkEqual(error as? APIConnectionError, expected)
        checkFalse(error.localizedDescription.contains("unit-test"))
      }
    }
  }
}

private final class StubURLProtocol: URLProtocol {
  static var status = 200
  static var response = Data()
  static var simulatedError: URLError?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    if let error = Self.simulatedError { client?.urlProtocol(self, didFailWithError: error); return }
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.response)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
final class ConnectionTransportTests {
  func testURLSessionUsesParsedResponseAndClassifiesTimeout() async throws {
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
    let tester = APIConnectionTester(session: session)
    let input = APIConnectionConfiguration(providerID: "deepseek", key: "unit-test-not-a-key", model: "deepseek-flash")
    StubURLProtocol.status = 200; StubURLProtocol.response = Data(#"{"choices":[{"message":{"content":"OK"}}]}"#.utf8)
    StubURLProtocol.simulatedError = nil
    try await tester.test(input)
    StubURLProtocol.status = 401
    do { try await tester.test(input); checkFailure("401 was accepted") } catch { checkEqual(error as? APIConnectionError, .authentication) }
    StubURLProtocol.simulatedError = URLError(.timedOut)
    do { try await tester.test(input); checkFailure("Timeout was accepted") } catch { checkEqual(error as? APIConnectionError, .timedOut) }
    StubURLProtocol.simulatedError = nil
  }
}

private actor Recorder {
  var tests = 0
  var saves = 0
  func tested() { tests += 1 }
  func saved() { saves += 1 }
}
private struct FixtureTester: APIConnectionTesting {
  let recorder: Recorder
  var failure: APIConnectionError?
  func test(_ configuration: APIConnectionConfiguration) async throws {
    await recorder.tested()
    try await Task.sleep(for: .milliseconds(100))
    if let failure { throw failure }
  }
}
@MainActor final class ConnectionStateTests {
  func testFailureRetainsFormAndDoesNotSaveOrAdvance() async {
    let suite = "FitnessSetup.Test." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let state = SetupState(defaults: defaults), recorder = Recorder()
    state.page = .api; state.apiKey = "unit-test-not-a-key"
    let ok = await state.testAndSaveAPI(tester: FixtureTester(recorder: recorder, failure: .authentication), saveKey: { _, _ in await recorder.saved() })
    checkFalse(ok); checkEqual(state.page, .api); checkEqual(state.apiKey, "unit-test-not-a-key")
    checkEqual(state.connectionPhase, .failure); checkEqual(state.shakeID, 1)
    let saves = await recorder.saves; checkEqual(saves, 0)
    checkNil(defaults.string(forKey: "setup.provider")); checkFalse(state.keySaved)
  }
  func testSuccessSavesOnlyAfterReplyAndBlocksDuplicateSubmission() async throws {
    let suite = "FitnessSetup.Test." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let state = SetupState(defaults: defaults), recorder = Recorder()
    state.page = .api; state.apiKey = "unit-test-not-a-key"
    let tester = FixtureTester(recorder: recorder)
    let first = Task { await state.testAndSaveAPI(tester: tester, saveKey: { _, _ in await recorder.saved() }) }
    while !state.saving { await Task.yield() }
    let repeated = await state.testAndSaveAPI(tester: tester, saveKey: { _, _ in await recorder.saved() })
    checkFalse(repeated)
    let success = await first.value; checkTrue(success)
    let calls = await recorder.tests, saves = await recorder.saves
    checkEqual(calls, 1); checkEqual(saves, 1)
    checkEqual(state.page, .api); checkEqual(state.connectionPhase, .success)
    checkEqual(state.recordingMode, .ai); checkEqual(defaults.string(forKey: "setup.mode"), "ai")
    checkFalse(String(describing: defaults.persistentDomain(forName: suite)).contains("unit-test-not-a-key"))
    state.useManualMode(); checkEqual(state.recordingMode, .manual)
    checkEqual(defaults.string(forKey: "setup.mode"), "manual"); checkFalse(state.keySaved)
  }
  func testStorageFailureDoesNotClaimSetupSucceeded() async {
    let suite = "FitnessSetup.Test." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let state = SetupState(defaults: defaults), recorder = Recorder(); state.apiKey = "unit-test-not-a-key"
    let ok = await state.testAndSaveAPI(tester: FixtureTester(recorder: recorder), saveKey: { _, _ in throw NSError(domain: "FixtureStorage", code: 1) })
    checkFalse(ok); checkFalse(state.keySaved); checkEqual(state.connectionPhase, .failure)
    checkNil(defaults.string(forKey: "setup.mode")); checkTrue(state.error?.contains("API 已连通") == true)
  }
  func testCancellationCannotPersistAConfiguration() async throws {
    let suite = "FitnessSetup.Test." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let state = SetupState(defaults: defaults), recorder = Recorder(); state.apiKey = "unit-test-not-a-key"
    let work = Task { await state.testAndSaveAPI(tester: FixtureTester(recorder: recorder), saveKey: { _, _ in await recorder.saved() }) }
    while !state.saving { await Task.yield() }
    work.cancel(); state.cancelTest()
    let ok = await work.value; checkFalse(ok)
    let saves = await recorder.saves; checkEqual(saves, 0)
    checkNil(defaults.string(forKey: "setup.provider")); checkEqual(state.connectionPhase, .idle)
  }
  func testOnboardingRunsOnceAndReviewDoesNotResetCompletion() async {
    let suite = "FitnessSetup.Test." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = SetupState(defaults: defaults)
    checkTrue(first.presentsOnboarding)
    first.useManualMode()
    checkTrue(SetupState(defaults: defaults).presentsOnboarding) // Interrupted tutorial resumes setup.
    first.finishTutorial()
    checkFalse(first.presentsOnboarding)
    let relaunch = SetupState(defaults: defaults)
    checkFalse(relaunch.presentsOnboarding)
    checkEqual(relaunch.recordingMode, .manual)
    relaunch.reviewTutorial()
    checkTrue(relaunch.presentsOnboarding); checkEqual(relaunch.page, .preferences)
    checkFalse(SetupState(defaults: defaults).presentsOnboarding)
    relaunch.finishTutorial()
    checkFalse(relaunch.presentsOnboarding)
    let configured = SetupState(defaults: defaults), recorder = Recorder()
    configured.apiKey = "unit-test-not-a-key"
    let success = await configured.testAndSaveAPI(tester: FixtureTester(recorder: recorder), saveKey: { _, _ in await recorder.saved() })
    checkTrue(success)
    let nextLaunch = SetupState(defaults: defaults)
    checkFalse(nextLaunch.presentsOnboarding)
    checkEqual(nextLaunch.recordingMode, .ai)
    checkEqual(nextLaunch.model, configured.model)
    checkEqual(nextLaunch.apiKey, "") // Launch routing does not read a credential or contact its provider.
    nextLaunch.useManualMode()
    checkFalse(SetupState(defaults: defaults).presentsOnboarding)
  }
}

final class LocalStorageTests {
  func testEncryptedPersistenceAndTamperDetection() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FitnessKeys.Test." + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalAPIKeyStore(directory: directory)
    checkNil(try store.read(provider: "deepseek"))
    checkFalse(FileManager.default.fileExists(atPath: directory.path))
    let sample = "synthetic-local-secret-" + UUID().uuidString
    try store.save(sample, provider: "deepseek")
    let ciphertext = directory.appendingPathComponent("credentials.enc")
    let initial = try Data(contentsOf: ciphertext)
    checkNil(initial.range(of: Data(sample.utf8)))
    checkEqual(try LocalAPIKeyStore(directory: directory).read(provider: "deepseek"), sample)
    try store.save("second-synthetic-secret", provider: "qwen")
    try store.save(sample + "-updated", provider: "deepseek")
    checkEqual(try store.read(provider: "qwen"), "second-synthetic-secret")
    checkEqual(try store.read(provider: "deepseek"), sample + "-updated")
    for (url, mode) in [(directory, 0o700), (directory.appendingPathComponent("installation.key"), 0o600), (ciphertext, 0o600)] {
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      checkEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, mode)
    }
    let valid = try Data(contentsOf: ciphertext)
    var tampered = valid; tampered[tampered.count-1] ^= 1
    try tampered.write(to: ciphertext)
    checkThrows(try store.read(provider: "deepseek"))
    checkThrows(try store.save("must-not-overwrite", provider: "deepseek"))
    checkEqual(try Data(contentsOf: ciphertext), tampered)
    try valid.write(to: ciphertext)
    let master = directory.appendingPathComponent("installation.key")
    try FileManager.default.removeItem(at: master)
    checkThrows(try store.read(provider: "deepseek"))
    checkThrows(try store.save("must-not-replace-key", provider: "deepseek"))
    checkFalse(FileManager.default.fileExists(atPath: master.path))
  }
}

private var checkFailures: [String] = []
private var assertions = 0
private func checkFailure(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
  checkFailures.append("\(file):\(line): \(message)")
}
private func checkEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: StaticString = #fileID, line: UInt = #line) {
  assertions += 1
  do { if try lhs() != rhs() { checkFailure("Equality assertion failed", file: file, line: line) } }
  catch { checkFailure("Unexpected throw", file: file, line: line) }
}
private func checkTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #fileID, line: UInt = #line) {
  assertions += 1
  do { if try !value() { checkFailure("Expected true", file: file, line: line) } }
  catch { checkFailure("Unexpected throw", file: file, line: line) }
}
private func checkFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #fileID, line: UInt = #line) {
  do { checkTrue(try !value(), file: file, line: line) }
}
private func checkNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #fileID, line: UInt = #line) {
  do { checkTrue(try value() == nil, file: file, line: line) }
}
private func checkThrows<T>(_ value: @autoclosure () throws -> T, file: StaticString = #fileID, line: UInt = #line, handler: ((Error) -> Void)? = nil) {
  assertions += 1
  do { _ = try value(); checkFailure("Expected failure", file: file, line: line) }
  catch { handler?(error) }
}
@main enum ConnectionCheckRunner {
  @MainActor static func main() async {
    NSApplication.shared.setActivationPolicy(.prohibited)
    do {
      let requests = ConnectionRequestTests()
      try requests.testEachProviderUsesItsDocumentedProtocol()
      try requests.testRegionsAndCustomURL()
      try requests.testThinkingAndTokenLimitsAreProviderSpecific()
      requests.testRedirectIsNeverFollowed()
      let responses = ConnectionResponseTests()
      try responses.testSuccessRequiresActualAssistantText()
      responses.testFailureClassificationNeverLeaksRemoteMessage()
      try await ConnectionTransportTests().testURLSessionUsesParsedResponseAndClassifiesTimeout()
      let state = ConnectionStateTests()
      await state.testFailureRetainsFormAndDoesNotSaveOrAdvance()
      try await state.testSuccessSavesOnlyAfterReplyAndBlocksDuplicateSubmission()
      try await state.testCancellationCannotPersistAConfiguration()
      await state.testStorageFailureDoesNotClaimSetupSucceeded()
      await state.testOnboardingRunsOnceAndReviewDoesNotResetCompletion()
      try LocalStorageTests().testEncryptedPersistenceAndTamperDetection()
    } catch { checkFailure("Uncaught check error: \(error.localizedDescription)") }
    let report: [String: Any] = ["ok": checkFailures.isEmpty, "assertions": assertions, "scenarios": 13, "failures": checkFailures, "realCredentialsUsed": false, "externalNetworkRequests": 0]
    let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    if CommandLine.arguments.count > 1 { try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic) }
    print(String(data: data, encoding: .utf8)!)
    exit(checkFailures.isEmpty ? 0 : 1)
  }
}
