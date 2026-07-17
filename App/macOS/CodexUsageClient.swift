import Darwin
import Foundation

struct CodexUsageClient: ProviderUsageClient {
  enum Context {
    case personalDesktop
    case enterprise(apiKey: String, workspaceID: String, days: Int)
  }

  struct DesktopAuthorization {
    let accessToken: String
    let accountID: String?
  }

  struct PersonalUsage {
    let plan: String
    let allowed: Bool?
    let limitReached: Bool?
    let windows: [QuotaWindow]
    let credits: PersonalCredits?
    let fallbackResetCredits: Int?
  }

  struct PersonalCredits {
    let balance: Double?
    let unlimited: Bool?
    let hasCredits: Bool?
  }

  struct EnterpriseTotals {
    var threads = 0
    var turns = 0
    var credits: Double = 0
    var textInputTokens = 0
    var cachedInputTokens = 0
    var textOutputTokens = 0
    var rows = 0

    mutating func merge(_ other: EnterpriseTotals) throws {
      func checked(_ lhs: Int, _ rhs: Int) throws -> Int {
        let value = lhs.addingReportingOverflow(rhs)
        guard !value.overflow else { throw CodexUsageClientError.invalidProviderResponse }
        return value.partialValue
      }
      let updatedCredits = credits + other.credits
      guard updatedCredits.isFinite else { throw CodexUsageClientError.invalidProviderResponse }
      let updatedThreads = try checked(threads, other.threads)
      let updatedTurns = try checked(turns, other.turns)
      let updatedInput = try checked(textInputTokens, other.textInputTokens)
      let updatedCached = try checked(cachedInputTokens, other.cachedInputTokens)
      let updatedOutput = try checked(textOutputTokens, other.textOutputTokens)
      let updatedRows = try checked(rows, other.rows)
      threads = updatedThreads
      turns = updatedTurns
      credits = updatedCredits
      textInputTokens = updatedInput
      cachedInputTokens = updatedCached
      textOutputTokens = updatedOutput
      rows = updatedRows
    }
  }

  struct EnterprisePage {
    let totals: EnterpriseTotals
    let nextPage: String?
    let hasMore: Bool
  }

  let providerID: ProviderID = .codex

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
    case .personalDesktop:
      return await fetchPersonalSnapshot()
    case .enterprise(let apiKey, let workspaceID, let days):
      return await fetchEnterpriseSnapshot(apiKey: apiKey, workspaceID: workspaceID, days: days)
    }
  }

  func fetchPersonalSnapshot() async -> ProviderSnapshot {
    let observedAt = now()
    let baseScope = ProviderScope.personal("Codex Desktop")

    let authorization: DesktopAuthorization
    do {
      authorization = try Self.loadDesktopAuthorization()
    } catch {
      return ProviderSnapshot(
        providerID: providerID,
        scope: baseScope,
        sourceKind: .experimentalPrivate,
        observedAt: observedAt,
        windows: [],
        balance: nil,
        metrics: [],
        warnings: [
          ProviderWarning(
            id: "codex-private-contract",
            message: "Personal Codex usage uses an experimental, non-public desktop endpoint."
          )
        ],
        partialFailures: [
          ProviderFailure(operation: "codex.desktop.auth", message: ProviderJSON.safeMessage(error))
        ]
      )
    }

    let headers = Self.desktopHeaders(for: authorization)
    async let usageResult = captureProviderResult {
      try await requestJSON(
        url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        headers: headers,
        operation: "codex.desktop.usage"
      )
    }
    async let creditsResult = captureProviderResult {
      try await requestJSON(
        url: URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!,
        headers: headers,
        operation: "codex.desktop.reset-credits"
      )
    }

    let usage = await usageResult
    let credits = await creditsResult
    var normalizedUsage: PersonalUsage?
    var resetCredits: Int?
    var failures: [ProviderFailure] = []

    switch usage {
    case .success(let json):
      do {
        normalizedUsage = try Self.decodePersonalUsage(json)
      } catch {
        failures.append(
          ProviderFailure(operation: "codex.desktop.usage", message: ProviderJSON.safeMessage(error))
        )
      }
    case .failure(let error):
      failures.append(
        ProviderFailure(operation: "codex.desktop.usage", message: ProviderJSON.safeMessage(error))
      )
    }

    switch credits {
    case .success(let json):
      do {
        resetCredits = try Self.decodeResetCredits(json)
      } catch {
        failures.append(
          ProviderFailure(operation: "codex.desktop.reset-credits", message: ProviderJSON.safeMessage(error))
        )
      }
    case .failure(let error):
      failures.append(
        ProviderFailure(operation: "codex.desktop.reset-credits", message: ProviderJSON.safeMessage(error))
      )
    }

    if resetCredits == nil {
      resetCredits = normalizedUsage?.fallbackResetCredits
    }

    var warnings = [
      ProviderWarning(
        id: "codex-private-contract",
        message: "Personal Codex usage uses an experimental, non-public desktop endpoint."
      )
    ]
    if normalizedUsage?.allowed == false {
      warnings.append(ProviderWarning(id: "codex-not-allowed", message: "Codex reported that usage is not currently allowed."))
    }
    if normalizedUsage?.limitReached == true {
      warnings.append(ProviderWarning(id: "codex-limit-reached", message: "Codex reported that a usage limit was reached."))
    }
    if let normalizedUsage, normalizedUsage.windows.isEmpty {
      warnings.append(
        ProviderWarning(
          id: "codex-no-fixed-window",
          message: "Codex did not report a fixed usage window for this account. Dashis does not infer a rolling-window duration; current allowance is plan- and credit-dependent."
        )
      )
    }
    if normalizedUsage?.credits?.unlimited == true {
      warnings.append(
        ProviderWarning(
          id: "codex-unlimited-credits",
          message: "Codex reported unlimited credit access for this account."
        )
      )
    }

    let metrics = resetCredits.map {
      [ProviderMetric(key: "reset_credits", label: "Available reset credits", value: Double($0), unit: "credits")]
    } ?? []
    let balance = Self.personalCreditBalance(normalizedUsage?.credits)

    return ProviderSnapshot(
      providerID: providerID,
      scope: ProviderScope.personal(normalizedUsage?.plan ?? baseScope.label),
      sourceKind: .experimentalPrivate,
      observedAt: observedAt,
      windows: normalizedUsage?.windows ?? [],
      balance: balance,
      metrics: metrics,
      warnings: warnings,
      partialFailures: failures
    )
  }

  func fetchEnterpriseSnapshot(apiKey: String, workspaceID: String, days: Int) async -> ProviderSnapshot {
    let observedAt = now()
    let normalizedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedWorkspaceID = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
    let scope = ProviderScope.workspace(trimmedWorkspaceID.isEmpty ? "Codex workspace" : trimmedWorkspaceID)

    guard !normalizedAPIKey.isEmpty else {
      return Self.enterpriseFailureSnapshot(
        scope: scope,
        observedAt: observedAt,
        operation: "codex.enterprise.auth",
        error: .missingEnterpriseKey
      )
    }
    guard Self.validBearerCredential(normalizedAPIKey) else {
      return Self.enterpriseFailureSnapshot(
        scope: scope,
        observedAt: observedAt,
        operation: "codex.enterprise.auth",
        error: .invalidEnterpriseKey
      )
    }
    guard ProviderEndpointPolicy.sanitizeIdentifier(trimmedWorkspaceID) == trimmedWorkspaceID else {
      return Self.enterpriseFailureSnapshot(
        scope: ProviderScope.workspace("Codex workspace"),
        observedAt: observedAt,
        operation: "codex.enterprise.workspace",
        error: .invalidWorkspaceID
      )
    }

    let safeDays = max(1, min(days, 90))
    let end = Int(observedAt.timeIntervalSince1970)
    let start = end - safeDays * 86_400
    let headers = [
      "Authorization": "Bearer \(normalizedAPIKey)",
      "Accept": "application/json"
    ]

    var totals = EnterpriseTotals()
    var failures: [ProviderFailure] = []
    var warnings: [ProviderWarning] = []
    var requestedPage: String?
    var seenPages = Set<String>()
    var ordinal = 1
    var successfulPages = 0
    let maximumPages = 100

    while ordinal <= maximumPages {
      let url: URL
      do {
        url = try Self.enterpriseUsageURL(
          workspaceID: trimmedWorkspaceID,
          start: start,
          end: end,
          page: requestedPage
        )
      } catch {
        failures.append(
          ProviderFailure(operation: "codex.enterprise.usage", message: ProviderJSON.safeMessage(error))
        )
        break
      }

      do {
        let json = try await requestJSON(
          url: url,
          headers: headers,
          operation: "codex.enterprise.usage.page-\(ordinal)"
        )
        let page = try Self.decodeEnterprisePage(json)
        try totals.merge(page.totals)
        successfulPages += 1

        guard page.hasMore || page.nextPage != nil else { break }
        let nextPage = page.nextPage ?? String(ordinal + 1)
        guard ProviderEndpointPolicy.sanitizeIdentifier(nextPage) == nextPage,
              seenPages.insert(nextPage).inserted
        else {
          warnings.append(
            ProviderWarning(
              id: "codex-pagination-stopped",
              message: "Workspace pagination stopped because the next page token was invalid or repeated."
            )
          )
          break
        }
        requestedPage = nextPage
        ordinal += 1
      } catch {
        failures.append(
          ProviderFailure(
            operation: "codex.enterprise.usage.page-\(ordinal)",
            message: ProviderJSON.safeMessage(error)
          )
        )
        break
      }
    }

    if ordinal > maximumPages {
      warnings.append(
        ProviderWarning(
          id: "codex-pagination-limit",
          message: "Workspace usage stopped after 100 pages; displayed totals may be incomplete."
        )
      )
    }

    var metrics = successfulPages == 0 ? [] : [
      ProviderMetric(key: "threads", label: "Threads", value: Double(totals.threads), unit: "threads"),
      ProviderMetric(key: "turns", label: "Turns", value: Double(totals.turns), unit: "turns"),
      ProviderMetric(key: "credits", label: "Credits", value: totals.credits, unit: "credits"),
      ProviderMetric(key: "text_input_tokens", label: "Input tokens", value: Double(totals.textInputTokens), unit: "tokens"),
      ProviderMetric(key: "cached_input_tokens", label: "Cached input tokens", value: Double(totals.cachedInputTokens), unit: "tokens"),
      ProviderMetric(key: "text_output_tokens", label: "Output tokens", value: Double(totals.textOutputTokens), unit: "tokens"),
      ProviderMetric(key: "rows", label: "Usage rows", value: Double(totals.rows), unit: "rows")
    ]
    if successfulPages > 0 {
      let first = totals.textInputTokens.addingReportingOverflow(totals.cachedInputTokens)
      let second = first.partialValue.addingReportingOverflow(totals.textOutputTokens)
      if first.overflow || second.overflow {
        failures.append(
          ProviderFailure(
            operation: "codex.enterprise.total_tokens",
            message: ProviderJSON.safeMessage(CodexUsageClientError.invalidProviderResponse)
          )
        )
      } else {
        metrics.append(
          ProviderMetric(key: "total_tokens", label: "Total tokens", value: Double(second.partialValue), unit: "tokens")
        )
      }
    }

    return ProviderSnapshot(
      providerID: providerID,
      scope: scope,
      sourceKind: .officialDirect,
      observedAt: observedAt,
      windows: [],
      balance: nil,
      metrics: metrics,
      warnings: warnings,
      partialFailures: failures
    )
  }

  static func decodePersonalUsage(_ json: Any) throws -> PersonalUsage {
    guard let response = json as? [String: Any] else {
      throw CodexUsageClientError.invalidProviderResponse
    }
    let rateLimitRaw = aliasedValue(response, aliases: ["rate_limit", "rateLimit"])
    let rateLimit: [String: Any]?
    if let rateLimitRaw, !(rateLimitRaw is NSNull) {
      guard let decoded = rateLimitRaw as? [String: Any] else {
        throw CodexUsageClientError.invalidProviderResponse
      }
      rateLimit = decoded
    } else {
      rateLimit = nil
    }

    let allowed = try optionalBoolValue(rateLimit, aliases: ["allowed"])
    let limitReached = try optionalBoolValue(rateLimit, aliases: ["limit_reached", "limitReached"])
    var windows: [QuotaWindow] = []
    var recognizedRateLimit = allowed != nil || limitReached != nil

    if let primary = try optionalDictionaryValue(rateLimit, aliases: ["primary_window", "primaryWindow"]) {
      windows.append(decodePersonalWindow(primary, fallbackID: "primary"))
      recognizedRateLimit = true
    }
    if let secondary = try optionalDictionaryValue(rateLimit, aliases: ["secondary_window", "secondaryWindow"]) {
      windows.append(decodePersonalWindow(secondary, fallbackID: "secondary"))
      recognizedRateLimit = true
    }

    let credits = try decodePersonalCredits(aliasedValue(response, aliases: ["credits"]))
    let fallbackResetCredits = try decodeEmbeddedResetCredits(response)
    guard recognizedRateLimit || credits != nil || fallbackResetCredits != nil else {
      throw CodexUsageClientError.invalidProviderResponse
    }

    return PersonalUsage(
      plan: ProviderJSON.string(response["plan_type"] ?? response["planType"]) ?? "Codex Desktop",
      allowed: allowed,
      limitReached: limitReached,
      windows: windows,
      credits: credits,
      fallbackResetCredits: fallbackResetCredits
    )
  }

  static func decodeResetCredits(_ json: Any) throws -> Int {
    let response = ProviderJSON.dictionary(json)
    if let available = ProviderJSON.int(response["available_count"] ?? response["availableCount"]) {
      return available
    }
    guard let credits = response["credits"] as? [Any] else {
      throw CodexUsageClientError.invalidProviderResponse
    }
    return credits.reduce(into: 0) { count, rawCredit in
      let credit = ProviderJSON.dictionary(rawCredit)
      if ProviderJSON.string(credit["status"])?.lowercased() == "available" {
        count += 1
      }
    }
  }

  static func decodeEnterprisePage(_ json: Any) throws -> EnterprisePage {
    guard let response = json as? [String: Any],
          let rowsKey = ["data", "items", "results"].first(where: { response[$0] != nil }),
          let rows = response[rowsKey] as? [Any]
    else {
      throw CodexUsageClientError.invalidProviderResponse
    }
    var totals = EnterpriseTotals()

    for rawRow in rows {
      guard let row = rawRow as? [String: Any] else {
        throw CodexUsageClientError.invalidProviderResponse
      }
      let recognizedKeys: Set<String> = [
        "threads", "thread_count", "threadCount",
        "turns", "turn_count", "turnCount",
        "credits", "credit_usage", "creditUsage",
        "text_input_tokens", "textInputTokens", "input_tokens", "inputTokens",
        "cached_input_tokens", "cachedInputTokens", "cache_read_input_tokens", "cached_tokens",
        "text_output_tokens", "textOutputTokens", "output_tokens", "outputTokens"
      ]
      guard !recognizedKeys.isDisjoint(with: row.keys) else {
        throw CodexUsageClientError.invalidProviderResponse
      }

      try add(
        try intValue(row, aliases: ["threads", "thread_count", "threadCount"]),
        to: &totals.threads
      )
      try add(
        try intValue(row, aliases: ["turns", "turn_count", "turnCount"]),
        to: &totals.turns
      )
      let credits = try numberValue(row, aliases: ["credits", "credit_usage", "creditUsage"])
      let updatedCredits = totals.credits + credits
      guard updatedCredits.isFinite else { throw CodexUsageClientError.invalidProviderResponse }
      totals.credits = updatedCredits
      try add(
        try intValue(row, aliases: ["text_input_tokens", "textInputTokens", "input_tokens", "inputTokens"]),
        to: &totals.textInputTokens
      )
      try add(
        try intValue(row, aliases: ["cached_input_tokens", "cachedInputTokens", "cache_read_input_tokens", "cached_tokens"]),
        to: &totals.cachedInputTokens
      )
      try add(
        try intValue(row, aliases: ["text_output_tokens", "textOutputTokens", "output_tokens", "outputTokens"]),
        to: &totals.textOutputTokens
      )
      try add(1, to: &totals.rows)
    }

    let metadata: [String: Any]
    if let metadataKey = ["metadata", "meta", "pagination"].first(where: { response[$0] != nil }) {
      guard let decoded = response[metadataKey] as? [String: Any] else {
        throw CodexUsageClientError.invalidProviderResponse
      }
      metadata = decoded
    } else {
      metadata = [:]
    }

    let nextPageRaw = aliasedValue(
      response,
      aliases: ["next_page", "nextPage"]
    ) ?? aliasedValue(
      metadata,
      aliases: ["next_page", "nextPage", "next_page_token", "nextPageToken"]
    )
    let nextPage: String?
    if let nextPageRaw {
      guard let value = nextPageRaw as? String else {
        throw CodexUsageClientError.invalidProviderResponse
      }
      nextPage = value.isEmpty ? nil : value
    } else {
      nextPage = nil
    }

    let hasMoreRaw = aliasedValue(response, aliases: ["has_more", "hasMore"])
      ?? aliasedValue(metadata, aliases: ["has_more", "hasMore"])
    let hasMore: Bool
    if let hasMoreRaw {
      guard let value = ProviderJSON.bool(hasMoreRaw) else {
        throw CodexUsageClientError.invalidProviderResponse
      }
      hasMore = value
    } else {
      hasMore = nextPage != nil
    }
    return EnterprisePage(totals: totals, nextPage: nextPage, hasMore: hasMore)
  }

  private static func aliasedValue(_ object: [String: Any], aliases: [String]) -> Any? {
    for alias in aliases where object.keys.contains(alias) {
      return object[alias]
    }
    return nil
  }

  private static func intValue(_ object: [String: Any], aliases: [String]) throws -> Int {
    guard let raw = aliasedValue(object, aliases: aliases) else { return 0 }
    guard let value = ProviderJSON.int(raw) else {
      throw CodexUsageClientError.invalidProviderResponse
    }
    return value
  }

  private static func numberValue(_ object: [String: Any], aliases: [String]) throws -> Double {
    guard let raw = aliasedValue(object, aliases: aliases) else { return 0 }
    guard let value = ProviderJSON.number(raw) else {
      throw CodexUsageClientError.invalidProviderResponse
    }
    return value
  }

  private static func add(_ value: Int, to total: inout Int) throws {
    let result = total.addingReportingOverflow(value)
    guard !result.overflow else { throw CodexUsageClientError.invalidProviderResponse }
    total = result.partialValue
  }

  private func requestJSON(url: URL, headers: [String: String], operation: String) async throws -> Any {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    for (name, value) in headers {
      request.setValue(value, forHTTPHeaderField: name)
    }
    return try await httpClient.json(for: request, operation: operation)
  }

  private static func decodePersonalWindow(_ window: [String: Any], fallbackID: String) -> QuotaWindow {
    let windowSeconds = ProviderJSON.number(window["limit_window_seconds"] ?? window["limitWindowSeconds"])
    let usedPercentage = ProviderJSON.number(window["used_percent"] ?? window["usedPercent"])
    let remainingPercentage = usedPercentage.map { 100 - $0 }
    let resetRaw = ProviderJSON.number(window["reset_at"] ?? window["resetAt"])
    let resetSeconds = resetRaw.map { $0 > 10_000_000_000 ? $0 / 1_000 : $0 }
    let label = personalWindowLabel(seconds: windowSeconds, fallbackID: fallbackID)

    return QuotaWindow(
      id: fallbackID,
      label: label,
      used: usedPercentage,
      limit: usedPercentage == nil ? nil : 100,
      remaining: remainingPercentage,
      usedPercentage: usedPercentage,
      remainingPercentage: remainingPercentage,
      resetsAt: resetSeconds.map(Date.init(timeIntervalSince1970:)),
      unit: "%",
      isEstimated: false
    )
  }

  private static func personalWindowLabel(seconds: Double?, fallbackID: String) -> String {
    let fallback = fallbackID == "primary"
      ? "Primary usage window"
      : fallbackID == "secondary" ? "Secondary usage window" : "Usage window"
    guard let seconds,
          seconds > 0,
          let wholeSeconds = Int(exactly: seconds.rounded()),
          abs(seconds - Double(wholeSeconds)) < 0.001,
          wholeSeconds <= 10 * 365 * 24 * 60 * 60
    else {
      return fallback
    }

    if wholeSeconds.isMultiple(of: 24 * 60 * 60) {
      return "\(wholeSeconds / (24 * 60 * 60))-day window"
    }
    if wholeSeconds.isMultiple(of: 60 * 60) {
      return "\(wholeSeconds / (60 * 60))-hour window"
    }
    if wholeSeconds.isMultiple(of: 60) {
      return "\(wholeSeconds / 60)-minute window"
    }
    return "\(wholeSeconds)-second window"
  }

  private static func optionalBoolValue(
    _ object: [String: Any]?,
    aliases: [String]
  ) throws -> Bool? {
    guard let object, let raw = aliasedValue(object, aliases: aliases) else { return nil }
    guard !(raw is NSNull), let value = ProviderJSON.bool(raw) else {
      if raw is NSNull { return nil }
      throw CodexUsageClientError.invalidProviderResponse
    }
    return value
  }

  private static func optionalDictionaryValue(
    _ object: [String: Any]?,
    aliases: [String]
  ) throws -> [String: Any]? {
    guard let object, let raw = aliasedValue(object, aliases: aliases) else { return nil }
    if raw is NSNull { return nil }
    guard let value = raw as? [String: Any] else {
      throw CodexUsageClientError.invalidProviderResponse
    }
    return value
  }

  private static func decodePersonalCredits(_ raw: Any?) throws -> PersonalCredits? {
    guard let raw, !(raw is NSNull) else { return nil }
    guard let credits = raw as? [String: Any] else {
      throw CodexUsageClientError.invalidProviderResponse
    }

    let balanceRaw = aliasedValue(credits, aliases: ["balance"])
    let unlimitedRaw = aliasedValue(credits, aliases: ["unlimited"])
    let hasCreditsRaw = aliasedValue(credits, aliases: ["has_credits", "hasCredits"])
    guard balanceRaw != nil || unlimitedRaw != nil || hasCreditsRaw != nil else {
      throw CodexUsageClientError.invalidProviderResponse
    }

    let balance: Double?
    if let balanceRaw, !(balanceRaw is NSNull) {
      guard let value = ProviderJSON.number(balanceRaw) else {
        throw CodexUsageClientError.invalidProviderResponse
      }
      balance = value
    } else {
      balance = nil
    }

    let unlimited: Bool?
    if let unlimitedRaw, !(unlimitedRaw is NSNull) {
      guard let value = ProviderJSON.bool(unlimitedRaw) else {
        throw CodexUsageClientError.invalidProviderResponse
      }
      unlimited = value
    } else {
      unlimited = nil
    }

    let hasCredits: Bool?
    if let hasCreditsRaw, !(hasCreditsRaw is NSNull) {
      guard let value = ProviderJSON.bool(hasCreditsRaw) else {
        throw CodexUsageClientError.invalidProviderResponse
      }
      hasCredits = value
    } else {
      hasCredits = nil
    }

    guard balance != nil || unlimited != nil || hasCredits != nil else {
      throw CodexUsageClientError.invalidProviderResponse
    }
    return PersonalCredits(balance: balance, unlimited: unlimited, hasCredits: hasCredits)
  }

  private static func decodeEmbeddedResetCredits(_ response: [String: Any]) throws -> Int? {
    guard let raw = aliasedValue(
      response,
      aliases: ["rate_limit_reset_credits", "rateLimitResetCredits"]
    ), !(raw is NSNull) else {
      return nil
    }
    guard let reset = raw as? [String: Any] else {
      throw CodexUsageClientError.invalidProviderResponse
    }
    guard !reset.isEmpty else { return nil }
    return try decodeResetCredits(reset)
  }

  static func personalCreditBalance(_ credits: PersonalCredits?) -> ProviderBalance? {
    guard let credits else { return nil }
    if credits.unlimited == true {
      return ProviderBalance(
        label: "Codex credits",
        used: nil,
        limit: nil,
        remaining: nil,
        unit: "credits",
        resetDescription: nil,
        valueDescription: "Unlimited"
      )
    }
    if let balance = credits.balance {
      return ProviderBalance(
        label: "Codex credits",
        used: nil,
        limit: nil,
        remaining: balance,
        unit: "credits",
        resetDescription: nil
      )
    }
    if let hasCredits = credits.hasCredits {
      return ProviderBalance(
        label: "Codex credits",
        used: nil,
        limit: nil,
        remaining: nil,
        unit: "credits",
        resetDescription: nil,
        valueDescription: hasCredits ? "Available" : "No additional credits"
      )
    }
    return nil
  }

  private static func desktopHeaders(for authorization: DesktopAuthorization) -> [String: String] {
    var headers = [
      "Authorization": "Bearer \(authorization.accessToken)",
      "originator": "Codex Desktop",
      "OAI-Product-Sku": "CODEX",
      "Accept": "application/json"
    ]
    if let accountID = authorization.accountID,
       ProviderEndpointPolicy.sanitizeIdentifier(accountID) == accountID {
      headers["ChatGPT-Account-Id"] = accountID
    }
    return headers
  }

  private static func loadDesktopAuthorization() throws -> DesktopAuthorization {
    let authURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex", isDirectory: true)
      .appendingPathComponent("auth.json", isDirectory: false)
    let data: Data
    do {
      data = try readOwnedRegularFile(at: authURL, maximumBytes: 1_048_576)
    } catch {
      throw CodexUsageClientError.desktopAuthorizationUnavailable
    }
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tokens = object["tokens"] as? [String: Any],
          let accessToken = tokens["access_token"] as? String,
          validBearerCredential(accessToken)
    else {
      throw CodexUsageClientError.desktopAuthorizationUnavailable
    }

    let fallbackAccountID = (tokens["account_id"] ?? tokens["accountId"]) as? String
    let safeFallbackAccountID = fallbackAccountID.flatMap { value in
      ProviderEndpointPolicy.sanitizeIdentifier(value) == value ? value : nil
    }
    return DesktopAuthorization(
      accessToken: accessToken,
      accountID: accountID(from: accessToken) ?? safeFallbackAccountID
    )
  }

  static func readOwnedRegularFile(at url: URL, maximumBytes: Int) throws -> Data {
    let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
    guard descriptor >= 0 else { throw CodexUsageClientError.desktopAuthorizationUnavailable }
    defer { Darwin.close(descriptor) }

    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0,
          metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
          metadata.st_uid == getuid(),
          metadata.st_mode & mode_t(0o077) == 0,
          metadata.st_size >= 0,
          metadata.st_size <= off_t(maximumBytes)
    else {
      throw CodexUsageClientError.desktopAuthorizationUnavailable
    }

    var result = Data()
    result.reserveCapacity(Int(metadata.st_size))
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while true {
      let count = buffer.withUnsafeMutableBytes { rawBuffer in
        Darwin.read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
      }
      if count == 0 { return result }
      if count < 0 {
        if errno == EINTR { continue }
        throw CodexUsageClientError.desktopAuthorizationUnavailable
      }
      result.append(buffer, count: count)
      guard result.count <= maximumBytes else {
        throw CodexUsageClientError.desktopAuthorizationUnavailable
      }
    }
  }

  private static func accountID(from accessToken: String) -> String? {
    let parts = accessToken.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count >= 2, let payload = decodeBase64URL(String(parts[1])),
          let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
          let auth = object["https://api.openai.com/auth"] as? [String: Any]
    else {
      return nil
    }
    guard let value = (auth["chatgpt_account_id"] ?? auth["chatgptAccountId"]) as? String,
          ProviderEndpointPolicy.sanitizeIdentifier(value) == value
    else { return nil }
    return value
  }

  private static func validBearerCredential(_ value: String) -> Bool {
    !value.isEmpty
      && value.count <= 8_192
      && !value.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains)
      && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
  }

  private static func decodeBase64URL(_ value: String) -> Data? {
    var normalized = value.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let remainder = normalized.count % 4
    if remainder > 0 {
      normalized.append(String(repeating: "=", count: 4 - remainder))
    }
    return Data(base64Encoded: normalized)
  }

  private static func enterpriseUsageURL(
    workspaceID: String,
    start: Int,
    end: Int,
    page: String?
  ) throws -> URL {
    var components = URLComponents(
      string: "https://api.chatgpt.com/v1/analytics/codex/workspaces/\(workspaceID)/usage"
    )!
    var queryItems = [
      URLQueryItem(name: "start_time", value: String(start)),
      URLQueryItem(name: "end_time", value: String(end)),
      URLQueryItem(name: "group_by", value: "day"),
      URLQueryItem(name: "group", value: "workspace"),
      URLQueryItem(name: "limit", value: "500")
    ]
    if let page {
      queryItems.append(URLQueryItem(name: "page", value: page))
    }
    components.queryItems = queryItems
    guard let url = components.url else { throw CodexUsageClientError.invalidWorkspaceID }
    return url
  }

  private static func enterpriseFailureSnapshot(
    scope: ProviderScope,
    observedAt: Date,
    operation: String,
    error: CodexUsageClientError
  ) -> ProviderSnapshot {
    ProviderSnapshot(
      providerID: .codex,
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

enum CodexUsageClientError: LocalizedError {
  case desktopAuthorizationUnavailable
  case missingEnterpriseKey
  case invalidEnterpriseKey
  case invalidWorkspaceID
  case invalidProviderResponse

  var errorDescription: String? {
    switch self {
    case .desktopAuthorizationUnavailable:
      "Codex Desktop sign-in was not available. Sign in again, then retry explicitly."
    case .missingEnterpriseKey:
      "Enter an analytics-scoped API key for this check."
    case .invalidEnterpriseKey:
      "The analytics API key contains unsupported characters."
    case .invalidWorkspaceID:
      "The workspace identifier contains unsupported characters."
    case .invalidProviderResponse:
      "Codex returned an unsupported response."
    }
  }
}
