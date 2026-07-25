import Darwin
import Foundation
import XCTest
@testable import Dashis

private final class SyntheticProviderURLProtocol: URLProtocol {
  typealias Response = (status: Int, headers: [String: String], body: Data)
  private static let lock = NSLock()
  private static var responder: ((URLRequest) -> Response)?

  static func install(_ responder: @escaping (URLRequest) -> Response) {
    lock.lock()
    self.responder = responder
    lock.unlock()
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    let responder = Self.responder
    Self.lock.unlock()
    guard let responder, let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    let result = responder(request)
    guard let response = HTTPURLResponse(
      url: url,
      statusCode: result.status,
      httpVersion: "HTTP/1.1",
      headerFields: result.headers
    ) else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: result.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private func syntheticRequestBody(_ request: URLRequest) -> Data? {
  if let body = request.httpBody { return body }
  guard let stream = request.httpBodyStream else { return nil }
  stream.open()
  defer { stream.close() }
  var data = Data()
  var buffer = [UInt8](repeating: 0, count: 4_096)
  while true {
    let count = stream.read(&buffer, maxLength: buffer.count)
    if count > 0 {
      data.append(buffer, count: count)
    } else if count == 0 {
      return data
    } else {
      return nil
    }
  }
}

final class SecurityBoundaryTests: XCTestCase {
  func testProviderJSONDistinguishesBooleanAndNumericNSNumberBridges() {
    XCTAssertEqual(ProviderJSON.bool(true), true)
    XCTAssertEqual(ProviderJSON.bool(false), false)
    XCTAssertEqual(ProviderJSON.bool(NSNumber(value: true)), true)
    XCTAssertNil(ProviderJSON.bool(NSNumber(value: 1)))
    XCTAssertNil(ProviderJSON.number(NSNumber(value: true)))
    XCTAssertEqual(ProviderJSON.number(NSNumber(value: 12.5)), 12.5)
    XCTAssertEqual(ProviderJSON.int(NSNumber(value: 12)), 12)
  }

  func testProviderJSONIntegerConversionFailsClosedForFractionalAndHugeValues() {
    XCTAssertNil(ProviderJSON.int(NSNumber(value: 1.25)))
    XCTAssertNil(ProviderJSON.int("1.25"))
    XCTAssertNil(ProviderJSON.int(NSNumber(value: Double.greatestFiniteMagnitude)))
  }

  func testEndpointPolicyRejectsTransportPortAndTrailingSlashVariants() throws {
    for rawURL in [
      "http://openrouter.ai/api/v1/key",
      "https://openrouter.ai:444/api/v1/key",
      "https://openrouter.ai/api/v1/key/"
    ] {
      var request = URLRequest(url: try XCTUnwrap(URL(string: rawURL)))
      request.httpMethod = "GET"
      XCTAssertFalse(ProviderEndpointPolicy.allows(request), rawURL)
    }
  }

  func testEndpointPolicyRejectsDotSegmentsAndEncodedDotSegments() throws {
    for rawURL in [
      "https://openrouter.ai/api/v1/./key",
      "https://openrouter.ai/api/v1/generation?id=..",
      "https://openrouter.ai/api/v1/generation?id=%2e%2e",
      "https://api.chatgpt.com/v1/analytics/codex/workspaces/../usage?start_time=1&end_time=2&group_by=day&group=workspace&limit=1",
      "https://api.chatgpt.com/v1/analytics/codex/workspaces/%2e%2e/usage?start_time=1&end_time=2&group_by=day&group=workspace&limit=1"
    ] {
      var request = URLRequest(url: try XCTUnwrap(URL(string: rawURL)))
      request.httpMethod = "GET"
      XCTAssertFalse(ProviderEndpointPolicy.allows(request), rawURL)
    }
  }

  func testEndpointPolicyRejectsDuplicateQueryNames() throws {
    var request = URLRequest(url: try XCTUnwrap(URL(string:
      "https://openrouter.ai/api/v1/generation?id=synthetic-one&id=synthetic-two"
    )))
    request.httpMethod = "GET"
    XCTAssertFalse(ProviderEndpointPolicy.allows(request))
  }

  func testEmptySnapshotFreshnessIsNoDataEvenWhenRecentlyObserved() {
    let snapshot = ProviderSnapshot(
      providerID: .google,
      scope: ProviderScope(kind: .manual, label: "Synthetic manual scope"),
      sourceKind: .manualOnly,
      observedAt: Date(),
      windows: [],
      balance: nil,
      metrics: [],
      warnings: [ProviderWarning(id: "synthetic", message: "No synthetic value was supplied.")],
      partialFailures: []
    )

    let freshness = FreshnessPolicy.freshness(of: snapshot, now: snapshot.observedAt)
    XCTAssertEqual(freshness, .missing)
    XCTAssertEqual(freshness.label, "No data")
  }

  func testClaudeNullResetRetainsOtherwiseValidWindow() throws {
    let input = Data(#"{"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":null}}}"#.utf8)
    guard case .update(let update) = ClaudeStatusLineCodec.parse(input) else {
      return XCTFail("Expected a sanitized rate-limit update")
    }

    let fiveHour = try XCTUnwrap(update.fiveHour)
    XCTAssertEqual(fiveHour.usedPercentage, 42)
    XCTAssertNil(fiveHour.resetsAt)
  }

  func testClaudeSnapshotRejectsSymlinkAndUnsafePermissions() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let snapshot = syntheticClaudeSnapshot()
    let target = directory.appendingPathComponent("target.json")
    try ClaudeSnapshotFile.write(snapshot, to: target)

    let symlink = directory.appendingPathComponent("snapshot-link.json")
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
    assertSnapshotReadError(.unsafeFile, from: symlink)

    let permissive = directory.appendingPathComponent("permissive.json")
    try ClaudeSnapshotFile.write(snapshot, to: permissive)
    XCTAssertEqual(chmod(permissive.path, mode_t(0o644)), 0)
    assertSnapshotReadError(.unsafeFile, from: permissive)
  }

  func testClaudeSnapshotRejectsOversizedFileBeforeDecoding() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let oversized = directory.appendingPathComponent("oversized.json")
    try Data(repeating: 0x20, count: ClaudeSnapshotFile.maximumBytes + 1).write(to: oversized)
    XCTAssertEqual(chmod(oversized.path, mode_t(0o600)), 0)
    assertSnapshotReadError(.tooLarge, from: oversized)
  }

  func testCodexAuthorizationFileRequiresPrivateRegularBoundedFile() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let secure = directory.appendingPathComponent("auth.json")
    let payload = Data(#"{"synthetic":true}"#.utf8)
    try payload.write(to: secure)
    XCTAssertEqual(chmod(secure.path, mode_t(0o600)), 0)
    XCTAssertEqual(
      try CodexUsageClient.readOwnedRegularFile(at: secure, maximumBytes: 1024),
      payload
    )

    XCTAssertEqual(chmod(secure.path, mode_t(0o644)), 0)
    XCTAssertThrowsError(
      try CodexUsageClient.readOwnedRegularFile(at: secure, maximumBytes: 1024)
    )

    let symlink = directory.appendingPathComponent("auth-link.json")
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: secure)
    XCTAssertThrowsError(
      try CodexUsageClient.readOwnedRegularFile(at: symlink, maximumBytes: 1024)
    )

    let oversized = directory.appendingPathComponent("oversized-auth.json")
    try Data(repeating: 0x20, count: 1025).write(to: oversized)
    XCTAssertEqual(chmod(oversized.path, mode_t(0o600)), 0)
    XCTAssertThrowsError(
      try CodexUsageClient.readOwnedRegularFile(at: oversized, maximumBytes: 1024)
    )
  }

  func testHTTPClientRetriesIdempotentGETButNotOAuthPOST() async throws {
    let lock = NSLock()
    var getCount = 0
    var postCount = 0
    SyntheticProviderURLProtocol.install { request in
      lock.lock()
      defer { lock.unlock() }
      if request.httpMethod == "GET" {
        getCount += 1
        return getCount == 1
          ? (503, [:], Data())
          : (200, ["Content-Type": "application/json"], Data(#"{"data":{"usage":1}}"#.utf8))
      }
      postCount += 1
      return (503, [:], Data())
    }
    let client = ProviderHTTPClient(configuration: syntheticSessionConfiguration(), maximumRetries: 1)

    var get = URLRequest(url: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/key")))
    get.httpMethod = "GET"
    _ = try await client.json(for: get, operation: "synthetic.get")
    XCTAssertEqual(getCount, 2)

    var post = URLRequest(url: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/auth/keys")))
    post.httpMethod = "POST"
    post.setValue("application/json", forHTTPHeaderField: "Content-Type")
    post.httpBody = try JSONSerialization.data(withJSONObject: [
      "code": "synthetic-code",
      "code_verifier": String(repeating: "a", count: 43),
      "code_challenge_method": "S256"
    ])
    do {
      _ = try await client.data(for: post, operation: "synthetic.post")
      XCTFail("Expected a non-retried HTTP failure")
    } catch {
      XCTAssertEqual(error as? ProviderHTTPError, .httpStatus(503))
    }
    XCTAssertEqual(postCount, 1)
  }

  func testHTTPClientEnforcesStreamingResponseCap() async throws {
    SyntheticProviderURLProtocol.install { _ in
      (200, ["Content-Length": "2048"], Data(repeating: 0x61, count: 2048))
    }
    let client = ProviderHTTPClient(
      configuration: syntheticSessionConfiguration(),
      maximumRetries: 0,
      maximumResponseBytes: 1024
    )
    var request = URLRequest(url: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/key")))
    request.httpMethod = "GET"
    do {
      _ = try await client.data(for: request, operation: "synthetic.large")
      XCTFail("Expected the response-size guard to fail")
    } catch {
      XCTAssertEqual(error as? ProviderHTTPError, .responseTooLarge)
    }
  }

  func testOpenRouterManagementKeepsSuccessfulCreditsWhenOtherSubchecksFail() async {
    SyntheticProviderURLProtocol.install { request in
      switch request.url?.path {
      case "/api/v1/credits":
        return (200, ["Content-Type": "application/json"], Data(#"{"data":{"total_credits":10,"total_usage":3}}"#.utf8))
      default:
        return (500, [:], Data())
      }
    }
    let client = ProviderHTTPClient(configuration: syntheticSessionConfiguration(), maximumRetries: 0)
    let snapshot = await OpenRouterUsageClient(
      httpClient: client,
      now: { Date(timeIntervalSince1970: 1_800_000_000) }
    ).fetchManagementSnapshot(context: .init(apiKey: "sk-or-synthetic"))

    XCTAssertEqual(snapshot.balance?.remaining, 7)
    XCTAssertTrue(snapshot.hasData)
    XCTAssertTrue(snapshot.partialFailures.contains { $0.operation == "openrouter.activity" })
    XCTAssertTrue(snapshot.partialFailures.contains { $0.operation == "openrouter.analytics.meta" })
  }

  func testOpenRouterAccountSnapshotUsesUnfilteredAccountQueries() async throws {
    SyntheticProviderURLProtocol.install { request in
      switch request.url?.path {
      case "/api/v1/credits":
        return (200, ["Content-Type": "application/json"], Data(#"{"data":{"total_credits":20,"total_usage":4}}"#.utf8))
      case "/api/v1/activity":
        XCTAssertNil(request.url?.query)
        return (200, ["Content-Type": "application/json"], Data(#"{"data":[]}"#.utf8))
      case "/api/v1/analytics/meta":
        let body = #"{"data":{"metrics":[{"name":"request_count","is_rate":false}],"dimensions":[{"name":"model"}],"granularities":[{"name":"day"}]}}"#
        return (200, ["Content-Type": "application/json"], Data(body.utf8))
      case "/api/v1/analytics/query":
        let body = syntheticRequestBody(request)
          .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        XCTAssertNil(body?["filters"])
        let response = #"{"data":{"data":[],"metadata":{"row_count":0,"truncated":false}}}"#
        return (200, ["Content-Type": "application/json"], Data(response.utf8))
      default:
        return (404, [:], Data())
      }
    }
    let client = ProviderHTTPClient(configuration: syntheticSessionConfiguration(), maximumRetries: 0)
    let snapshot = await OpenRouterUsageClient(
      httpClient: client,
      now: { Date(timeIntervalSince1970: 1_800_000_000) }
    ).fetchManagementSnapshot(context: .init(apiKey: "sk-or-synthetic"))

    XCTAssertEqual(snapshot.scope, .workspace("OpenRouter account"))
    XCTAssertEqual(snapshot.balance?.remaining, 16)
    XCTAssertTrue(snapshot.partialFailures.isEmpty)
  }

  func testOpenRouterRecentCallsUsesAccountWideMetadataQuery() async throws {
    SyntheticProviderURLProtocol.install { request in
      switch request.url?.path {
      case "/api/v1/analytics/meta":
        let body = #"{"data":{"metrics":[{"name":"total_usage","is_rate":false},{"name":"tokens_total","is_rate":false},{"name":"requests_per_second","is_rate":true}],"dimensions":[{"name":"generation_id"},{"name":"api_key_id"},{"name":"model"}],"granularities":[{"name":"hour"}]}}"#
        return (200, ["Content-Type": "application/json"], Data(body.utf8))
      case "/api/v1/analytics/query":
        let body = syntheticRequestBody(request)
          .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        XCTAssertEqual(body?["dimensions"] as? [String], ["generation_id", "api_key_id"])
        XCTAssertEqual(body?["metrics"] as? [String], ["total_usage", "tokens_total"])
        XCTAssertEqual(body?["granularity"] as? String, "hour")
        XCTAssertEqual(ProviderJSON.int(body?["group_limit"]), 1)
        XCTAssertEqual(ProviderJSON.int(body?["limit"]), 20)
        XCTAssertNil(body?["filters"])
        XCTAssertNil(body?["order_by"])
        let timeRange = body?["time_range"] as? [String: Any]
        let start = ProviderJSON.date(timeRange?["start"])
        let end = ProviderJSON.date(timeRange?["end"])
        if let start, let end {
          XCTAssertEqual(end.timeIntervalSince(start), 86_400, accuracy: 0.001)
        } else {
          XCTFail("Expected an explicit recent-calls time range")
        }
        let response = #"{"data":{"data":[{"generation_id":"gen-synthetic","api_key_id":"account-key","date__hour":"2027-01-15T07:00:00Z","total_usage":"0.01","tokens_total":"50"}],"metadata":{"row_count":1,"truncated":false}}}"#
        return (200, ["Content-Type": "application/json"], Data(response.utf8))
      default:
        return (404, [:], Data())
      }
    }
    let client = ProviderHTTPClient(configuration: syntheticSessionConfiguration(), maximumRetries: 0)
    let page = try await OpenRouterUsageClient(
      httpClient: client,
      now: { Date(timeIntervalSince1970: 1_800_000_000) }
    ).fetchRecentCalls(apiKey: "sk-or-synthetic")

    XCTAssertEqual(page.calls.map(\.id), ["gen-synthetic"])
    XCTAssertEqual(page.calls.first?.apiKeyLabel, "account-key")
    XCTAssertEqual(page.calls.first?.totalTokens, 50)
  }

  @MainActor
  func testOpenRouterPrimaryAccountFlowKeepsBalanceWhenRecentCallsFail() async {
    SyntheticProviderURLProtocol.install { request in
      XCTAssertNotEqual(request.url?.path, "/api/v1/auth/keys")
      switch request.url?.path {
      case "/api/v1/credits":
        return (200, ["Content-Type": "application/json"], Data(#"{"data":{"total_credits":20,"total_usage":4}}"#.utf8))
      case "/api/v1/activity":
        return (200, ["Content-Type": "application/json"], Data(#"{"data":[]}"#.utf8))
      case "/api/v1/analytics/meta":
        let body = #"{"data":{"metrics":[{"name":"request_count","is_rate":false}],"dimensions":[{"name":"model"}],"granularities":[{"name":"day"}]}}"#
        return (200, ["Content-Type": "application/json"], Data(body.utf8))
      case "/api/v1/analytics/query":
        let body = #"{"data":{"data":[],"metadata":{"row_count":0,"truncated":false}}}"#
        return (200, ["Content-Type": "application/json"], Data(body.utf8))
      default:
        return (404, [:], Data())
      }
    }
    let client = ProviderHTTPClient(configuration: syntheticSessionConfiguration(), maximumRetries: 0)
    let store = DashisProviderStore(service: DashisProviderService(httpClient: client))
    store.openRouterManagementAPIKey = "sk-or-synthetic"

    await store.runPrimaryCheck(for: ProviderID.openRouter.rawValue)
    XCTAssertEqual(store.snapshots[.openRouter]?.balance?.remaining, 16)
    XCTAssertTrue(store.canLoadOpenRouterRecentCalls)

    await store.loadOpenRouterRecentCalls()
    if case .failed = store.openRouterRecentCallsState {
      // Expected: this synthetic account does not publish generation_id analytics.
    } else {
      XCTFail("Expected recent-call metadata to fail independently")
    }
    XCTAssertEqual(store.snapshots[.openRouter]?.balance?.remaining, 16)

    SyntheticProviderURLProtocol.install { request in
      switch request.url?.path {
      case "/api/v1/analytics/meta":
        let body = #"{"data":{"metrics":[{"name":"total_usage","is_rate":false}],"dimensions":[{"name":"generation_id"}],"granularities":[{"name":"hour"}]}}"#
        return (200, ["Content-Type": "application/json"], Data(body.utf8))
      case "/api/v1/analytics/query":
        let body = #"{"data":{"data":[{"generation_id":"gen-window","date__hour":"2027-01-15T07:00:00Z","total_usage":0.01}],"metadata":{"row_count":1,"truncated":false}}}"#
        return (200, ["Content-Type": "application/json"], Data(body.utf8))
      default:
        return (404, [:], Data())
      }
    }
    await store.loadOpenRouterRecentCalls()
    if case .loaded(let page) = store.openRouterRecentCallsState {
      XCTAssertEqual(page.calls.map(\.id), ["gen-window"])
    } else {
      XCTFail("Expected a loaded recent-call page")
    }
    store.openRouterRecentCallsDays = 2
    XCTAssertEqual(store.openRouterRecentCallsState, .idle)
    XCTAssertEqual(store.snapshots[.openRouter]?.balance?.remaining, 16)

    store.openRouterManagementAPIKey = "sk-or-other-synthetic"
    XCTAssertNil(store.snapshots[.openRouter])
    XCTAssertFalse(store.canLoadOpenRouterRecentCalls)
  }

  @MainActor
  func testOpenRouterLateAccountAndRecentCallResponsesCannotRestoreClearedState() async {
    let creditsStarted = expectation(description: "Delayed account credits request started")
    let releaseCredits = DispatchSemaphore(value: 0)
    SyntheticProviderURLProtocol.install { request in
      switch request.url?.path {
      case "/api/v1/credits":
        creditsStarted.fulfill()
        _ = releaseCredits.wait(timeout: .now() + 5)
        return (200, ["Content-Type": "application/json"], Data(#"{"data":{"total_credits":20,"total_usage":4}}"#.utf8))
      case "/api/v1/activity":
        return (200, ["Content-Type": "application/json"], Data(#"{"data":[]}"#.utf8))
      case "/api/v1/analytics/meta":
        let body = #"{"data":{"metrics":[{"name":"request_count","is_rate":false}],"dimensions":[{"name":"model"}],"granularities":[{"name":"day"}]}}"#
        return (200, ["Content-Type": "application/json"], Data(body.utf8))
      case "/api/v1/analytics/query":
        let body = #"{"data":{"data":[],"metadata":{"row_count":0,"truncated":false}}}"#
        return (200, ["Content-Type": "application/json"], Data(body.utf8))
      default:
        return (404, [:], Data())
      }
    }
    let client = ProviderHTTPClient(configuration: syntheticSessionConfiguration(), maximumRetries: 0)
    let store = DashisProviderStore(service: DashisProviderService(httpClient: client))
    store.openRouterManagementAPIKey = "sk-or-delayed-account"
    let accountTask = Task { await store.checkOpenRouterAccount() }

    await fulfillment(of: [creditsStarted], timeout: 2)
    store.clearOpenRouterSession()
    releaseCredits.signal()
    await accountTask.value

    XCTAssertNil(store.snapshots[.openRouter])
    XCTAssertEqual(store.openRouterRecentCallsState, .idle)
    XCTAssertTrue(store.openRouterManagementAPIKey.isEmpty)

    SyntheticProviderURLProtocol.install { request in
      switch request.url?.path {
      case "/api/v1/credits":
        return (200, ["Content-Type": "application/json"], Data(#"{"data":{"total_credits":20,"total_usage":4}}"#.utf8))
      case "/api/v1/activity":
        return (200, ["Content-Type": "application/json"], Data(#"{"data":[]}"#.utf8))
      case "/api/v1/analytics/meta":
        let body = #"{"data":{"metrics":[{"name":"request_count","is_rate":false}],"dimensions":[{"name":"model"}],"granularities":[{"name":"day"}]}}"#
        return (200, ["Content-Type": "application/json"], Data(body.utf8))
      case "/api/v1/analytics/query":
        let body = #"{"data":{"data":[],"metadata":{"row_count":0,"truncated":false}}}"#
        return (200, ["Content-Type": "application/json"], Data(body.utf8))
      default:
        return (404, [:], Data())
      }
    }
    store.openRouterManagementAPIKey = "sk-or-delayed-recent"
    await store.checkOpenRouterAccount()
    XCTAssertEqual(store.snapshots[.openRouter]?.balance?.remaining, 16)

    let recentQueryStarted = expectation(description: "Delayed recent-call query started")
    let releaseRecentQuery = DispatchSemaphore(value: 0)
    SyntheticProviderURLProtocol.install { request in
      switch request.url?.path {
      case "/api/v1/analytics/meta":
        let body = #"{"data":{"metrics":[{"name":"total_usage","is_rate":false}],"dimensions":[{"name":"generation_id"}],"granularities":[{"name":"hour"}]}}"#
        return (200, ["Content-Type": "application/json"], Data(body.utf8))
      case "/api/v1/analytics/query":
        recentQueryStarted.fulfill()
        _ = releaseRecentQuery.wait(timeout: .now() + 5)
        let body = #"{"data":{"data":[{"generation_id":"gen-late","date__hour":"2027-01-15T07:00:00Z","total_usage":0.01}],"metadata":{"row_count":1,"truncated":false}}}"#
        return (200, ["Content-Type": "application/json"], Data(body.utf8))
      default:
        return (404, [:], Data())
      }
    }
    let recentTask = Task { await store.loadOpenRouterRecentCalls() }

    await fulfillment(of: [recentQueryStarted], timeout: 2)
    store.openRouterMode = .singleKey
    releaseRecentQuery.signal()
    await recentTask.value

    XCTAssertEqual(store.openRouterMode, .singleKey)
    XCTAssertNil(store.snapshots[.openRouter])
    XCTAssertEqual(store.openRouterRecentCallsState, .idle)
    XCTAssertTrue(store.openRouterManagementAPIKey.isEmpty)
  }

  func testEmbeddedClaudeHelperForwardsStdinStdoutAndExitStatus() throws {
    guard let helperURL = Bundle.main.url(forAuxiliaryExecutable: "dashis-claude-statusline") else {
      throw XCTSkip("The hosted test bundle does not expose the embedded Claude helper.")
    }

    let input = Data(#"{"synthetic":"no-rate-limits"}"#.utf8)
    let process = Process()
    process.executableURL = helperURL
    process.arguments = [
      ClaudeBridgeCommand.markerArgument,
      ClaudeBridgeCommand.priorCommandArgument,
      Data("/bin/cat".utf8).base64EncodedString()
    ]

    let inputPipe = Pipe()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardInput = inputPipe
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()
    try inputPipe.fileHandleForWriting.write(contentsOf: input)
    try inputPipe.fileHandleForWriting.close()

    let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    XCTAssertEqual(output, input)
    XCTAssertEqual(process.terminationReason, .exit)
    XCTAssertEqual(process.terminationStatus, 0)
    XCTAssertTrue(errorOutput.isEmpty, String(decoding: errorOutput, as: UTF8.self))
  }

  private enum ExpectedSnapshotError {
    case unsafeFile
    case tooLarge
  }

  private func assertSnapshotReadError(
    _ expected: ExpectedSnapshotError,
    from url: URL,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(try ClaudeSnapshotFile.read(from: url), file: file, line: line) { error in
      guard let snapshotError = error as? ClaudeSnapshotFileError else {
        return XCTFail("Unexpected error type: \(error)", file: file, line: line)
      }
      switch (expected, snapshotError) {
      case (.unsafeFile, .unsafeFile), (.tooLarge, .tooLarge):
        break
      default:
        XCTFail("Unexpected snapshot error: \(snapshotError)", file: file, line: line)
      }
    }
  }

  private func syntheticClaudeSnapshot() -> ClaudeSanitizedSnapshot {
    ClaudeSanitizedSnapshot(
      observedAt: Date(timeIntervalSince1970: 1_800_000_000),
      fiveHour: ClaudeRateLimitWindowSnapshot(usedPercentage: 25, resetsAt: nil),
      sevenDay: nil
    )
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("dashis-security-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: NSNumber(value: 0o700)]
    )
    return url
  }

  private func syntheticSessionConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SyntheticProviderURLProtocol.self]
    return configuration
  }
}
