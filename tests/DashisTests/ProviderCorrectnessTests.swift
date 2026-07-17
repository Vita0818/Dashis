import Foundation
import XCTest
@testable import Dashis

final class CodexEnterpriseCorrectnessTests: XCTestCase {
  func testEnterpriseDecoderRejectsArbitraryEnvelope() {
    XCTAssertThrowsError(
      try CodexUsageClient.decodeEnterprisePage(["unexpected": []])
    )
    XCTAssertThrowsError(
      try CodexUsageClient.decodeEnterprisePage(["data": ["not": "an array"]])
    )
  }

  func testEnterpriseDecoderRejectsMalformedAndUnrecognizedRows() {
    XCTAssertThrowsError(
      try CodexUsageClient.decodeEnterprisePage(["data": ["not-a-row"]])
    )
    XCTAssertThrowsError(
      try CodexUsageClient.decodeEnterprisePage(["data": [["unknown_metric": 1]]])
    )
    XCTAssertThrowsError(
      try CodexUsageClient.decodeEnterprisePage(["data": [["turns": "not-an-integer"]]])
    )
  }
}

final class OpenRouterCorrectnessTests: XCTestCase {
  func testActivityRejectsMalformedAndUnrecognizedRows() {
    XCTAssertThrowsError(
      try OpenRouterUsageClient.decodeActivity(["data": ["not-a-row"]])
    )
    XCTAssertThrowsError(
      try OpenRouterUsageClient.decodeActivity(["data": [["unknown_metric": 1]]])
    )
  }

  func testActivityRejectsIntegerOverflow() {
    XCTAssertThrowsError(
      try OpenRouterUsageClient.decodeActivity([
        "data": [
          ["requests": Int.max],
          ["requests": 1]
        ]
      ])
    )
  }

  func testGenerationRejectsArbitraryDictionary() {
    XCTAssertThrowsError(
      try OpenRouterUsageClient.decodeGeneration(["data": ["id": "synthetic-generation"]])
    )
    XCTAssertThrowsError(
      try OpenRouterUsageClient.decodeGeneration(["id": "synthetic-generation"])
    )
  }

  func testAnalyticsRejectsMissingMetadataOrTruncatedFlag() {
    let rows: [[String: Any]] = [["request_count": 1]]

    XCTAssertThrowsError(
      try OpenRouterUsageClient.decodeAnalyticsSummary(
        ["data": ["data": rows]],
        requestedMetrics: ["request_count"]
      )
    )
    XCTAssertThrowsError(
      try OpenRouterUsageClient.decodeAnalyticsSummary(
        [
          "data": [
            "data": rows,
            "metadata": ["row_count": 1]
          ]
        ],
        requestedMetrics: ["request_count"]
      )
    )
  }

  func testAnalyticsRejectsRowMissingRequestedMetric() {
    XCTAssertThrowsError(
      try OpenRouterUsageClient.decodeAnalyticsSummary(
        [
          "data": [
            "data": [["usage": 1.25]],
            "metadata": ["row_count": 1, "truncated": false]
          ]
        ],
        requestedMetrics: ["request_count"]
      )
    )
  }

  func testAnalyticsMetadataSeparatesRateMetricsFromSummableMetrics() throws {
    let definition = try OpenRouterUsageClient.decodeAnalyticsDefinition([
      "data": [
        "metrics": [
          ["name": "request_count", "is_rate": false],
          ["name": "requests_per_second", "is_rate": true]
        ],
        "dimensions": [],
        "granularities": []
      ]
    ])

    XCTAssertEqual(definition.metrics, ["request_count"])
    XCTAssertEqual(definition.rateMetrics, ["requests_per_second"])
    XCTAssertFalse(definition.metrics.contains("requests_per_second"))
  }
}

final class GoogleQuotaCorrectnessTests: XCTestCase {
  private let quotaID = "GenerateRequestsPerMinute"
  private let usageMetric = "generativelanguage.googleapis.com/quota/generate_content_requests_per_minute/usage"
  private let limitMetric = "generativelanguage.googleapis.com/quota/generate_content_requests_per_minute/limit"
  private let now = Date(timeIntervalSince1970: 1_800_000_050)

  func testOfficialRefreshIntervalNamesMapToSupportedCadences() {
    XCTAssertEqual(GoogleQuotaCadence(refreshInterval: "minute"), .minute)
    XCTAssertEqual(GoogleQuotaCadence(refreshInterval: "hour"), .hour)
    XCTAssertEqual(GoogleQuotaCadence(refreshInterval: "day"), .pacificDay)
  }

  func testQuotaDecoderRejectsNegativeEffectiveLimit() {
    XCTAssertThrowsError(try GoogleQuotaPayloadDecoder.decode([
      "quotaInfos": [[
        "quotaId": quotaID,
        "metric": "generativelanguage.googleapis.com/generate_content_requests_per_minute",
        "refreshInterval": "minute",
        "dimensionsInfos": [["details": ["value": -1]]]
      ]]
    ]))
  }

  func testMismatchedLimitNameDoesNotProduceRemaining() throws {
    let quota = makeQuota(
      dimensionInfos: [dimension(limit: 100)]
    )
    let usage = series(
      metricType: usageMetric,
      kind: .delta,
      labels: ["limit_name": "DifferentQuota"],
      points: [deltaPoint(used: 25)]
    )

    let result = GoogleQuotaDeriver.derive(
      quota: quota,
      limitSeries: [],
      usageSeries: [usage],
      now: now
    )

    let window = try XCTUnwrap(result.windows.first)
    XCTAssertNil(window.used)
    XCTAssertNil(window.remaining)
    XCTAssertTrue(result.warnings.contains { $0.id.contains("google-limit-name") })
  }

  func testModelAndLocationMismatchDoNotProduceUsage() throws {
    let quota = makeQuota(
      dimensions: ["model"],
      dimensionInfos: [
        dimension(
          dimensions: ["model": "gemini-pro"],
          limit: 100,
          locations: ["global"]
        )
      ]
    )
    let wrongModel = series(
      metricType: usageMetric,
      kind: .delta,
      labels: [
        "limit_name": quotaID,
        "model": "gemini-flash",
        "location": "global"
      ],
      points: [deltaPoint(used: 10)]
    )
    let wrongLocation = series(
      metricType: usageMetric,
      kind: .delta,
      labels: [
        "limit_name": quotaID,
        "model": "gemini-pro",
        "location": "europe-west1"
      ],
      points: [deltaPoint(used: 15)]
    )

    let result = GoogleQuotaDeriver.derive(
      quota: quota,
      limitSeries: [],
      usageSeries: [wrongModel, wrongLocation],
      now: now
    )

    let window = try XCTUnwrap(result.windows.first)
    XCTAssertNil(window.used)
    XCTAssertNil(window.remaining)
  }

  func testRegionDimensionMatchesMonitoringLocationAlias() throws {
    let quota = makeQuota(
      dimensions: ["region"],
      dimensionInfos: [
        dimension(dimensions: ["region": "us-central1"], limit: 100)
      ]
    )
    let usage = series(
      metricType: usageMetric,
      kind: .delta,
      labels: ["limit_name": quotaID, "location": "us-central1"],
      points: [deltaPoint(used: 25)]
    )

    let result = GoogleQuotaDeriver.derive(
      quota: quota,
      limitSeries: [series(
        metricType: limitMetric,
        kind: .gauge,
        labels: ["limit_name": quotaID, "location": "us-central1"],
        points: [gaugePoint(value: 100, secondsBeforeNow: 15)]
      )],
      usageSeries: [usage],
      now: now
    )
    let window = try XCTUnwrap(result.windows.first)
    XCTAssertEqual(window.used, 25)
    XCTAssertEqual(window.remaining, 75)
  }

  func testDimensionInfosUseFirstMatchingMostSpecificEntry() throws {
    let quota = makeQuota(
      dimensions: ["model"],
      dimensionInfos: [
        dimension(dimensions: ["model": "gemini-pro"], limit: 100),
        dimension(limit: 1_000)
      ]
    )
    let usage = series(
      metricType: usageMetric,
      kind: .delta,
      labels: ["limit_name": quotaID, "model": "gemini-pro"],
      points: [deltaPoint(used: 40)]
    )

    let result = GoogleQuotaDeriver.derive(
      quota: quota,
      limitSeries: [series(
        metricType: limitMetric,
        kind: .gauge,
        labels: ["limit_name": quotaID, "model": "gemini-pro"],
        points: [gaugePoint(value: 100, secondsBeforeNow: 15)]
      )],
      usageSeries: [usage],
      now: now
    )

    XCTAssertEqual(result.windows.count, 2)
    let specific = try XCTUnwrap(result.windows.first { $0.label.contains("model: gemini-pro") })
    let fallback = try XCTUnwrap(result.windows.first { !$0.label.contains("model: gemini-pro") })
    XCTAssertEqual(specific.used, 40)
    XCTAssertEqual(specific.remaining, 60)
    XCTAssertNil(fallback.used, "A series matching the specific entry must not be counted again in the fallback entry")
    XCTAssertNil(fallback.remaining)
  }

  func testConflictingCloudQuotasAndMonitoringLimitsHideRemaining() throws {
    let quota = makeQuota(
      dimensionInfos: [dimension(limit: 100)]
    )
    let monitoredLimit = series(
      metricType: limitMetric,
      kind: .gauge,
      labels: ["limit_name": quotaID],
      points: [gaugePoint(value: 120, secondsBeforeNow: 15)]
    )
    let usage = series(
      metricType: usageMetric,
      kind: .delta,
      labels: ["limit_name": quotaID],
      points: [deltaPoint(used: 10)]
    )

    let result = GoogleQuotaDeriver.derive(
      quota: quota,
      limitSeries: [monitoredLimit],
      usageSeries: [usage],
      now: now
    )

    let window = try XCTUnwrap(result.windows.first)
    XCTAssertNil(window.limit)
    XCTAssertEqual(window.used, 10)
    XCTAssertNil(window.remaining)
    XCTAssertTrue(result.warnings.contains { $0.id.contains("google-limit-mismatch") })
  }

  func testConcurrentQuotaRejectsDeltaUsage() throws {
    let quota = makeQuota(
      refreshInterval: nil,
      isConcurrent: true,
      dimensionInfos: [dimension(limit: 20)]
    )
    let delta = series(
      metricType: usageMetric,
      kind: .delta,
      labels: ["limit_name": quotaID],
      points: [deltaPoint(used: 8)]
    )

    let result = GoogleQuotaDeriver.derive(
      quota: quota,
      limitSeries: [],
      usageSeries: [delta],
      now: now
    )

    XCTAssertNil(try XCTUnwrap(result.windows.first).used)
  }

  func testConcurrentQuotaUsesLatestGaugePoint() throws {
    let quota = makeQuota(
      refreshInterval: nil,
      isConcurrent: true,
      dimensionInfos: [dimension(limit: 20)]
    )
    let gauge = series(
      metricType: usageMetric,
      kind: .gauge,
      labels: ["limit_name": quotaID],
      points: [
        gaugePoint(value: 3, secondsBeforeNow: 40),
        gaugePoint(value: 7, secondsBeforeNow: 5)
      ]
    )

    let result = GoogleQuotaDeriver.derive(
      quota: quota,
      limitSeries: [],
      usageSeries: [gauge],
      now: now
    )

    let window = try XCTUnwrap(result.windows.first)
    XCTAssertEqual(window.used, 7)
    XCTAssertEqual(window.remaining, 13)
  }

  func testMonitoringFragmentsFromPointPaginationAreCoalesced() {
    let labels = ["limit_name": quotaID, "model": "gemini-pro", "method": "generateContent"]
    let first = series(
      metricType: usageMetric,
      kind: .delta,
      labels: labels,
      points: [deltaPoint(used: 4)]
    )
    let second = series(
      metricType: usageMetric,
      kind: .delta,
      labels: labels,
      points: [GoogleMonitoringPoint(
        start: now.addingTimeInterval(-20),
        end: now.addingTimeInterval(-5),
        value: 6
      )]
    )

    let result = GeminiAPIProjectUsageClient.coalescedMonitoringSeries([first, second])
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result.first?.points.count, 2)
  }

  func testShortWindowUsesLatestCommonCompletedBucketAcrossSeries() throws {
    let quota = makeQuota(dimensionInfos: [dimension(limit: 100)])
    let commonEnd = now.addingTimeInterval(-70)
    let commonStart = now.addingTimeInterval(-120)
    let first = series(
      metricType: usageMetric,
      kind: .delta,
      labels: ["limit_name": quotaID, "method": "generateContent"],
      points: [
        GoogleMonitoringPoint(start: commonStart, end: commonEnd, value: 4),
        GoogleMonitoringPoint(
          start: now.addingTimeInterval(-50),
          end: now.addingTimeInterval(-10),
          value: 100
        )
      ]
    )
    let second = series(
      metricType: usageMetric,
      kind: .delta,
      labels: ["limit_name": quotaID, "method": "streamGenerateContent"],
      points: [GoogleMonitoringPoint(start: commonStart, end: commonEnd, value: 6)]
    )
    let limit = series(
      metricType: limitMetric,
      kind: .gauge,
      labels: ["limit_name": quotaID],
      points: [GoogleMonitoringPoint(start: nil, end: now.addingTimeInterval(-75), value: 100)]
    )

    let result = GoogleQuotaDeriver.derive(
      quota: quota,
      limitSeries: [limit],
      usageSeries: [first, second],
      now: now
    )
    let window = try XCTUnwrap(result.windows.first)
    XCTAssertEqual(window.used, 10)
    XCTAssertEqual(window.remaining, 90)
    XCTAssertTrue(window.label.contains(ISO8601DateFormatter.providerStandard.string(from: commonEnd)))
  }

  func testShortWindowLeavesOverlyOldMonitoringPointUnavailable() throws {
    let quota = makeQuota(dimensionInfos: [dimension(limit: 100)])
    let oldUsage = series(
      metricType: usageMetric,
      kind: .delta,
      labels: ["limit_name": quotaID],
      points: [GoogleMonitoringPoint(
        start: now.addingTimeInterval(-760),
        end: now.addingTimeInterval(-700),
        value: 12
      )]
    )

    let result = GoogleQuotaDeriver.derive(
      quota: quota,
      limitSeries: [],
      usageSeries: [oldUsage],
      now: now
    )
    let window = try XCTUnwrap(result.windows.first)
    XCTAssertNil(window.used)
    XCTAssertNil(window.remaining)
    XCTAssertFalse(window.label.contains("as of"))
  }

  func testGoogleOAuthRejectsWrongState() throws {
    let redirect = try XCTUnwrap(
      URL(string: "http://127.0.0.1:54321/dashis/google/oauth/synthetic-callback-nonce")
    )
    let flow = try GoogleDesktopOAuth.makeAuthorizationFlow(
      clientID: "12345-synthetic.apps.googleusercontent.com",
      redirectURI: redirect
    )
    var callback = URLComponents(url: redirect, resolvingAgainstBaseURL: false)
    callback?.queryItems = [
      URLQueryItem(name: "code", value: "synthetic-code"),
      URLQueryItem(name: "state", value: "wrong-synthetic-state")
    ]

    XCTAssertThrowsError(
      try GoogleDesktopOAuth.authorizationCode(
        from: try XCTUnwrap(callback?.url),
        flow: flow
      )
    ) { error in
      XCTAssertEqual(error as? GoogleDesktopOAuthError, .stateMismatch)
    }
  }

  private func makeQuota(
    refreshInterval: String? = "minute",
    dimensions: [String] = [],
    isConcurrent: Bool? = nil,
    dimensionInfos: [GoogleQuotaDimensionInfo]
  ) -> GoogleQuotaInfo {
    GoogleQuotaInfo(
      quotaID: quotaID,
      metric: "generativelanguage.googleapis.com/generate_content_requests_per_minute",
      displayName: "Generate requests",
      metricUnit: "requests",
      refreshInterval: refreshInterval,
      isPrecise: true,
      dimensions: dimensions,
      isConcurrent: isConcurrent,
      dimensionInfos: dimensionInfos
    )
  }

  private func dimension(
    dimensions: [String: String] = [:],
    limit: Double?,
    locations: [String] = []
  ) -> GoogleQuotaDimensionInfo {
    GoogleQuotaDimensionInfo(
      dimensions: dimensions,
      effectiveLimit: limit,
      applicableLocations: locations
    )
  }

  private func series(
    metricType: String,
    kind: GoogleMetricKind,
    labels: [String: String],
    points: [GoogleMonitoringPoint]
  ) -> GoogleMonitoringSeries {
    GoogleMonitoringSeries(
      metricType: metricType,
      metricKind: kind,
      metricLabels: labels,
      resourceLabels: [:],
      points: points
    )
  }

  private func deltaPoint(used: Double) -> GoogleMonitoringPoint {
    GoogleMonitoringPoint(
      start: now.addingTimeInterval(-30),
      end: now.addingTimeInterval(-10),
      value: used
    )
  }

  private func gaugePoint(value: Double, secondsBeforeNow: TimeInterval) -> GoogleMonitoringPoint {
    GoogleMonitoringPoint(
      start: nil,
      end: now.addingTimeInterval(-secondsBeforeNow),
      value: value
    )
  }
}

final class DashisProviderRegistryCorrectnessTests: XCTestCase {
  @MainActor
  func testStoreContainsExactlyTheFourBuiltInProviders() {
    let store = DashisProviderStore()

    XCTAssertEqual(
      store.providers.map(\.id),
      [
        ProviderID.codex.rawValue,
        ProviderID.claude.rawValue,
        ProviderID.google.rawValue,
        ProviderID.openRouter.rawValue
      ]
    )
    XCTAssertEqual(Set(store.providers.map(\.id)).count, 4)
    XCTAssertTrue(store.providers.allSatisfy(\.isBuiltIn))
  }

  func testHistoricalGoogleWindowIsProminentInCardProjection() {
    let snapshot = ProviderSnapshot(
      providerID: .google,
      scope: .project("synthetic-project"),
      sourceKind: .officialDerived,
      observedAt: Date(timeIntervalSince1970: 1_800_000_000),
      windows: [QuotaWindow(
        id: "synthetic-window",
        label: "Requests · per minute · as of synthetic-time",
        used: 25,
        limit: 100,
        remaining: 75,
        usedPercentage: 25,
        remainingPercentage: 75,
        resetsAt: nil,
        unit: "requests",
        isEstimated: true
      )],
      balance: nil,
      metrics: [],
      warnings: [ProviderWarning(
        id: "google-historical-window-synthetic",
        message: "Synthetic latest completed window ending synthetic-time; not live."
      )],
      partialFailures: []
    )
    let provider = ProviderCardProjection.apply(
      snapshot: snapshot,
      to: .googleAI,
      now: snapshot.observedAt
    )
    XCTAssertEqual(provider.freshnessLabel, "Historical")
    XCTAssertEqual(provider.statusLabel, "historical")
    XCTAssertTrue(provider.primary.contains("historical"))
    XCTAssertTrue(provider.caption.contains("Latest complete historical"))
  }
}
