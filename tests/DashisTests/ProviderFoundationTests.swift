import Foundation
import XCTest
@testable import Dashis

final class ProviderEndpointPolicyTests: XCTestCase {
  func testOpenRouterKeyAllowsExactGET() throws {
    var request = URLRequest(url: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/key")))
    request.httpMethod = "GET"
    XCTAssertTrue(ProviderEndpointPolicy.allows(request))
  }

  func testOpenRouterRejectsWrongMethodAndUnexpectedQuery() throws {
    var wrongMethod = URLRequest(url: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/key")))
    wrongMethod.httpMethod = "POST"
    XCTAssertFalse(ProviderEndpointPolicy.allows(wrongMethod))

    var query = URLRequest(url: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/key?token=secret")))
    query.httpMethod = "GET"
    XCTAssertFalse(ProviderEndpointPolicy.allows(query))
  }

  func testPolicyRejectsLookalikeHostAndEmbeddedCredentials() throws {
    var lookalike = URLRequest(url: try XCTUnwrap(URL(string: "https://openrouter.ai.example.com/api/v1/key")))
    lookalike.httpMethod = "GET"
    XCTAssertFalse(ProviderEndpointPolicy.allows(lookalike))

    var credentials = URLRequest(url: try XCTUnwrap(URL(string: "https://user:password@openrouter.ai/api/v1/key")))
    credentials.httpMethod = "GET"
    XCTAssertFalse(ProviderEndpointPolicy.allows(credentials))
  }

  func testGoogleProjectPathsAndExactMetricFilter() throws {
    var quota = URLRequest(url: try XCTUnwrap(URL(string:
      "https://cloudquotas.googleapis.com/v1/projects/demo-project/locations/global/services/generativelanguage.googleapis.com/quotaInfos?pageSize=1000"
    )))
    quota.httpMethod = "GET"
    XCTAssertTrue(ProviderEndpointPolicy.allows(quota))

    var components = URLComponents(string: "https://monitoring.googleapis.com/v3/projects/demo-project/timeSeries")!
    components.queryItems = [
      URLQueryItem(name: "filter", value: "metric.type = \"generativelanguage.googleapis.com/quota/generate_content_requests_per_minute/usage\""),
      URLQueryItem(name: "interval.startTime", value: "2026-07-11T00:00:00Z"),
      URLQueryItem(name: "interval.endTime", value: "2026-07-11T01:00:00Z"),
      URLQueryItem(name: "view", value: "FULL")
    ]
    var monitoring = URLRequest(url: try XCTUnwrap(components.url))
    monitoring.httpMethod = "GET"
    XCTAssertTrue(ProviderEndpointPolicy.allows(monitoring))
  }

  func testPOSTRequiresExpectedContentTypeAndBody() throws {
    var request = URLRequest(url: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/analytics/query")))
    request.httpMethod = "POST"
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "metrics": ["request_count"],
      "limit": 100,
      "time_range": [
        "start": "2026-07-10T00:00:00Z",
        "end": "2026-07-11T00:00:00Z"
      ]
    ])
    XCTAssertFalse(ProviderEndpointPolicy.allows(request))
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    XCTAssertTrue(ProviderEndpointPolicy.allows(request))

    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "metrics": ["request_count"],
      "limit": 100,
      "time_range": [
        "start": "2026-07-10T00:00:00Z",
        "end": "2026-07-11T00:00:00Z"
      ],
      "unexpected": "value"
    ])
    XCTAssertFalse(ProviderEndpointPolicy.allows(request))
  }

  func testOpenRouterRecentCallsPolicyIsBoundedAndMetadataOnly() throws {
    var request = URLRequest(url: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/analytics/query")))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    func setBody(
      metrics: [String] = ["total_usage", "tokens_total"],
      dimensions: [String] = ["generation_id", "api_key_id"],
      granularity: String? = "hour",
      groupLimit: Int? = 1,
      limit: Int = 20,
      start: String = "2026-07-10T00:00:00Z"
    ) throws {
      var body: [String: Any] = [
        "metrics": metrics,
        "dimensions": dimensions,
        "limit": limit,
        "time_range": [
          "start": start,
          "end": "2026-07-11T00:00:00Z"
        ]
      ]
      if let granularity { body["granularity"] = granularity }
      if let groupLimit { body["group_limit"] = groupLimit }
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }

    try setBody()
    XCTAssertTrue(ProviderEndpointPolicy.allows(request))
    try setBody(dimensions: ["generation_id", "api_key_id", "model"])
    XCTAssertFalse(ProviderEndpointPolicy.allows(request))
    try setBody(dimensions: ["generation_id", "user"])
    XCTAssertFalse(ProviderEndpointPolicy.allows(request))
    try setBody(metrics: ["usage_web"])
    XCTAssertFalse(ProviderEndpointPolicy.allows(request))
    try setBody(metrics: ["total_usage", "total_usage"])
    XCTAssertFalse(ProviderEndpointPolicy.allows(request))
    try setBody(granularity: nil)
    XCTAssertFalse(ProviderEndpointPolicy.allows(request))
    try setBody(groupLimit: nil)
    XCTAssertFalse(ProviderEndpointPolicy.allows(request))
    try setBody(groupLimit: 2)
    XCTAssertFalse(ProviderEndpointPolicy.allows(request))
    try setBody(limit: 51)
    XCTAssertFalse(ProviderEndpointPolicy.allows(request))
    try setBody(start: "2026-06-01T00:00:00Z")
    XCTAssertFalse(ProviderEndpointPolicy.allows(request))

    var generation = URLRequest(url: try XCTUnwrap(URL(string:
      "https://openrouter.ai/api/v1/generation?id=gen-synthetic_123"
    )))
    generation.httpMethod = "GET"
    XCTAssertTrue(ProviderEndpointPolicy.allows(generation))

    var opaqueGeneration = URLRequest(url: try XCTUnwrap(URL(string:
      "https://openrouter.ai/api/v1/generation?id=opaque-request-123"
    )))
    opaqueGeneration.httpMethod = "GET"
    XCTAssertTrue(ProviderEndpointPolicy.allows(opaqueGeneration))

    var content = URLRequest(url: try XCTUnwrap(URL(string:
      "https://openrouter.ai/api/v1/generation/content?id=gen-synthetic_123"
    )))
    content.httpMethod = "GET"
    XCTAssertFalse(ProviderEndpointPolicy.allows(content))
  }
}

final class ProviderSnapshotTests: XCTestCase {
  func testFreshStaleExpiredAndFutureTimestamps() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    XCTAssertEqual(FreshnessPolicy.freshness(of: snapshot(at: now.addingTimeInterval(-60)), now: now), .fresh)
    XCTAssertEqual(FreshnessPolicy.freshness(of: snapshot(at: now.addingTimeInterval(-16 * 60)), now: now), .stale)
    XCTAssertEqual(FreshnessPolicy.freshness(of: snapshot(at: now.addingTimeInterval(-25 * 60 * 60)), now: now), .expired)
    XCTAssertEqual(FreshnessPolicy.freshness(of: snapshot(at: now.addingTimeInterval(61)), now: now), .missing)
  }

  func testProjectionPreservesNegativeBalanceWhileClampingOnlyProgress() {
    let snapshot = ProviderSnapshot(
      providerID: .openRouter,
      scope: ProviderScope(kind: .apiKey, label: "OAuth key"),
      sourceKind: .officialDirect,
      observedAt: Date(),
      windows: [],
      balance: ProviderBalance(
        label: "Key limit",
        used: 12,
        limit: 10,
        remaining: -2,
        unit: "USD",
        resetDescription: nil
      ),
      metrics: [],
      warnings: [],
      partialFailures: []
    )
    let projected = ProviderCardProjection.apply(snapshot: snapshot, to: .openRouter)
    XCTAssertEqual(projected.primary, "$-2.00")
    XCTAssertEqual(projected.statusLabel, "exceeded")
    XCTAssertEqual(projected.progress, 100)
    XCTAssertEqual(snapshot.balance?.remaining, -2)
  }

  func testProjectionTreatsTextualCreditBalanceAsData() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = ProviderSnapshot(
      providerID: .codex,
      scope: .personal("credit-based plan"),
      sourceKind: .experimentalPrivate,
      observedAt: now,
      windows: [],
      balance: ProviderBalance(
        label: "Codex credits",
        used: nil,
        limit: nil,
        remaining: nil,
        unit: "credits",
        resetDescription: nil,
        valueDescription: "Unlimited"
      ),
      metrics: [],
      warnings: [],
      partialFailures: []
    )

    let projected = ProviderCardProjection.apply(snapshot: snapshot, to: .codex, now: now)
    XCTAssertTrue(snapshot.hasData)
    XCTAssertEqual(projected.primary, "Unlimited")
    XCTAssertEqual(projected.statusLabel, "connected")
    XCTAssertEqual(projected.stats.first?.value, "Unlimited")
  }

  func testVisualizationPrioritizesReturnedWindowAndKeepsCreditsSecondary() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let reset = now.addingTimeInterval(7 * 24 * 60 * 60)
    let snapshot = ProviderSnapshot(
      providerID: .codex,
      scope: .personal("pro"),
      sourceKind: .experimentalPrivate,
      observedAt: now,
      windows: [
        QuotaWindow(
          id: "weekly",
          label: "Weekly usage limit",
          used: nil,
          limit: 100,
          remaining: nil,
          usedPercentage: 6,
          remainingPercentage: 94,
          resetsAt: reset,
          unit: "%",
          isEstimated: false
        )
      ],
      balance: ProviderBalance(
        label: "Credits remaining",
        used: nil,
        limit: nil,
        remaining: 0,
        unit: "credits",
        resetDescription: nil
      ),
      metrics: [
        ProviderMetric(key: "reset_credits", label: "Available reset credits", value: 5, unit: "credits")
      ],
      warnings: [],
      partialFailures: []
    )

    let visualization = ProviderVisualizationProjection.make(snapshot: snapshot, now: now)

    XCTAssertEqual(visualization.primaryCards.count, 2)
    XCTAssertEqual(visualization.primaryCards[0].headline, "94%")
    XCTAssertEqual(visualization.primaryCards[0].descriptor, "remaining")
    XCTAssertEqual(try XCTUnwrap(visualization.primaryCards[0].progressFraction), 0.94, accuracy: 0.000_001)
    XCTAssertEqual(visualization.primaryCards[0].progressKind, .remaining)
    XCTAssertTrue(visualization.primaryCards[0].supportingText?.hasPrefix("Resets ") == true)
    XCTAssertEqual(visualization.primaryCards[1].headline, "0")
    XCTAssertEqual(visualization.primaryCards[1].supportingText, "5 credits reset available")
  }

  func testVisualizationDoesNotInventProgressForLimitOnlyWindow() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = ProviderSnapshot(
      providerID: .google,
      scope: .project("demo-project"),
      sourceKind: .officialDirect,
      observedAt: now,
      windows: [
        QuotaWindow(
          id: "requests",
          label: "Requests per minute",
          used: nil,
          limit: 60,
          remaining: nil,
          usedPercentage: nil,
          remainingPercentage: nil,
          resetsAt: nil,
          unit: "requests",
          isEstimated: false
        )
      ],
      balance: nil,
      metrics: [],
      warnings: [],
      partialFailures: []
    )

    let card = ProviderVisualizationProjection.make(snapshot: snapshot, now: now).primaryCards[0]
    XCTAssertEqual(card.headline, "60 requests")
    XCTAssertEqual(card.descriptor, "limit")
    XCTAssertNil(card.progressFraction)
    XCTAssertNil(card.progressKind)
  }

  func testVisualizationCreditOnlyCodexDoesNotInventUsageWindow() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = ProviderSnapshot(
      providerID: .codex,
      scope: .personal("credit-based plan"),
      sourceKind: .experimentalPrivate,
      observedAt: now,
      windows: [],
      balance: ProviderBalance(
        label: "Codex credits",
        used: nil,
        limit: nil,
        remaining: nil,
        unit: "credits",
        resetDescription: nil,
        valueDescription: "Unlimited"
      ),
      metrics: [],
      warnings: [],
      partialFailures: []
    )

    let visualization = ProviderVisualizationProjection.make(snapshot: snapshot, now: now)
    XCTAssertEqual(visualization.primaryCards.map(\.title), ["Codex credits"])
    XCTAssertEqual(visualization.primaryCards[0].headline, "Unlimited")
    XCTAssertNil(visualization.primaryCards[0].progressFraction)
  }

  func testVisualizationMergesDuplicateOpenRouterBalanceAndWindow() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = ProviderSnapshot(
      providerID: .openRouter,
      scope: ProviderScope(kind: .apiKey, label: "OAuth key"),
      sourceKind: .officialDirect,
      observedAt: now,
      windows: [
        QuotaWindow(
          id: "key-limit",
          label: "Key limit",
          used: 2,
          limit: 10,
          remaining: 8,
          usedPercentage: 20,
          remainingPercentage: 80,
          resetsAt: nil,
          unit: "USD",
          isEstimated: false
        )
      ],
      balance: ProviderBalance(
        label: "Key limit",
        used: 2,
        limit: 10,
        remaining: 8,
        unit: "USD",
        resetDescription: nil
      ),
      metrics: [],
      warnings: [],
      partialFailures: []
    )

    let visualization = ProviderVisualizationProjection.make(snapshot: snapshot, now: now)
    XCTAssertEqual(visualization.primaryCards.count, 1)
    XCTAssertEqual(visualization.primaryCards[0].title, "Key limit")
    XCTAssertEqual(visualization.primaryCards[0].headline, "$8.00")
  }

  func testISODateParsesWithAndWithoutFractionalSeconds() {
    XCTAssertNotNil(ProviderJSON.date("2026-07-11T01:02:03Z"))
    XCTAssertNotNil(ProviderJSON.date("2026-07-11T01:02:03.456Z"))
  }

  private func snapshot(at date: Date) -> ProviderSnapshot {
    ProviderSnapshot(
      providerID: .claude,
      scope: .personal("Claude Code"),
      sourceKind: .officialLocalBridge,
      observedAt: date,
      windows: [],
      balance: nil,
      metrics: [ProviderMetric(key: "fixture", label: "Fixture", value: 1, unit: "value")],
      warnings: [],
      partialFailures: []
    )
  }
}

final class ProviderPKCETests: XCTestCase {
  func testGeneratedPKCEUsesURLSafeS256Values() throws {
    let pair = try ProviderPKCE.generate()
    XCTAssertGreaterThanOrEqual(pair.verifier.count, 43)
    XCTAssertEqual(pair.challenge.count, 43)
    XCTAssertNil(pair.verifier.range(of: #"[^A-Za-z0-9_-]"#, options: .regularExpression))
    XCTAssertNil(pair.challenge.range(of: #"[^A-Za-z0-9_-]"#, options: .regularExpression))
    XCTAssertFalse(pair.verifier.contains("="))
    XCTAssertFalse(pair.challenge.contains("="))
  }
}
