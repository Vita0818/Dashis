import Darwin
import Foundation
import XCTest
@testable import Dashis

final class CodexUsageDecoderTests: XCTestCase {
  func testPersonalWindowsAndResetCredits() throws {
    let payload: [String: Any] = [
      "plan_type": "plus",
      "rate_limit": [
        "allowed": true,
        "limit_reached": false,
        "primary_window": [
          "limit_window_seconds": 18_000,
          "used_percent": 25,
          "reset_at": 1_800_000_000
        ],
        "secondary_window": [
          "limit_window_seconds": 604_800,
          "used_percent": 110,
          "reset_at": 1_800_500_000
        ]
      ],
      "rate_limit_reset_credits": ["available_count": 3]
    ]
    let decoded = try CodexUsageClient.decodePersonalUsage(payload)
    XCTAssertEqual(decoded.plan, "plus")
    XCTAssertEqual(decoded.windows.count, 2)
    XCTAssertEqual(decoded.windows[0].label, "5-hour window")
    XCTAssertEqual(decoded.windows[1].label, "7-day window")
    XCTAssertEqual(decoded.windows[0].remainingPercentage, 75)
    XCTAssertEqual(decoded.windows[1].remainingPercentage, -10)
    XCTAssertEqual(decoded.fallbackResetCredits, 3)
  }

  func testPersonalDecoderFailsClosedWithoutUsageEnvelope() {
    XCTAssertThrowsError(try CodexUsageClient.decodePersonalUsage(["plan_type": "plus"]))
  }

  func testPersonalCreditOnlyResponseDoesNotInventFiveHourWindow() throws {
    let decoded = try CodexUsageClient.decodePersonalUsage([
      "plan_type": "plus",
      "credits": [
        "has_credits": true,
        "unlimited": false,
        "balance": "42.5"
      ]
    ])

    XCTAssertTrue(decoded.windows.isEmpty)
    XCTAssertEqual(decoded.credits?.balance, 42.5)
    XCTAssertEqual(decoded.credits?.hasCredits, true)
    XCTAssertEqual(decoded.credits?.unlimited, false)
  }

  func testPersonalWindowlessRateLimitIsAcceptedWithoutInventingWindow() throws {
    let decoded = try CodexUsageClient.decodePersonalUsage([
      "plan_type": "enterprise",
      "rate_limit": ["allowed": true, "limit_reached": false]
    ])

    XCTAssertEqual(decoded.allowed, true)
    XCTAssertEqual(decoded.limitReached, false)
    XCTAssertTrue(decoded.windows.isEmpty)
  }

  func testPersonalWindowLabelsFollowReportedDurationRatherThanSlotName() throws {
    let decoded = try CodexUsageClient.decodePersonalUsage([
      "rate_limit": [
        "primary_window": ["limit_window_seconds": 7_200, "used_percent": 10],
        "secondary_window": ["limit_window_seconds": 259_200, "used_percent": 20]
      ]
    ])

    XCTAssertEqual(decoded.windows.map(\.label), ["2-hour window", "3-day window"])
  }

  func testPersonalInvalidDurationsUseGenericSlotLabelsWithoutOverflow() throws {
    let decoded = try CodexUsageClient.decodePersonalUsage([
      "rate_limit": [
        "primary_window": ["limit_window_seconds": -1, "used_percent": 10],
        "secondary_window": [
          "limit_window_seconds": Double.greatestFiniteMagnitude,
          "used_percent": 20
        ]
      ]
    ])

    XCTAssertEqual(
      decoded.windows.map(\.label),
      ["Primary usage window", "Secondary usage window"]
    )
  }

  func testPersonalCreditsRejectMalformedKnownFields() {
    XCTAssertThrowsError(try CodexUsageClient.decodePersonalUsage([
      "credits": ["balance": "not-a-number"]
    ]))
    XCTAssertThrowsError(try CodexUsageClient.decodePersonalUsage([
      "credits": ["unknown": true]
    ]))
    XCTAssertThrowsError(try CodexUsageClient.decodePersonalUsage([
      "credits": ["balance": NSNull(), "unlimited": NSNull(), "has_credits": NSNull()]
    ]))
  }

  func testPersonalCreditProjectionPreservesReportedStates() throws {
    let numeric = try CodexUsageClient.decodePersonalUsage([
      "credits": ["balance": 12.5]
    ])
    let unlimited = try CodexUsageClient.decodePersonalUsage([
      "credits": ["unlimited": true, "balance": 12.5]
    ])
    let unavailable = try CodexUsageClient.decodePersonalUsage([
      "credits": ["has_credits": false]
    ])

    XCTAssertEqual(CodexUsageClient.personalCreditBalance(numeric.credits)?.remaining, 12.5)
    XCTAssertEqual(
      CodexUsageClient.personalCreditBalance(unlimited.credits)?.valueDescription,
      "Unlimited"
    )
    XCTAssertEqual(
      CodexUsageClient.personalCreditBalance(unavailable.credits)?.valueDescription,
      "No additional credits"
    )
  }

  func testEnterprisePageNormalizesAliasesAndPagination() throws {
    let page = try CodexUsageClient.decodeEnterprisePage([
      "items": [
        [
          "thread_count": 2,
          "turnCount": 4,
          "credit_usage": 1.5,
          "input_tokens": 10,
          "cachedInputTokens": 3,
          "outputTokens": 7
        ]
      ],
      "pagination": ["nextPageToken": "page-2", "hasMore": true]
    ])
    XCTAssertEqual(page.totals.threads, 2)
    XCTAssertEqual(page.totals.turns, 4)
    XCTAssertEqual(page.totals.textInputTokens, 10)
    XCTAssertEqual(page.totals.cachedInputTokens, 3)
    XCTAssertEqual(page.totals.textOutputTokens, 7)
    XCTAssertEqual(page.nextPage, "page-2")
    XCTAssertTrue(page.hasMore)
  }
}

final class OpenRouterUsageDecoderTests: XCTestCase {
  func testKeyAndCreditsPreserveNegativeRemaining() throws {
    let key = try OpenRouterUsageClient.decodeKey([
      "data": ["usage": 12, "limit": 10, "limit_remaining": -2]
    ])
    XCTAssertEqual(key.remaining, -2)

    let credits = try OpenRouterUsageClient.decodeCredits([
      "data": ["total_credits": 10, "total_usage": 12]
    ])
    XCTAssertEqual(credits.remaining, -2)
  }

  func testReasoningIsBreakdownAndNotAddedTwice() throws {
    let activity = try OpenRouterUsageClient.decodeActivity([
      "data": [[
        "requests": 1,
        "prompt_tokens": 10,
        "completion_tokens": 20,
        "reasoning_tokens": 7,
        "model": "example/model"
      ]]
    ])
    XCTAssertEqual(activity.totalTokens, 30)
    XCTAssertEqual(activity.reasoningTokens, 7)

    let generation = try OpenRouterUsageClient.decodeGeneration([
      "data": [
        "prompt_tokens": 10,
        "completion_tokens": 20,
        "reasoning_tokens": 7
      ]
    ])
    XCTAssertEqual(generation.totalTokens, 30)
  }

  func testActivityPrefersProviderTotalTokens() throws {
    let activity = try OpenRouterUsageClient.decodeActivity([
      "data": [[
        "prompt_tokens": 10,
        "completion_tokens": 20,
        "reasoning_tokens": 7,
        "total_tokens": 31
      ]]
    ])
    XCTAssertEqual(activity.totalTokens, 31)
  }

  func testAnalyticsUsesMetadataAndTruncation() throws {
    let definition = try OpenRouterUsageClient.decodeAnalyticsDefinition([
      "data": [
        "metrics": [
          ["name": "request_count", "is_rate": false],
          ["name": "usage", "is_rate": false],
          ["name": "requests_per_second", "is_rate": true]
        ],
        "dimensions": [["name": "model"]],
        "granularities": ["day"]
      ]
    ])
    XCTAssertEqual(definition.metrics, ["request_count", "usage"])
    XCTAssertEqual(definition.rateMetrics, ["requests_per_second"])

    let summary = try OpenRouterUsageClient.decodeAnalyticsSummary([
      "data": [
        "data": [
          ["request_count": 2, "usage": 1.25],
          ["request_count": 3, "usage": 0.75]
        ],
        "metadata": ["row_count": 2, "truncated": true]
      ]
    ], requestedMetrics: definition.metrics)
    XCTAssertEqual(summary.metricTotals["request_count"], 5)
    XCTAssertEqual(summary.metricTotals["usage"], 2)
    XCTAssertTrue(summary.truncated)
  }

  func testRecentCallsDecoderKeepsRowsDistinctAndAcceptsStringMetrics() throws {
    let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let rangeStart = observedAt.addingTimeInterval(-86_400)
    let duplicateRow: [String: Any] = [
      "generation_id": "gen-synthetic-one",
      "api_key_id": "batch-key",
      "date__hour": "2027-01-15T07:00:00Z",
      "total_usage": "0.0125",
      "tokens_total": "42"
    ]
    let page = try OpenRouterUsageClient.decodeRecentCallsPage(
      [
        "data": [
          "data": [
            duplicateRow,
            [
              "generation_id": "gen-synthetic-two",
              "api_key_id": "interactive-key",
              "date__hour": "2027-01-15T08:00:00Z",
              "total_usage": 0.025,
              "tokens_total": 84
            ],
            duplicateRow
          ],
          "metadata": ["row_count": "3", "truncated": true]
        ]
      ],
      requestedMetrics: ["total_usage", "tokens_total"],
      dimensions: ["generation_id", "api_key_id"],
      granularity: "hour",
      observedAt: observedAt,
      rangeStart: rangeStart,
      requestedLimit: 20
    )

    XCTAssertEqual(page.calls.map(\.id), ["gen-synthetic-two", "gen-synthetic-one"])
    XCTAssertEqual(page.calls.last?.usage, 0.0125)
    XCTAssertEqual(page.calls.last?.totalTokens, 42)
    XCTAssertEqual(page.returnedRowCount, 3)
    XCTAssertTrue(page.isTruncated)

    let emptyTruncated = try OpenRouterUsageClient.decodeRecentCallsPage(
      [
        "data": [
          "data": [],
          "metadata": ["row_count": 0, "truncated": true]
        ]
      ],
      requestedMetrics: ["request_count"],
      dimensions: ["generation_id"],
      granularity: "hour",
      observedAt: observedAt,
      rangeStart: rangeStart,
      requestedLimit: 20
    )
    XCTAssertTrue(emptyTruncated.calls.isEmpty)
    XCTAssertNotNil(emptyTruncated.truncationMessage)
  }

  func testRecentCallsDecoderRejectsInvalidOrConflictingGenerationRows() {
    let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let base: [String: Any] = [
      "data": [
        "data": [[
          "generation_id": "bad\ngeneration",
          "date__hour": "2027-01-15T08:00:00Z",
          "request_count": 1
        ]],
        "metadata": ["row_count": 1, "truncated": false]
      ]
    ]
    XCTAssertThrowsError(try OpenRouterUsageClient.decodeRecentCallsPage(
      base,
      requestedMetrics: ["request_count"],
      dimensions: ["generation_id"],
      granularity: "hour",
      observedAt: observedAt,
      rangeStart: observedAt.addingTimeInterval(-86_400),
      requestedLimit: 20
    ))

    let conflicting: [String: Any] = [
      "data": [
        "data": [
          [
            "generation_id": "gen-conflict",
            "date__hour": "2027-01-15T08:00:00Z",
            "request_count": 1
          ],
          [
            "generation_id": "gen-conflict",
            "date__hour": "2027-01-15T07:00:00Z",
            "request_count": 1
          ]
        ],
        "metadata": ["row_count": 2, "truncated": false]
      ]
    ]
    XCTAssertThrowsError(try OpenRouterUsageClient.decodeRecentCallsPage(
      conflicting,
      requestedMetrics: ["request_count"],
      dimensions: ["generation_id"],
      granularity: "hour",
      observedAt: observedAt,
      rangeStart: observedAt.addingTimeInterval(-86_400),
      requestedLimit: 20
    ))

    let negativeUsage: [String: Any] = [
      "data": [
        "data": [[
          "generation_id": "gen-negative",
          "date__hour": "2027-01-15T08:00:00Z",
          "total_usage": -0.01
        ]],
        "metadata": ["row_count": 1, "truncated": false]
      ]
    ]
    XCTAssertThrowsError(try OpenRouterUsageClient.decodeRecentCallsPage(
      negativeUsage,
      requestedMetrics: ["total_usage"],
      dimensions: ["generation_id"],
      granularity: "hour",
      observedAt: observedAt,
      rangeStart: observedAt.addingTimeInterval(-86_400),
      requestedLimit: 20
    ))
  }
}

final class ClaudeBridgeTests: XCTestCase {
  func testMissingRateLimitsDoesNotProduceUpdate() {
    let data = Data(#"{"cwd":"/private/project","session_id":"private"}"#.utf8)
    XCTAssertEqual(ClaudeStatusLineCodec.parse(data), .noRateLimits)
  }

  func testWindowsAreSanitizedAndMillisecondsAreRejected() throws {
    let data = Data(#"{"cwd":"/private/project","session_id":"private","rate_limits":{"five_hour":{"used_percentage":0,"resets_at":1800000000},"seven_day":{"used_percentage":100,"resets_at":1800000000000}}}"#.utf8)
    guard case .update(let update) = ClaudeStatusLineCodec.parse(data) else {
      return XCTFail("Expected a sanitized update")
    }
    XCTAssertEqual(update.fiveHour?.usedPercentage, 0)
    XCTAssertNil(update.sevenDay)
    let snapshot = try XCTUnwrap(ClaudeStatusLineCodec.merge(update, into: nil))
    let encoded = try JSONEncoder().encode(snapshot)
    let text = String(decoding: encoded, as: UTF8.self)
    XCTAssertFalse(text.contains("cwd"))
    XCTAssertFalse(text.contains("session"))
    XCTAssertFalse(text.contains("private"))
  }

  func testSingleWindowUpdateRetainsOtherWindowConservatively() throws {
    let old = ClaudeSanitizedSnapshot(
      observedAt: Date(timeIntervalSince1970: 100),
      fiveHour: ClaudeRateLimitWindowSnapshot(usedPercentage: 10, resetsAt: nil),
      sevenDay: ClaudeRateLimitWindowSnapshot(usedPercentage: 20, resetsAt: nil)
    )
    let update = ClaudeStatusLineUpdate(
      observedAt: Date(timeIntervalSince1970: 200),
      fiveHour: ClaudeRateLimitWindowSnapshot(usedPercentage: 30, resetsAt: nil),
      sevenDay: nil
    )
    let merged = try XCTUnwrap(ClaudeStatusLineCodec.merge(update, into: old))
    XCTAssertEqual(merged.fiveHour?.usedPercentage, 30)
    XCTAssertEqual(merged.sevenDay?.usedPercentage, 20)
    XCTAssertEqual(merged.observedAt, old.observedAt)
  }

  func testRepeatedIdenticalWindowsDoNotRenewFreshness() throws {
    let five = ClaudeRateLimitWindowSnapshot(usedPercentage: 10, resetsAt: nil)
    let seven = ClaudeRateLimitWindowSnapshot(usedPercentage: 20, resetsAt: nil)
    let old = ClaudeSanitizedSnapshot(
      observedAt: Date(timeIntervalSince1970: 100),
      fiveHour: five,
      sevenDay: seven
    )
    let repeated = ClaudeStatusLineUpdate(
      observedAt: Date(timeIntervalSince1970: 200),
      fiveHour: five,
      sevenDay: seven
    )
    XCTAssertEqual(try XCTUnwrap(ClaudeStatusLineCodec.merge(repeated, into: old)).observedAt, old.observedAt)
  }

  func testFreshnessBoundaries() {
    let now = Date(timeIntervalSince1970: 10_000)
    XCTAssertEqual(ClaudeUsageClient.freshness(of: now.addingTimeInterval(-900), now: now), .fresh)
    XCTAssertEqual(ClaudeUsageClient.freshness(of: now.addingTimeInterval(-901), now: now), .stale)
    XCTAssertEqual(ClaudeUsageClient.freshness(of: now.addingTimeInterval(-86_401), now: now), .expired)
    XCTAssertEqual(ClaudeUsageClient.freshness(of: now.addingTimeInterval(61), now: now), .invalidFuture)
  }

  func testSettingsConnectAndDisconnectRestorePriorCommand() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let settings = directory.appendingPathComponent("settings.json")
    let helper = directory.appendingPathComponent("helper")
    try Data("#!/bin/sh\n".utf8).write(to: helper)
    XCTAssertEqual(chmod(helper.path, 0o700), 0)
    let source = #"{"theme":"dark","statusLine":{"type":"command","command":"printf prior"}}"#
    try Data(source.utf8).write(to: settings)
    XCTAssertEqual(chmod(settings.path, 0o600), 0)

    let connect = try ClaudeSettingsPatcher.prepareConnect(helperURL: helper, settingsURL: settings)
    XCTAssertTrue(connect.summary.contains("Chain"))
    try ClaudeSettingsPatcher.apply(connect)
    let connected = try Data(contentsOf: settings)
    let connectedRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: connected) as? [String: Any])
    let connectedStatus = try XCTUnwrap(connectedRoot["statusLine"] as? [String: Any])
    XCTAssertTrue(ClaudeBridgeCommand.isBridgeCommand(try XCTUnwrap(connectedStatus["command"] as? String)))
    XCTAssertEqual(connectedRoot["theme"] as? String, "dark")

    let disconnect = try ClaudeSettingsPatcher.prepareDisconnect(settingsURL: settings)
    try ClaudeSettingsPatcher.apply(disconnect)
    let restored = try Data(contentsOf: settings)
    let restoredRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: restored) as? [String: Any])
    let restoredStatus = try XCTUnwrap(restoredRoot["statusLine"] as? [String: Any])
    XCTAssertEqual(restoredStatus["command"] as? String, "printf prior")
    XCTAssertEqual(restoredRoot["theme"] as? String, "dark")
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("dashis-claude-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: NSNumber(value: 0o700)]
    )
    return url
  }
}

final class GoogleQuotaTests: XCTestCase {
  func testManualModeDoesNotInventQuota() async {
    let snapshot = await GoogleConsumerUsageClient().fetchSnapshot(
      context: GoogleConsumerManualContext(observedAt: Date(timeIntervalSince1970: 100))
    )
    XCTAssertEqual(snapshot.sourceKind, .manualOnly)
    XCTAssertFalse(snapshot.hasData)
    XCTAssertFalse(snapshot.warnings.isEmpty)
  }

  func testManualModeDoesNotExposeOverflowedDerivedValues() async throws {
    let snapshot = await GoogleConsumerUsageClient().fetchSnapshot(
      context: GoogleConsumerManualContext(
        used: .greatestFiniteMagnitude,
        remaining: .greatestFiniteMagnitude
      )
    )
    let window = try XCTUnwrap(snapshot.windows.first)
    XCTAssertEqual(window.used, .greatestFiniteMagnitude)
    XCTAssertEqual(window.remaining, .greatestFiniteMagnitude)
    XCTAssertNil(window.limit)
    XCTAssertNil(window.usedPercentage)
    XCTAssertNil(window.remainingPercentage)
  }

  func testQuotaDecoderReadsStringLimit() throws {
    let page = try GoogleQuotaPayloadDecoder.decode([
      "quotaInfos": [[
        "quotaId": "GenerateRequestsPerMinute",
        "metric": "generativelanguage.googleapis.com/generate_content_requests_per_minute",
        "quotaDisplayName": "Generate requests",
        "metricUnit": "1/min",
        "refreshInterval": "minute",
        "dimensionsInfos": [[
          "dimensions": ["model": "gemini-test"],
          "details": ["value": "100"],
          "applicableLocations": ["global"]
        ]]
      ]]
    ])
    XCTAssertEqual(page.quotaInfos.first?.dimensionInfos.first?.effectiveLimit, 100)
  }

  func testDeltaUsageAggregatesAcrossMethodAndKeepsNegativeRemaining() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_050)
    let quota = GoogleQuotaInfo(
      quotaID: "GenerateRequestsPerMinute",
      metric: "generativelanguage.googleapis.com/generate_content_requests_per_minute",
      displayName: "Generate requests",
      metricUnit: "requests",
      refreshInterval: "60s",
      isPrecise: true,
      dimensionInfos: [GoogleQuotaDimensionInfo(
        dimensions: ["model": "gemini-test"],
        effectiveLimit: 100,
        applicableLocations: []
      )]
    )
    let metricType = "generativelanguage.googleapis.com/quota/generate_content_requests_per_minute/usage"
    let makeSeries: (String, Double) -> GoogleMonitoringSeries = { method, value in
      GoogleMonitoringSeries(
        metricType: metricType,
        metricKind: .delta,
        metricLabels: [
          "limit_name": quota.quotaID,
          "model": "gemini-test",
          "method": method
        ],
        resourceLabels: [:],
        points: [GoogleMonitoringPoint(
          start: now.addingTimeInterval(-50),
          end: now.addingTimeInterval(-10),
          value: value
        )]
      )
    }
    let result = GoogleQuotaDeriver.derive(
      quota: quota,
      limitSeries: [GoogleMonitoringSeries(
        metricType: "generativelanguage.googleapis.com/quota/generate_content_requests_per_minute/limit",
        metricKind: .gauge,
        metricLabels: ["limit_name": quota.quotaID, "model": "gemini-test"],
        resourceLabels: [:],
        points: [GoogleMonitoringPoint(start: nil, end: now.addingTimeInterval(-15), value: 100)]
      )],
      usageSeries: [makeSeries("generateContent", 60), makeSeries("streamGenerateContent", 50)],
      now: now
    )
    let window = try XCTUnwrap(result.windows.first)
    XCTAssertEqual(window.used, 110)
    XCTAssertEqual(window.limit, 100)
    XCTAssertEqual(window.remaining, -10)
    XCTAssertTrue(window.label.contains("as of"))
    XCTAssertTrue(result.warnings.contains { $0.id.contains("google-historical-window") })
  }

  func testUnknownRefreshDoesNotClaimRemaining() throws {
    let quota = GoogleQuotaInfo(
      quotaID: "UnknownRefresh",
      metric: "generativelanguage.googleapis.com/unknown_refresh",
      displayName: "Unknown refresh",
      metricUnit: "requests",
      refreshInterval: nil,
      isPrecise: nil,
      dimensionInfos: [GoogleQuotaDimensionInfo(dimensions: [:], effectiveLimit: 100, applicableLocations: [])]
    )
    let result = GoogleQuotaDeriver.derive(quota: quota, limitSeries: [], usageSeries: [], now: Date())
    XCTAssertNil(result.windows.first?.remaining)
    XCTAssertFalse(result.warnings.isEmpty)
  }

  func testPacificDailyResetUsesCalendarMidnight() throws {
    let cadence = try XCTUnwrap(GoogleQuotaCadence(refreshInterval: "86400s"))
    let now = try XCTUnwrap(ISO8601DateFormatter.providerStandard.date(from: "2026-07-11T12:00:00Z"))
    let reset = try XCTUnwrap(cadence.bounds(containing: now).reset)
    XCTAssertEqual(ISO8601DateFormatter.providerStandard.string(from: reset), "2026-07-12T07:00:00Z")
  }

  func testGoogleTokenExchangeUsesNoClientSecretAndPassesPolicy() throws {
    let redirect = try XCTUnwrap(URL(string: "http://127.0.0.1:54321/dashis/google/oauth/test-nonce"))
    let flow = try GoogleDesktopOAuth.makeAuthorizationFlow(
      clientID: "12345-example.apps.googleusercontent.com",
      redirectURI: redirect
    )
    let request = try GoogleDesktopOAuth.tokenExchangeRequest(
      authorizationCode: "synthetic-code",
      clientID: "12345-example.apps.googleusercontent.com",
      flow: flow
    )
    let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
    XCTAssertFalse(body.contains("client_secret"))
    XCTAssertTrue(ProviderEndpointPolicy.allows(request))
  }
}
