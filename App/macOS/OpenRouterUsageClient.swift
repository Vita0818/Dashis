import Foundation

enum OpenRouterRecentCallsState: Hashable, Sendable {
  case idle
  case loading
  case loaded(OpenRouterRecentCallsPage)
  case failed(String)
}

struct OpenRouterRecentCallsPage: Hashable, Sendable {
  let observedAt: Date
  let rangeStart: Date
  let rangeEnd: Date
  let granularity: String
  let requestedLimit: Int
  let returnedRowCount: Int
  let isTruncated: Bool
  let calls: [OpenRouterRecentCall]

  var truncationMessage: String? {
    guard isTruncated else { return nil }
    return "OpenRouter reported more rows than the selected-window result could include. The displayed metadata is incomplete (up to \(requestedLimit) rows)."
  }
}

struct OpenRouterRecentCall: Identifiable, Hashable, Sendable {
  let id: String
  let bucketStart: Date
  let apiKeyLabel: String?
  let model: String?
  let usage: Double?
  let totalTokens: Int?
}

struct OpenRouterUsageClient: ProviderUsageClient {
  struct ActivityFilter: Sendable {
    var date: String?
    var apiKeyHash: String?
    var userID: String?

    init(date: String? = nil, apiKeyHash: String? = nil, userID: String? = nil) {
      self.date = date
      self.apiKeyHash = apiKeyHash
      self.userID = userID
    }
  }

  struct ManagementContext: Sendable {
    let apiKey: String
    let generationID: String?
    let activityFilter: ActivityFilter
    let analyticsDays: Int

    init(
      apiKey: String,
      generationID: String? = nil,
      activityFilter: ActivityFilter = ActivityFilter(),
      analyticsDays: Int = 30
    ) {
      self.apiKey = apiKey
      self.generationID = generationID
      self.activityFilter = activityFilter
      self.analyticsDays = analyticsDays
    }
  }

  enum Context: Sendable {
    case apiKey(String)
    case management(ManagementContext)
  }

  struct KeySummary {
    let usage: Double?
    let limit: Double?
    let remaining: Double?
    let limitReset: String?
    let expiresAt: Date?
    let usageDaily: Double?
    let usageWeekly: Double?
    let usageMonthly: Double?
    let byokUsage: Double?
    let isFreeTier: Bool?
  }

  struct CreditsSummary {
    let totalCredits: Double?
    let totalUsage: Double?
    let remaining: Double?
  }

  struct ActivitySummary {
    let rowCount: Int
    let requests: Int
    let promptTokens: Int
    let completionTokens: Int
    let reasoningTokens: Int
    let usage: Double
    let modelCount: Int
    let totalTokens: Int
  }

  struct GenerationSummary {
    let totalTokens: Int
    let promptTokens: Int
    let completionTokens: Int
    let reasoningTokens: Int
    let usage: Double?
  }

  struct AnalyticsDefinition {
    struct Metric {
      let name: String
      let isRate: Bool
    }

    let metricDefinitions: [Metric]
    let dimensions: [String]
    let granularities: [String]

    var metrics: [String] {
      metricDefinitions.filter { !$0.isRate }.map(\.name)
    }

    var rateMetrics: [String] {
      metricDefinitions.filter(\.isRate).map(\.name)
    }
  }

  struct AnalyticsSummary {
    let rowCount: Int
    let truncated: Bool
    let queryTimeMilliseconds: Double?
    let metricTotals: [String: Double]
  }

  struct AnalyticsFetch {
    let summary: AnalyticsSummary?
    let warnings: [ProviderWarning]
    let failures: [ProviderFailure]
  }

  let providerID: ProviderID = .openRouter

  private let httpClient: ProviderHTTPClient
  private let now: @Sendable () -> Date

  init(
    httpClient: ProviderHTTPClient = ProviderHTTPClient(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.httpClient = httpClient
    self.now = now
  }

  func fetchSnapshot(context: Context) async -> ProviderSnapshot {
    switch context {
    case .apiKey(let apiKey):
      return await fetchAPIKeySnapshot(apiKey: apiKey)
    case .management(let context):
      return await fetchManagementSnapshot(context: context)
    }
  }

  func fetchAPIKeySnapshot(apiKey: String) async -> ProviderSnapshot {
    let observedAt = now()
    let scope = ProviderScope(kind: .apiKey, label: "OpenRouter API key")
    guard Self.hasCredential(apiKey) else {
      return Self.failureSnapshot(
        scope: scope,
        observedAt: observedAt,
        operation: "openrouter.key.auth",
        error: OpenRouterUsageClientError.missingAPIKey
      )
    }

    do {
      let json = try await requestJSON(
        path: "/api/v1/key",
        apiKey: apiKey,
        operation: "openrouter.key"
      )
      let summary = try Self.decodeKey(json)
      let balance = ProviderBalance(
        label: "Key spending limit",
        used: summary.usage,
        limit: summary.limit,
        remaining: summary.remaining,
        unit: "credits",
        resetDescription: summary.limitReset
      )
      let window = Self.keyQuotaWindow(from: summary)
      var warnings: [ProviderWarning] = []
      if let expiresAt = summary.expiresAt, expiresAt <= observedAt {
        warnings.append(ProviderWarning(id: "openrouter-key-expired", message: "This OpenRouter API key has expired."))
      }
      if summary.isFreeTier == true {
        warnings.append(
          ProviderWarning(
            id: "openrouter-free-tier",
            message: "OpenRouter reports this as a free-tier key; model-specific request limits can still apply."
          )
        )
      }

      var metrics: [ProviderMetric] = []
      Self.appendMetric(&metrics, key: "usage_daily", label: "Daily usage", value: summary.usageDaily, unit: "credits")
      Self.appendMetric(&metrics, key: "usage_weekly", label: "Weekly usage", value: summary.usageWeekly, unit: "credits")
      Self.appendMetric(&metrics, key: "usage_monthly", label: "Monthly usage", value: summary.usageMonthly, unit: "credits")
      Self.appendMetric(&metrics, key: "byok_usage", label: "BYOK usage", value: summary.byokUsage, unit: "credits")

      return ProviderSnapshot(
        providerID: providerID,
        scope: scope,
        sourceKind: .officialDirect,
        observedAt: observedAt,
        windows: window.map { [$0] } ?? [],
        balance: balance,
        metrics: metrics,
        warnings: warnings,
        partialFailures: []
      )
    } catch {
      return Self.failureSnapshot(
        scope: scope,
        observedAt: observedAt,
        operation: "openrouter.key",
        error: error
      )
    }
  }

  func fetchRecentCalls(
    apiKey: String,
    days: Int = 1,
    limit: Int = 20
  ) async throws -> OpenRouterRecentCallsPage {
    guard Self.hasCredential(apiKey) else {
      throw OpenRouterUsageClientError.missingManagementKey
    }

    let observedAt = now()
    let metaJSON = try await requestJSON(
      path: "/api/v1/analytics/meta",
      apiKey: apiKey,
      operation: "openrouter.recent-calls.meta"
    )
    let definition = try Self.decodeAnalyticsDefinition(metaJSON)
    guard definition.dimensions.contains("generation_id") else {
      throw OpenRouterUsageClientError.recentCallsUnavailable
    }

    let usageMetric = ["total_usage", "usage"].first(where: definition.metrics.contains)
    let tokenMetric = ["tokens_total", "total_tokens"].first(where: definition.metrics.contains)
    var requestedMetrics = [usageMetric, tokenMetric].compactMap { $0 }
    if requestedMetrics.isEmpty, definition.metrics.contains("request_count") {
      requestedMetrics = ["request_count"]
    }
    guard !requestedMetrics.isEmpty else {
      throw OpenRouterUsageClientError.recentCallsUnavailable
    }

    var dimensions = ["generation_id"]
    if definition.dimensions.contains("api_key_id") {
      dimensions.append("api_key_id")
    } else if definition.dimensions.contains("model") {
      dimensions.append("model")
    }
    let granularity: String
    if definition.granularities.contains("hour") {
      granularity = "hour"
    } else if definition.granularities.contains("day") {
      granularity = "day"
    } else {
      throw OpenRouterUsageClientError.recentCallsUnavailable
    }

    let safeDays = max(1, min(days, 30))
    let safeLimit = max(1, min(limit, 20))
    let rangeStart = observedAt.addingTimeInterval(Double(-safeDays * 86_400))
    let body = try JSONSerialization.data(withJSONObject: [
      "metrics": requestedMetrics,
      "dimensions": dimensions,
      "granularity": granularity,
      "group_limit": 1,
      "limit": safeLimit,
      "time_range": [
        "start": ISO8601DateFormatter.providerStandard.string(from: rangeStart),
        "end": ISO8601DateFormatter.providerStandard.string(from: observedAt)
      ]
    ])
    let json = try await requestJSON(
      path: "/api/v1/analytics/query",
      method: "POST",
      apiKey: apiKey,
      body: body,
      operation: "openrouter.recent-calls.query"
    )
    return try Self.decodeRecentCallsPage(
      json,
      requestedMetrics: requestedMetrics,
      dimensions: dimensions,
      granularity: granularity,
      observedAt: observedAt,
      rangeStart: rangeStart,
      requestedLimit: safeLimit
    )
  }

  func fetchManagementSnapshot(context: ManagementContext) async -> ProviderSnapshot {
    let observedAt = now()
    let scope = ProviderScope.workspace("OpenRouter account")
    guard Self.hasCredential(context.apiKey) else {
      return Self.failureSnapshot(
        scope: scope,
        observedAt: observedAt,
        operation: "openrouter.management.auth",
        error: OpenRouterUsageClientError.missingManagementKey
      )
    }

    let activityURL = Result { try Self.activityURL(filter: context.activityFilter) }

    async let creditsResult: Result<Any, Error> = captureProviderResult {
      return try await requestJSON(
        path: "/api/v1/credits",
        apiKey: context.apiKey,
        operation: "openrouter.credits"
      )
    }
    async let activityResult: Result<Any, Error> = captureProviderResult {
      let url = try activityURL.get()
      return try await requestJSON(
        url: url,
        apiKey: context.apiKey,
        operation: "openrouter.activity"
      )
    }
    async let analyticsFetch = fetchAnalytics(
      apiKey: context.apiKey,
      days: context.analyticsDays,
      observedAt: observedAt
    )

    var generationResult: Result<Any, Error>?
    var preflightFailures: [ProviderFailure] = []
    if let rawGenerationID = context.generationID?.trimmingCharacters(in: .whitespacesAndNewlines),
       !rawGenerationID.isEmpty {
      if ProviderEndpointPolicy.isOpenRouterGenerationID(rawGenerationID) {
        do {
          let generationURL = try Self.generationURL(id: rawGenerationID)
          generationResult = await captureProviderResult {
            try await requestJSON(
              url: generationURL,
              apiKey: context.apiKey,
              operation: "openrouter.generation"
            )
          }
        } catch {
          preflightFailures.append(
            ProviderFailure(operation: "openrouter.generation", message: ProviderJSON.safeMessage(error))
          )
        }
      } else {
        preflightFailures.append(
          ProviderFailure(
            operation: "openrouter.generation",
            message: ProviderJSON.safeMessage(OpenRouterUsageClientError.invalidGenerationID)
          )
        )
      }
    }

    let credits = await creditsResult
    let activity = await activityResult
    let analytics = await analyticsFetch
    var balance: ProviderBalance?
    var metrics: [ProviderMetric] = []
    let warnings = analytics.warnings
    var failures = preflightFailures + analytics.failures

    switch credits {
    case .success(let json):
      do {
        let summary = try Self.decodeCredits(json)
        balance = ProviderBalance(
          label: "Account credits",
          used: summary.totalUsage,
          limit: summary.totalCredits,
          remaining: summary.remaining,
          unit: "credits",
          resetDescription: nil
        )
      } catch {
        failures.append(ProviderFailure(operation: "openrouter.credits", message: ProviderJSON.safeMessage(error)))
      }
    case .failure(let error):
      failures.append(ProviderFailure(operation: "openrouter.credits", message: ProviderJSON.safeMessage(error)))
    }

    switch activity {
    case .success(let json):
      do {
        let summary = try Self.decodeActivity(json)
        metrics.append(contentsOf: [
          ProviderMetric(key: "activity_rows", label: "Activity groups", value: Double(summary.rowCount), unit: "groups"),
          ProviderMetric(key: "requests", label: "Requests", value: Double(summary.requests), unit: "requests"),
          ProviderMetric(key: "total_tokens", label: "Total tokens", value: Double(summary.totalTokens), unit: "tokens"),
          ProviderMetric(key: "prompt_tokens", label: "Prompt tokens", value: Double(summary.promptTokens), unit: "tokens"),
          ProviderMetric(key: "completion_tokens", label: "Completion tokens", value: Double(summary.completionTokens), unit: "tokens"),
          ProviderMetric(key: "reasoning_tokens", label: "Reasoning breakdown", value: Double(summary.reasoningTokens), unit: "tokens"),
          ProviderMetric(key: "activity_usage", label: "Activity usage", value: summary.usage, unit: "credits"),
          ProviderMetric(key: "models", label: "Models", value: Double(summary.modelCount), unit: "models")
        ])
      } catch {
        failures.append(ProviderFailure(operation: "openrouter.activity", message: ProviderJSON.safeMessage(error)))
      }
    case .failure(let error):
      failures.append(ProviderFailure(operation: "openrouter.activity", message: ProviderJSON.safeMessage(error)))
    }

    if let summary = analytics.summary {
      metrics.append(
        ProviderMetric(key: "analytics_rows", label: "Analytics groups", value: Double(summary.rowCount), unit: "groups")
      )
      Self.appendMetric(
        &metrics,
        key: "analytics_query_time",
        label: "Analytics query time",
        value: summary.queryTimeMilliseconds,
        unit: "ms"
      )
      for name in summary.metricTotals.keys.sorted() {
        guard let value = summary.metricTotals[name] else { continue }
        metrics.append(
          ProviderMetric(
            key: "analytics_\(name)",
            label: "Analytics \(Self.displayLabel(for: name))",
            value: value,
            unit: Self.analyticsUnit(for: name)
          )
        )
      }
    }

    if let generationResult {
      switch generationResult {
      case .success(let json):
        do {
          let generation = try Self.decodeGeneration(json)
          metrics.append(contentsOf: [
            ProviderMetric(
              key: "generation_total_tokens",
              label: "Generation total tokens",
              value: Double(generation.totalTokens),
              unit: "tokens"
            ),
            ProviderMetric(
              key: "generation_reasoning_tokens",
              label: "Generation reasoning breakdown",
              value: Double(generation.reasoningTokens),
              unit: "tokens"
            )
          ])
          Self.appendMetric(
            &metrics,
            key: "generation_usage",
            label: "Generation usage",
            value: generation.usage,
            unit: "credits"
          )
        } catch {
          failures.append(ProviderFailure(operation: "openrouter.generation", message: ProviderJSON.safeMessage(error)))
        }
      case .failure(let error):
        failures.append(ProviderFailure(operation: "openrouter.generation", message: ProviderJSON.safeMessage(error)))
      }
    }

    return ProviderSnapshot(
      providerID: providerID,
      scope: scope,
      sourceKind: .officialDirect,
      observedAt: observedAt,
      windows: [],
      balance: balance,
      metrics: metrics,
      warnings: warnings,
      partialFailures: failures
    )
  }

  func exchangeAuthorizationCode(code: String, codeVerifier: String) async throws -> String {
    guard Self.validOAuthValue(code, maximumLength: 2_048) else {
      throw OpenRouterUsageClientError.invalidAuthorizationCode
    }
    guard codeVerifier.count >= 43,
          codeVerifier.count <= 128,
          codeVerifier.range(of: #"^[A-Za-z0-9._~-]+$"#, options: .regularExpression) != nil
    else {
      throw OpenRouterUsageClientError.invalidCodeVerifier
    }

    let body = try JSONSerialization.data(withJSONObject: [
      "code": code,
      "code_verifier": codeVerifier,
      "code_challenge_method": "S256"
    ])
    var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/auth/keys")!)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let json = try await httpClient.json(for: request, operation: "openrouter.oauth.exchange")
    let root = ProviderJSON.dictionary(json)
    let data = ProviderJSON.dictionary(root["data"])
    guard let key = (root["key"] ?? data["key"]) as? String,
          Self.hasCredential(key),
          key.count <= 4_096
    else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    return key
  }

  static func decodeKey(_ json: Any) throws -> KeySummary {
    let root = ProviderJSON.dictionary(json)
    guard let data = root["data"] as? [String: Any] else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    let usage = ProviderJSON.number(data["usage"])
    let limit = ProviderJSON.number(data["limit"])
    let explicitRemaining = ProviderJSON.number(data["limit_remaining"] ?? data["limitRemaining"])
    guard usage != nil || limit != nil || explicitRemaining != nil else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    let remaining = explicitRemaining ?? limit.flatMap { limit in usage.map { limit - $0 } }

    return KeySummary(
      usage: usage,
      limit: limit,
      remaining: remaining,
      limitReset: ProviderJSON.string(data["limit_reset"] ?? data["limitReset"]),
      expiresAt: Self.parseDate(data["expires_at"] ?? data["expiresAt"]),
      usageDaily: ProviderJSON.number(data["usage_daily"] ?? data["usageDaily"]),
      usageWeekly: ProviderJSON.number(data["usage_weekly"] ?? data["usageWeekly"]),
      usageMonthly: ProviderJSON.number(data["usage_monthly"] ?? data["usageMonthly"]),
      byokUsage: ProviderJSON.number(data["byok_usage"] ?? data["byokUsage"]),
      isFreeTier: ProviderJSON.bool(data["is_free_tier"] ?? data["isFreeTier"])
    )
  }

  static func decodeCredits(_ json: Any) throws -> CreditsSummary {
    let root = ProviderJSON.dictionary(json)
    guard let data = root["data"] as? [String: Any] else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    let totalCredits = ProviderJSON.number(data["total_credits"] ?? data["totalCredits"])
    let totalUsage = ProviderJSON.number(data["total_usage"] ?? data["totalUsage"])
    let explicitRemaining = ProviderJSON.number(
      data["remaining_credits"] ?? data["remainingCredits"] ?? data["limit_remaining"]
    )
    guard totalCredits != nil || totalUsage != nil || explicitRemaining != nil else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    let remaining = explicitRemaining ?? totalCredits.flatMap { total in totalUsage.map { total - $0 } }
    return CreditsSummary(totalCredits: totalCredits, totalUsage: totalUsage, remaining: remaining)
  }

  static func decodeActivity(_ json: Any) throws -> ActivitySummary {
    guard let root = json as? [String: Any] else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    guard let rawRows = root["data"] as? [Any] else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }

    var requests = 0
    var promptTokens = 0
    var completionTokens = 0
    var reasoningTokens = 0
    var totalTokens = 0
    var usage: Double = 0
    var models = Set<String>()
    for rawRow in rawRows {
      guard let row = rawRow as? [String: Any] else {
        throw OpenRouterUsageClientError.invalidProviderResponse
      }
      let recognizedKeys: Set<String> = [
        "requests", "prompt_tokens", "tokens_prompt", "completion_tokens", "tokens_completion",
        "reasoning_tokens", "tokens_reasoning", "total_tokens", "tokens_total", "usage",
        "model", "model_permaslug", "date", "endpoint"
      ]
      guard !recognizedKeys.isDisjoint(with: row.keys) else {
        throw OpenRouterUsageClientError.invalidProviderResponse
      }
      try add(try strictInt(row, aliases: ["requests"]) ?? 0, to: &requests)
      let rowPrompt = try strictInt(row, aliases: ["prompt_tokens", "tokens_prompt"]) ?? 0
      let rowCompletion = try strictInt(row, aliases: ["completion_tokens", "tokens_completion"]) ?? 0
      try add(rowPrompt, to: &promptTokens)
      try add(rowCompletion, to: &completionTokens)
      try add(
        try strictInt(row, aliases: ["reasoning_tokens", "tokens_reasoning"]) ?? 0,
        to: &reasoningTokens
      )
      let fallbackTotal = try adding(rowPrompt, rowCompletion)
      try add(
        try strictInt(row, aliases: ["total_tokens", "tokens_total"]) ?? fallbackTotal,
        to: &totalTokens
      )
      let rowUsage = try strictNumber(row, aliases: ["usage"]) ?? 0
      let updatedUsage = usage + rowUsage
      guard updatedUsage.isFinite else { throw OpenRouterUsageClientError.invalidProviderResponse }
      usage = updatedUsage
      if let rawModel = aliasedValue(row, aliases: ["model", "model_permaslug"]) {
        guard let model = rawModel as? String,
              model.count <= 512,
              !model.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
          throw OpenRouterUsageClientError.invalidProviderResponse
        }
        if !model.isEmpty {
        models.insert(model)
        }
      }
    }
    return ActivitySummary(
      rowCount: rawRows.count,
      requests: requests,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      reasoningTokens: reasoningTokens,
      usage: usage,
      modelCount: models.count,
      totalTokens: totalTokens
    )
  }

  static func decodeGeneration(_ json: Any) throws -> GenerationSummary {
    guard let root = json as? [String: Any] else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    let data: [String: Any]
    if let nested = root["data"] as? [String: Any] {
      data = nested
    } else if !root.isEmpty {
      data = root
    } else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    let tokenKeys: Set<String> = [
      "native_tokens_prompt", "tokens_prompt", "prompt_tokens",
      "native_tokens_completion", "tokens_completion", "completion_tokens",
      "native_tokens_reasoning", "reasoning_tokens", "total_tokens", "tokens_total"
    ]
    guard !tokenKeys.isDisjoint(with: data.keys) else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    let prompt = try strictInt(
      data,
      aliases: ["native_tokens_prompt", "tokens_prompt", "prompt_tokens"]
    ) ?? 0
    let completion = try strictInt(
      data,
      aliases: ["native_tokens_completion", "tokens_completion", "completion_tokens"]
    ) ?? 0
    let reasoning = try strictInt(
      data,
      aliases: ["native_tokens_reasoning", "reasoning_tokens"]
    ) ?? 0
    let total = try strictInt(data, aliases: ["total_tokens", "tokens_total"])
      ?? adding(prompt, completion)
    let usage = try strictNumber(data, aliases: ["usage", "total_cost"])
    return GenerationSummary(
      totalTokens: total,
      promptTokens: prompt,
      completionTokens: completion,
      reasoningTokens: reasoning,
      usage: usage
    )
  }

  static func decodeAnalyticsDefinition(_ json: Any) throws -> AnalyticsDefinition {
    guard let root = json as? [String: Any] else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    guard let data = root["data"] as? [String: Any] else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    guard let rawMetrics = data["metrics"] as? [Any] else {
      throw OpenRouterUsageClientError.analyticsMetadataUnavailable
    }
    var metrics: [AnalyticsDefinition.Metric] = []
    for rawMetric in rawMetrics {
      guard let metric = rawMetric as? [String: Any],
            let name = metric["name"] as? String,
            ProviderEndpointPolicy.sanitizeIdentifier(name) == name,
            !metrics.contains(where: { $0.name == name }),
            let isRate = ProviderJSON.bool(metric["is_rate"] ?? metric["isRate"])
      else {
        continue
      }
      metrics.append(AnalyticsDefinition.Metric(name: name, isRate: isRate))
    }
    guard metrics.contains(where: { !$0.isRate }) else {
      throw OpenRouterUsageClientError.analyticsMetadataUnavailable
    }
    return AnalyticsDefinition(
      metricDefinitions: metrics,
      dimensions: decodeMetaNames(data["dimensions"]),
      granularities: decodeMetaNames(data["granularities"])
    )
  }

  static func decodeAnalyticsSummary(_ json: Any, requestedMetrics: [String]) throws -> AnalyticsSummary {
    guard let root = json as? [String: Any] else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    guard let data = root["data"] as? [String: Any],
          let rows = data["data"] as? [Any]
    else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    let rawMetadata = data["metadata"] ?? root["metadata"]
    guard let metadata = rawMetadata as? [String: Any],
          let rowCount = try strictInt(metadata, aliases: ["row_count", "rowCount"]),
          rowCount >= 0,
          let truncatedRaw = aliasedValue(metadata, aliases: ["truncated"]),
          let truncated = ProviderJSON.bool(truncatedRaw)
    else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    var totals: [String: Double] = [:]
    for metric in requestedMetrics {
      var total: Double = 0
      for rawRow in rows {
        guard let row = rawRow as? [String: Any],
              row.keys.contains(metric),
              let value = ProviderJSON.number(row[metric])
        else {
          throw OpenRouterUsageClientError.invalidProviderResponse
        }
        let updated = total + value
        guard updated.isFinite else { throw OpenRouterUsageClientError.invalidProviderResponse }
        total = updated
      }
      totals[metric] = total
    }
    let queryTime = try strictNumber(metadata, aliases: ["query_time_ms", "queryTimeMs"])
    return AnalyticsSummary(
      rowCount: rowCount,
      truncated: truncated,
      queryTimeMilliseconds: queryTime,
      metricTotals: totals
    )
  }

  static func decodeRecentCallsPage(
    _ json: Any,
    requestedMetrics: [String],
    dimensions: [String],
    granularity: String,
    observedAt: Date,
    rangeStart: Date,
    requestedLimit: Int
  ) throws -> OpenRouterRecentCallsPage {
    guard let root = json as? [String: Any],
          let data = root["data"] as? [String: Any],
          let rows = data["data"] as? [Any]
    else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    let rawMetadata = data["metadata"] ?? root["metadata"]
    guard let metadata = rawMetadata as? [String: Any],
          let rowCount = try strictInt(metadata, aliases: ["row_count", "rowCount"]),
          rowCount >= 0,
          let truncatedRaw = aliasedValue(metadata, aliases: ["truncated"]),
          let truncated = ProviderJSON.bool(truncatedRaw),
          (1...2).contains(requestedMetrics.count),
          Set(requestedMetrics).count == requestedMetrics.count,
          requestedMetrics.allSatisfy({
            ["total_usage", "usage", "tokens_total", "total_tokens", "request_count"].contains($0)
          }),
          (1...2).contains(dimensions.count),
          dimensions.first == "generation_id",
          Set(dimensions).count == dimensions.count,
          dimensions.dropFirst().allSatisfy({ ["api_key_id", "model"].contains($0) }),
          ["hour", "day"].contains(granularity),
          (1...20).contains(requestedLimit),
          rows.count <= requestedLimit
    else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }

    let timeKeys = ["date__\(granularity)", "created_at__\(granularity)"]
    let usageMetric = ["total_usage", "usage"].first(where: requestedMetrics.contains)
    let tokenMetric = ["tokens_total", "total_tokens"].first(where: requestedMetrics.contains)
    var calls: [OpenRouterRecentCall] = []
    var callsByID: [String: OpenRouterRecentCall] = [:]

    for rawRow in rows {
      guard let row = rawRow as? [String: Any],
            let generationID = row["generation_id"] as? String,
            ProviderEndpointPolicy.isOpenRouterGenerationID(generationID),
            let rawBucket = aliasedValue(row, aliases: timeKeys),
            let bucketStart = ProviderJSON.date(rawBucket)
      else {
        throw OpenRouterUsageClientError.invalidProviderResponse
      }

      for metric in requestedMetrics {
        guard row.keys.contains(metric),
              let value = ProviderJSON.number(row[metric]),
              value >= 0
        else {
          throw OpenRouterUsageClientError.invalidProviderResponse
        }
      }
      let usage = try usageMetric.flatMap { try strictNumber(row, aliases: [$0]) }
      let totalTokens = try tokenMetric.flatMap { metric -> Int? in
        guard let value = try strictInt(row, aliases: [metric]), value >= 0 else {
          throw OpenRouterUsageClientError.invalidProviderResponse
        }
        return value
      }
      let apiKeyLabel = dimensions.contains("api_key_id")
        ? try optionalBoundedString(row["api_key_id"], maximumLength: 512)
        : nil
      let model = dimensions.contains("model")
        ? try optionalBoundedString(row["model"], maximumLength: 512)
        : nil
      let call = OpenRouterRecentCall(
        id: generationID,
        bucketStart: bucketStart,
        apiKeyLabel: apiKeyLabel,
        model: model,
        usage: usage,
        totalTokens: totalTokens
      )
      if let existing = callsByID[generationID] {
        guard existing == call else {
          throw OpenRouterUsageClientError.invalidProviderResponse
        }
        continue
      }
      callsByID[generationID] = call
      calls.append(call)
    }

    calls.sort {
      if $0.bucketStart == $1.bucketStart { return $0.id < $1.id }
      return $0.bucketStart > $1.bucketStart
    }
    return OpenRouterRecentCallsPage(
      observedAt: observedAt,
      rangeStart: rangeStart,
      rangeEnd: observedAt,
      granularity: granularity,
      requestedLimit: requestedLimit,
      returnedRowCount: rowCount,
      isTruncated: truncated,
      calls: calls
    )
  }

  private func fetchAnalytics(apiKey: String, days: Int, observedAt: Date) async -> AnalyticsFetch {
    let metaJSON: Any
    do {
      metaJSON = try await requestJSON(
        path: "/api/v1/analytics/meta",
        apiKey: apiKey,
        operation: "openrouter.analytics.meta"
      )
    } catch {
      return AnalyticsFetch(
        summary: nil,
        warnings: [],
        failures: [
          ProviderFailure(operation: "openrouter.analytics.meta", message: ProviderJSON.safeMessage(error))
        ]
      )
    }

    let definition: AnalyticsDefinition
    do {
      definition = try Self.decodeAnalyticsDefinition(metaJSON)
    } catch {
      return AnalyticsFetch(
        summary: nil,
        warnings: [],
        failures: [
          ProviderFailure(operation: "openrouter.analytics.meta", message: ProviderJSON.safeMessage(error))
        ]
      )
    }

    let requestedMetrics = Self.selectAnalyticsMetrics(from: definition.metrics)
    guard !requestedMetrics.isEmpty else {
      return AnalyticsFetch(
        summary: nil,
        warnings: [],
        failures: [
          ProviderFailure(
            operation: "openrouter.analytics.meta",
            message: ProviderJSON.safeMessage(OpenRouterUsageClientError.analyticsMetadataUnavailable)
          )
        ]
      )
    }

    var metadataWarnings: [ProviderWarning] = []
    if !definition.rateMetrics.isEmpty {
      metadataWarnings.append(
        ProviderWarning(
          id: "openrouter-analytics-rate-excluded",
          message: "OpenRouter rate metrics were excluded because rates cannot be safely summed across grouped rows."
        )
      )
    }

    let safeDays = max(1, min(days, 90))
    do {
      let initial = try await queryAnalytics(
        apiKey: apiKey,
        requestedMetrics: requestedMetrics,
        definition: definition,
        days: safeDays,
        observedAt: observedAt,
        operation: "openrouter.analytics.query"
      )
      guard initial.truncated else {
        return AnalyticsFetch(summary: initial, warnings: metadataWarnings, failures: [])
      }

      guard safeDays > 1 else {
        metadataWarnings.append(
          ProviderWarning(
            id: "openrouter-analytics-truncated",
            message: "OpenRouter truncated the one-day analytics result; totals remain incomplete."
          )
        )
        return AnalyticsFetch(summary: initial, warnings: metadataWarnings, failures: [])
      }

      let retryDays = max(1, safeDays / 2)
      do {
        let retry = try await queryAnalytics(
          apiKey: apiKey,
          requestedMetrics: requestedMetrics,
          definition: definition,
          days: retryDays,
          observedAt: observedAt,
          operation: "openrouter.analytics.query.retry"
        )
        metadataWarnings.append(
          ProviderWarning(
            id: "openrouter-analytics-window-reduced",
            message: retry.truncated
              ? "OpenRouter still truncated analytics after Dashis retried a narrower \(retryDays)-day window; totals remain incomplete."
              : "OpenRouter truncated the requested window, so Dashis retried and displayed a narrower \(retryDays)-day total."
          )
        )
        return AnalyticsFetch(summary: retry, warnings: metadataWarnings, failures: [])
      } catch {
        metadataWarnings.append(
          ProviderWarning(
            id: "openrouter-analytics-truncated",
            message: "OpenRouter truncated the analytics result; the automatic narrower retry failed, so totals remain incomplete."
          )
        )
        return AnalyticsFetch(
          summary: initial,
          warnings: metadataWarnings,
          failures: [
            ProviderFailure(
              operation: "openrouter.analytics.query.retry",
              message: ProviderJSON.safeMessage(error)
            )
          ]
        )
      }
    } catch {
      return AnalyticsFetch(
        summary: nil,
        warnings: metadataWarnings,
        failures: [
          ProviderFailure(operation: "openrouter.analytics.query", message: ProviderJSON.safeMessage(error))
        ]
      )
    }
  }

  private func queryAnalytics(
    apiKey: String,
    requestedMetrics: [String],
    definition: AnalyticsDefinition,
    days: Int,
    observedAt: Date,
    operation: String
  ) async throws -> AnalyticsSummary {
    let start = observedAt.addingTimeInterval(Double(-days * 86_400))
    var payload: [String: Any] = [
      "metrics": requestedMetrics,
      "limit": 1_000,
      "time_range": [
        "start": ISO8601DateFormatter.providerStandard.string(from: start),
        "end": ISO8601DateFormatter.providerStandard.string(from: observedAt)
      ]
    ]
    if definition.dimensions.contains("model") {
      payload["dimensions"] = ["model"]
    }
    if definition.granularities.contains("day") {
      payload["granularity"] = "day"
    }
    let body = try JSONSerialization.data(withJSONObject: payload)
    let json = try await requestJSON(
      path: "/api/v1/analytics/query",
      method: "POST",
      apiKey: apiKey,
      body: body,
      operation: operation
    )
    return try Self.decodeAnalyticsSummary(json, requestedMetrics: requestedMetrics)
  }

  private func requestJSON(
    path: String,
    method: String = "GET",
    apiKey: String,
    body: Data? = nil,
    operation: String
  ) async throws -> Any {
    guard let url = URL(string: "https://openrouter.ai\(path)") else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    return try await requestJSON(
      url: url,
      method: method,
      apiKey: apiKey,
      body: body,
      operation: operation
    )
  }

  private func requestJSON(
    url: URL,
    method: String = "GET",
    apiKey: String,
    body: Data? = nil,
    operation: String
  ) async throws -> Any {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Dashis", forHTTPHeaderField: "X-OpenRouter-Title")
    if body != nil {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    return try await httpClient.json(for: request, operation: operation)
  }

  private static func keyQuotaWindow(from summary: KeySummary) -> QuotaWindow? {
    guard summary.limit != nil || summary.remaining != nil else { return nil }
    let usedPercentage: Double? = summary.limit.flatMap { limit -> Double? in
      guard limit > 0, let usage = summary.usage else { return nil }
      return usage / limit * 100
    }
    let remainingPercentage: Double? = summary.limit.flatMap { limit -> Double? in
      guard limit > 0, let remaining = summary.remaining else { return nil }
      return remaining / limit * 100
    }
    return QuotaWindow(
      id: "key-spending-limit",
      label: "Key spending limit",
      used: summary.usage,
      limit: summary.limit,
      remaining: summary.remaining,
      usedPercentage: usedPercentage,
      remainingPercentage: remainingPercentage,
      resetsAt: nil,
      unit: "credits",
      isEstimated: false
    )
  }

  private static func activityURL(filter: ActivityFilter) throws -> URL {
    var components = URLComponents(string: "https://openrouter.ai/api/v1/activity")!
    var queryItems: [URLQueryItem] = []
    if let date = filter.date?.trimmingCharacters(in: .whitespacesAndNewlines), !date.isEmpty {
      guard date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
        throw OpenRouterUsageClientError.invalidActivityFilter
      }
      queryItems.append(URLQueryItem(name: "date", value: date))
    }
    if let hash = filter.apiKeyHash?.trimmingCharacters(in: .whitespacesAndNewlines), !hash.isEmpty {
      guard hash.range(of: #"^[a-f0-9]{64}$"#, options: [.regularExpression, .caseInsensitive]) != nil else {
        throw OpenRouterUsageClientError.invalidActivityFilter
      }
      queryItems.append(URLQueryItem(name: "api_key_hash", value: hash))
    }
    if let userID = filter.userID?.trimmingCharacters(in: .whitespacesAndNewlines), !userID.isEmpty {
      guard ProviderEndpointPolicy.sanitizeIdentifier(userID) == userID else {
        throw OpenRouterUsageClientError.invalidActivityFilter
      }
      queryItems.append(URLQueryItem(name: "user_id", value: userID))
    }
    components.queryItems = queryItems.isEmpty ? nil : queryItems
    guard let url = components.url else { throw OpenRouterUsageClientError.invalidActivityFilter }
    return url
  }

  private static func generationURL(id: String) throws -> URL {
    guard ProviderEndpointPolicy.isOpenRouterGenerationID(id) else {
      throw OpenRouterUsageClientError.invalidGenerationID
    }
    var components = URLComponents(string: "https://openrouter.ai/api/v1/generation")!
    components.queryItems = [URLQueryItem(name: "id", value: id)]
    guard let url = components.url else { throw OpenRouterUsageClientError.invalidGenerationID }
    return url
  }

  private static func decodeMetaNames(_ value: Any?) -> [String] {
    var names: [String] = []
    for item in ProviderJSON.array(value) {
      let candidate: String?
      if let string = item as? String {
        candidate = string
      } else {
        candidate = ProviderJSON.string(ProviderJSON.dictionary(item)["name"])
      }
      guard let name = candidate,
            ProviderEndpointPolicy.sanitizeIdentifier(name) == name,
            !names.contains(name)
      else {
        continue
      }
      names.append(name)
    }
    return names
  }

  private static func aliasedValue(_ object: [String: Any], aliases: [String]) -> Any? {
    for alias in aliases where object.keys.contains(alias) {
      return object[alias]
    }
    return nil
  }

  private static func strictInt(_ object: [String: Any], aliases: [String]) throws -> Int? {
    guard let raw = aliasedValue(object, aliases: aliases) else { return nil }
    guard let value = ProviderJSON.int(raw) else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    return value
  }

  private static func strictNumber(_ object: [String: Any], aliases: [String]) throws -> Double? {
    guard let raw = aliasedValue(object, aliases: aliases) else { return nil }
    guard let value = ProviderJSON.number(raw) else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    return value
  }

  private static func optionalBoundedString(
    _ value: Any?,
    maximumLength: Int
  ) throws -> String? {
    guard let value, !(value is NSNull) else { return nil }
    guard let string = value as? String,
          !string.isEmpty,
          string.count <= maximumLength,
          !string.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
      throw OpenRouterUsageClientError.invalidProviderResponse
    }
    return string
  }

  private static func add(_ value: Int, to total: inout Int) throws {
    total = try adding(total, value)
  }

  private static func adding(_ lhs: Int, _ rhs: Int) throws -> Int {
    let result = lhs.addingReportingOverflow(rhs)
    guard !result.overflow else { throw OpenRouterUsageClientError.invalidProviderResponse }
    return result.partialValue
  }

  private static func selectAnalyticsMetrics(from available: [String]) -> [String] {
    let preferred = [
      "request_count",
      "total_usage",
      "usage",
      "tokens_total",
      "total_tokens",
      "tokens_prompt",
      "prompt_tokens",
      "tokens_completion",
      "completion_tokens",
      "reasoning_tokens"
    ]
    let selected = preferred.filter(available.contains)
    return Array(selected.prefix(6))
  }

  private static func displayLabel(for name: String) -> String {
    name.replacingOccurrences(of: "_", with: " ")
  }

  private static func analyticsUnit(for name: String) -> String {
    let lowercased = name.lowercased()
    if lowercased.contains("token") { return "tokens" }
    if lowercased.contains("request") { return "requests" }
    if lowercased.contains("usage") || lowercased.contains("cost") { return "credits" }
    return "value"
  }

  private static func parseDate(_ value: Any?) -> Date? {
    guard let string = ProviderJSON.string(value) else { return nil }
    return ISO8601DateFormatter.providerFlexible.date(from: string)
      ?? ISO8601DateFormatter.providerStandard.date(from: string)
  }

  private static func hasCredential(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty
      && trimmed == value
      && trimmed.count <= 4_096
      && !trimmed.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains)
      && !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
  }

  private static func validOAuthValue(_ value: String, maximumLength: Int) -> Bool {
    !value.isEmpty
      && value.count <= maximumLength
      && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
  }

  private static func appendMetric(
    _ metrics: inout [ProviderMetric],
    key: String,
    label: String,
    value: Double?,
    unit: String
  ) {
    guard let value else { return }
    metrics.append(ProviderMetric(key: key, label: label, value: value, unit: unit))
  }

  private static func failureSnapshot(
    scope: ProviderScope,
    observedAt: Date,
    operation: String,
    error: Error
  ) -> ProviderSnapshot {
    ProviderSnapshot(
      providerID: .openRouter,
      scope: scope,
      sourceKind: .officialDirect,
      observedAt: observedAt,
      windows: [],
      balance: nil,
      metrics: [],
      warnings: [],
      partialFailures: [ProviderFailure(operation: operation, message: ProviderJSON.safeMessage(error))]
    )
  }
}

enum OpenRouterUsageClientError: LocalizedError {
  case missingAPIKey
  case missingManagementKey
  case invalidAuthorizationCode
  case invalidCodeVerifier
  case invalidActivityFilter
  case invalidGenerationID
  case invalidProviderResponse
  case analyticsMetadataUnavailable
  case recentCallsUnavailable

  var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      "Connect an OpenRouter API key before checking its limit."
    case .missingManagementKey:
      "Enter an OpenRouter management key to check the whole account."
    case .invalidAuthorizationCode:
      "OpenRouter returned an invalid authorization code. Start a new connection."
    case .invalidCodeVerifier:
      "The OpenRouter connection verifier is invalid or expired. Start a new connection."
    case .invalidActivityFilter:
      "An OpenRouter activity filter contains unsupported characters."
    case .invalidGenerationID:
      "The OpenRouter generation identifier contains unsupported characters."
    case .invalidProviderResponse:
      "OpenRouter returned an unsupported response."
    case .analyticsMetadataUnavailable:
      "OpenRouter did not publish a usable analytics metric for this query."
    case .recentCallsUnavailable:
      "OpenRouter did not publish the generation analytics needed for recent call metadata."
    }
  }
}
