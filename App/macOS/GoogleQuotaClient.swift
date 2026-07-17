import Foundation

struct GoogleConsumerManualContext: Sendable {
  let label: String
  let observedAt: Date
  let used: Double?
  let limit: Double?
  let remaining: Double?
  let unit: String

  init(
    label: String = "Google AI subscription",
    observedAt: Date = Date(),
    used: Double? = nil,
    limit: Double? = nil,
    remaining: Double? = nil,
    unit: String = "%"
  ) {
    self.label = label
    self.observedAt = observedAt
    self.used = used
    self.limit = limit
    self.remaining = remaining
    self.unit = unit
  }
}

struct GoogleConsumerUsageClient: ProviderUsageClient {
  let providerID: ProviderID = .google

  func fetchSnapshot(context: GoogleConsumerManualContext) async -> ProviderSnapshot {
    let reading = ManualReading(context: context)
    var warnings = [ProviderWarning]()
    if !reading.hasAnyValue {
      warnings.append(
        ProviderWarning(
          id: "google-consumer-manual-required",
          message: "Manual check required. Google does not publish a consumer subscription quota API."
        )
      )
    } else if reading.isInconsistent {
      warnings.append(
        ProviderWarning(
          id: "google-consumer-manual-inconsistent",
          message: "The manual values do not reconcile; the entered values are shown without correction."
        )
      )
    }

    let window: QuotaWindow? = reading.hasAnyValue
      ? QuotaWindow(
        id: "google-consumer-manual",
        label: context.label,
        used: reading.used,
        limit: reading.limit,
        remaining: reading.remaining,
        usedPercentage: reading.usedPercentage,
        remainingPercentage: reading.remainingPercentage,
        resetsAt: nil,
        unit: context.unit,
        isEstimated: false
      )
      : nil

    return ProviderSnapshot(
      providerID: providerID,
      scope: ProviderScope(kind: .manual, label: context.label),
      sourceKind: .manualOnly,
      observedAt: context.observedAt,
      windows: window.map { [$0] } ?? [],
      balance: nil,
      metrics: [],
      warnings: warnings,
      partialFailures: []
    )
  }
}

struct GeminiAPIProjectContext: Sendable {
  let projectID: String
  let accessToken: GoogleSessionAccessToken
  let selectedQuotaIDs: Set<String>?
  let observationDate: Date?

  init(
    projectID: String,
    accessToken: GoogleSessionAccessToken,
    selectedQuotaIDs: Set<String>? = nil,
    observationDate: Date? = nil
  ) {
    self.projectID = projectID
    self.accessToken = accessToken
    self.selectedQuotaIDs = selectedQuotaIDs
    self.observationDate = observationDate
  }
}

struct GeminiAPIProjectUsageClient: ProviderUsageClient {
  let providerID: ProviderID = .google
  private let httpClient: ProviderHTTPClient

  init(httpClient: ProviderHTTPClient = ProviderHTTPClient()) {
    self.httpClient = httpClient
  }

  func fetchSnapshot(context: GeminiAPIProjectContext) async -> ProviderSnapshot {
    let observedAt = context.observationDate ?? Date()
    let projectID = context.projectID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard GoogleQuotaValidation.validProjectID(projectID) else {
      return failureSnapshot(
        projectID: projectID,
        observedAt: observedAt,
        operation: "google.project",
        message: GoogleQuotaClientError.invalidProject.errorDescription!
      )
    }
    guard context.accessToken.isUsable(at: observedAt) else {
      return failureSnapshot(
        projectID: projectID,
        observedAt: observedAt,
        operation: "google.oauth",
        message: GoogleQuotaClientError.expiredAccessToken.errorDescription!
      )
    }

    let quotaInfos: [GoogleQuotaInfo]
    do {
      quotaInfos = try await fetchQuotaInfos(
        projectID: projectID,
        accessToken: context.accessToken.value
      )
    } catch {
      return failureSnapshot(
        projectID: projectID,
        observedAt: observedAt,
        operation: "google.quotas",
        message: ProviderJSON.safeMessage(error)
      )
    }

    var warnings = [ProviderWarning]()
    let matchingSelection = quotaInfos.filter { quota in
      guard let selectedQuotaIDs = context.selectedQuotaIDs else { return true }
      return selectedQuotaIDs.contains(quota.quotaID)
    }
    let orderedSelection = matchingSelection.sorted { lhs, rhs in
      let lhsSupported = lhs.isConcurrent == true || GoogleQuotaCadence(refreshInterval: lhs.refreshInterval) != nil
      let rhsSupported = rhs.isConcurrent == true || GoogleQuotaCadence(refreshInterval: rhs.refreshInterval) != nil
      if lhsSupported != rhsSupported { return lhsSupported && !rhsSupported }
      return lhs.quotaID < rhs.quotaID
    }
    let maximumQuotaDefinitions = 24
    let selected = Array(orderedSelection.prefix(maximumQuotaDefinitions))
    if orderedSelection.count > selected.count {
      warnings.append(
        ProviderWarning(
          id: "google-quota-selection-bounded",
          message: "Dashis limited this check to \(maximumQuotaDefinitions) quota definitions. Enter exact quota IDs to narrow the selection."
        )
      )
    }
    if let requested = context.selectedQuotaIDs {
      let found = Set(matchingSelection.map(\.quotaID))
      if !requested.isSubset(of: found) {
        warnings.append(
          ProviderWarning(
            id: "google-quota-selection-missing",
            message: "One or more requested quota IDs were not returned for this project."
          )
        )
      }
    }

    var failures = [ProviderFailure]()
    var seriesByType = [String: [GoogleMonitoringSeries]]()
    var validQuotaInfos = [GoogleQuotaInfo]()
    var monitoringStarts = [String: Date]()

    for quota in selected {
      guard let pair = GoogleQuotaMetricPair(quotaMetric: quota.metric) else {
        warnings.append(
          ProviderWarning(
            id: "google-metric-\(GoogleQuotaValidation.operationSlug(quota.quotaID))",
            message: "A quota metric could not be mapped to an official Gemini Monitoring metric."
          )
        )
        continue
      }
      validQuotaInfos.append(quota)
      guard let intervalStart = Self.monitoringIntervalStart(for: quota, observedAt: observedAt) else {
        continue
      }
      for metricType in [pair.limit, pair.usage] {
        monitoringStarts[metricType] = min(monitoringStarts[metricType] ?? intervalStart, intervalStart)
      }
    }

    await withTaskGroup(of: (String, Result<[GoogleMonitoringSeries], Error>).self) { group in
      for (metricType, intervalStart) in monitoringStarts {
        group.addTask { [self] in
          let result = await captureProviderResult {
            try await fetchMonitoringSeries(
              metricType: metricType,
              projectID: projectID,
              accessToken: context.accessToken.value,
              intervalStart: intervalStart,
              observedAt: observedAt
            )
          }
          return (metricType, result)
        }
      }
      for await (metricType, result) in group {
        switch result {
        case .success(let series):
          seriesByType[metricType] = series
        case .failure(let error):
          seriesByType[metricType] = []
          let suffix = metricType.hasSuffix("/limit") ? "limit" : "usage"
          failures.append(
            ProviderFailure(
              operation: "google.monitoring.\(suffix).\(GoogleQuotaValidation.operationSlug(metricType))",
              message: ProviderJSON.safeMessage(error)
            )
          )
        }
      }
    }

    var derivedWindows = [QuotaWindow]()
    for quota in validQuotaInfos {
      guard let pair = GoogleQuotaMetricPair(quotaMetric: quota.metric) else { continue }
      let result = GoogleQuotaDeriver.derive(
        quota: quota,
        limitSeries: seriesByType[pair.limit] ?? [],
        usageSeries: seriesByType[pair.usage] ?? [],
        now: observedAt
      )
      derivedWindows.append(contentsOf: result.windows)
      warnings.append(contentsOf: result.warnings)
    }

    warnings.append(
      ProviderWarning(
        id: "google-monitoring-delay",
        message: "Cloud Monitoring quota usage can be delayed by about 150 seconds."
      )
    )
    warnings.append(
      ProviderWarning(
        id: "google-preview-dynamic-capacity",
        message: "Some Gemini quota metrics are preview or dynamically allocated; Dashis leaves unmatched or conflicting capacity unavailable instead of guessing."
      )
    )
    if selected.isEmpty {
      warnings.append(
        ProviderWarning(
          id: "google-no-selected-quotas",
          message: "No Gemini API quota definitions matched this project and selection."
        )
      )
    }

    let hasQuotaValue = derivedWindows.contains { window in
      [window.used, window.limit, window.remaining, window.usedPercentage, window.remainingPercentage]
        .compactMap { $0 }
        .contains(where: \.isFinite)
    }
    let diagnosticMetrics = hasQuotaValue ? [
      ProviderMetric(
        key: "google-quota-definitions",
        label: "Quota definitions",
        value: Double(selected.count),
        unit: "quotas"
      ),
      ProviderMetric(
        key: "google-derived-windows",
        label: "Derived windows",
        value: Double(derivedWindows.filter { $0.remaining != nil }.count),
        unit: "windows"
      )
    ] : []

    return ProviderSnapshot(
      providerID: providerID,
      scope: .project(projectID),
      sourceKind: .officialDerived,
      observedAt: observedAt,
      windows: derivedWindows.sorted(by: GoogleQuotaDeriver.windowOrder),
      balance: nil,
      metrics: diagnosticMetrics,
      warnings: deduplicated(warnings),
      partialFailures: deduplicated(failures)
    )
  }

  private func fetchQuotaInfos(
    projectID: String,
    accessToken: String
  ) async throws -> [GoogleQuotaInfo] {
    var pageToken: String?
    var seenTokens = Set<String>()
    var result = [GoogleQuotaInfo]()

    for _ in 0..<20 {
      var components = URLComponents()
      components.scheme = "https"
      components.host = "cloudquotas.googleapis.com"
      components.path = "/v1/projects/\(projectID)/locations/global/services/generativelanguage.googleapis.com/quotaInfos"
      var queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
      if let pageToken {
        queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
      }
      components.queryItems = queryItems
      guard let url = components.url else {
        throw GoogleQuotaClientError.invalidRequest
      }

      var request = URLRequest(url: url)
      request.httpMethod = "GET"
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      let object = try await httpClient.json(for: request, operation: "google.quotas")
      let page = try GoogleQuotaPayloadDecoder.decode(object)
      result.append(contentsOf: page.quotaInfos)

      guard let next = page.nextPageToken, !next.isEmpty else {
        return result
      }
      guard next.count <= 2_048, seenTokens.insert(next).inserted else {
        throw GoogleQuotaClientError.invalidPagination
      }
      pageToken = next
    }
    throw GoogleQuotaClientError.invalidPagination
  }

  private func fetchMonitoringSeries(
    metricType: String,
    projectID: String,
    accessToken: String,
    intervalStart: Date,
    observedAt: Date
  ) async throws -> [GoogleMonitoringSeries] {
    var pageToken: String?
    var seenTokens = Set<String>()
    var result = [GoogleMonitoringSeries]()

    // Monitoring counts pageSize in points for FULL views. The page and loop
    // bounds together cap each metric query at 100,000 points.
    for _ in 0..<100 {
      var components = URLComponents()
      components.scheme = "https"
      components.host = "monitoring.googleapis.com"
      components.path = "/v3/projects/\(projectID)/timeSeries"
      var queryItems = [
        URLQueryItem(name: "filter", value: "metric.type = \"\(metricType)\""),
        URLQueryItem(name: "interval.startTime", value: ISO8601DateFormatter.providerStandard.string(from: intervalStart)),
        URLQueryItem(name: "interval.endTime", value: ISO8601DateFormatter.providerStandard.string(from: observedAt)),
        URLQueryItem(name: "view", value: "FULL"),
        URLQueryItem(name: "pageSize", value: "1000")
      ]
      if let pageToken {
        queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
      }
      components.queryItems = queryItems
      guard let url = components.url else {
        throw GoogleQuotaClientError.invalidRequest
      }

      var request = URLRequest(url: url)
      request.httpMethod = "GET"
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      let object = try await httpClient.json(
        for: request,
        operation: metricType.hasSuffix("/limit") ? "google.monitoring.limit" : "google.monitoring.usage"
      )
      let page = try GoogleMonitoringPayloadDecoder.decode(object, expectedMetricType: metricType)
      result.append(contentsOf: page.series)

      guard let next = page.nextPageToken, !next.isEmpty else {
        return Self.coalescedMonitoringSeries(result)
      }
      guard next.count <= 2_048, seenTokens.insert(next).inserted else {
        throw GoogleQuotaClientError.invalidPagination
      }
      pageToken = next
    }
    throw GoogleQuotaClientError.invalidPagination
  }

  static func coalescedMonitoringSeries(
    _ series: [GoogleMonitoringSeries]
  ) -> [GoogleMonitoringSeries] {
    let grouped = Dictionary(grouping: series) { item in
      GoogleMonitoringSeriesKey(
        metricType: item.metricType,
        metricKind: item.metricKind,
        metricLabels: item.metricLabels,
        resourceLabels: item.resourceLabels
      )
    }
    return grouped.map { key, fragments in
      let points = Array(Set(fragments.flatMap(\.points))).sorted { lhs, rhs in
        if lhs.end == rhs.end {
          return (lhs.start ?? .distantPast) < (rhs.start ?? .distantPast)
        }
        return lhs.end < rhs.end
      }
      return GoogleMonitoringSeries(
        metricType: key.metricType,
        metricKind: key.metricKind,
        metricLabels: key.metricLabels,
        resourceLabels: key.resourceLabels,
        points: points
      )
    }
  }

  private func failureSnapshot(
    projectID: String,
    observedAt: Date,
    operation: String,
    message: String
  ) -> ProviderSnapshot {
    ProviderSnapshot(
      providerID: providerID,
      scope: .project(projectID.isEmpty ? "Google Cloud project" : projectID),
      sourceKind: .officialDerived,
      observedAt: observedAt,
      windows: [],
      balance: nil,
      metrics: [],
      warnings: [],
      partialFailures: [ProviderFailure(operation: operation, message: message)]
    )
  }

  private static func monitoringIntervalStart(
    for quota: GoogleQuotaInfo,
    observedAt: Date
  ) -> Date? {
    if quota.isConcurrent == true {
      return observedAt.addingTimeInterval(-10 * 60)
    }
    guard let cadence = GoogleQuotaCadence(refreshInterval: quota.refreshInterval) else {
      return nil
    }
    switch cadence {
    case .minute, .concurrent:
      return observedAt.addingTimeInterval(-10 * 60)
    case .hour:
      return observedAt.addingTimeInterval(-2 * 60 * 60)
    case .pacificDay:
      // Covers a Pacific calendar day across the DST fall-back transition.
      return observedAt.addingTimeInterval(-27 * 60 * 60)
    }
  }

  private func deduplicated(_ warnings: [ProviderWarning]) -> [ProviderWarning] {
    var seen = Set<String>()
    return warnings.filter { seen.insert($0.id).inserted }
  }

  private func deduplicated(_ failures: [ProviderFailure]) -> [ProviderFailure] {
    var seen = Set<String>()
    return failures.filter { seen.insert($0.id).inserted }
  }
}

enum GoogleQuotaClientError: LocalizedError, Equatable {
  case invalidProject
  case expiredAccessToken
  case invalidRequest
  case invalidQuotaResponse
  case invalidMonitoringResponse
  case invalidPagination

  var errorDescription: String? {
    switch self {
    case .invalidProject:
      "Enter a valid Google Cloud project ID or project number."
    case .expiredAccessToken:
      "The in-memory Google access token expired. Connect Google again."
    case .invalidRequest:
      "The Google quota request could not be created."
    case .invalidQuotaResponse:
      "Cloud Quotas returned an unsupported response."
    case .invalidMonitoringResponse:
      "Cloud Monitoring returned an unsupported response."
    case .invalidPagination:
      "Google returned invalid or excessive pagination."
    }
  }
}

struct GoogleQuotaPage {
  let quotaInfos: [GoogleQuotaInfo]
  let nextPageToken: String?
}

struct GoogleQuotaInfo: Hashable {
  let quotaID: String
  let metric: String
  let displayName: String
  let metricUnit: String
  let refreshInterval: String?
  let isPrecise: Bool?
  let dimensions: [String]
  let isConcurrent: Bool?
  let dimensionInfos: [GoogleQuotaDimensionInfo]

  init(
    quotaID: String,
    metric: String,
    displayName: String,
    metricUnit: String,
    refreshInterval: String?,
    isPrecise: Bool?,
    dimensions: [String] = [],
    isConcurrent: Bool? = nil,
    dimensionInfos: [GoogleQuotaDimensionInfo]
  ) {
    self.quotaID = quotaID
    self.metric = metric
    self.displayName = displayName
    self.metricUnit = metricUnit
    self.refreshInterval = refreshInterval
    self.isPrecise = isPrecise
    self.dimensions = dimensions
    self.isConcurrent = isConcurrent
    self.dimensionInfos = dimensionInfos
  }
}

struct GoogleQuotaDimensionInfo: Hashable {
  let dimensions: [String: String]
  let effectiveLimit: Double?
  let applicableLocations: [String]
}

enum GoogleQuotaPayloadDecoder {
  static func decode(_ object: Any) throws -> GoogleQuotaPage {
    guard let root = object as? [String: Any] else {
      throw GoogleQuotaClientError.invalidQuotaResponse
    }
    let rawInfos: [Any]
    if let raw = root["quotaInfos"] {
      guard let decoded = raw as? [Any] else {
        throw GoogleQuotaClientError.invalidQuotaResponse
      }
      rawInfos = decoded
    } else {
      rawInfos = []
    }
    var infos = [GoogleQuotaInfo]()

    for raw in rawInfos {
      guard let dictionary = raw as? [String: Any],
            let quotaID = dictionary["quotaId"] as? String,
            GoogleQuotaValidation.validQuotaID(quotaID),
            let metric = dictionary["metric"] as? String,
            GoogleQuotaMetricPair(quotaMetric: metric) != nil
      else { throw GoogleQuotaClientError.invalidQuotaResponse }

      let displayName = [
        dictionary["quotaDisplayName"] as? String,
        dictionary["metricDisplayName"] as? String,
        quotaID
      ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty }) ?? quotaID
      let unit: String
      if let rawUnit = dictionary["metricUnit"] {
        guard let value = rawUnit as? String,
              let safe = GoogleQuotaValidation.safeDisplayText(value, maximumLength: 128)
        else { throw GoogleQuotaClientError.invalidQuotaResponse }
        unit = safe
      } else {
        unit = "units"
      }
      let refreshInterval: String?
      if let rawRefresh = dictionary["refreshInterval"] {
        guard let value = rawRefresh as? String,
              let safe = GoogleQuotaValidation.safeDuration(value)
        else { throw GoogleQuotaClientError.invalidQuotaResponse }
        refreshInterval = safe
      } else {
        refreshInterval = nil
      }
      let isPrecise: Bool?
      if let rawPrecise = dictionary["isPrecise"] {
        guard let value = ProviderJSON.bool(rawPrecise) else {
          throw GoogleQuotaClientError.invalidQuotaResponse
        }
        isPrecise = value
      } else {
        isPrecise = nil
      }
      let rawDimensionNames: [Any]
      if let raw = dictionary["dimensions"] {
        guard let values = raw as? [Any] else { throw GoogleQuotaClientError.invalidQuotaResponse }
        rawDimensionNames = values
      } else {
        rawDimensionNames = []
      }
      let dimensions = rawDimensionNames.compactMap { raw -> String? in
        guard let value = raw as? String, GoogleQuotaValidation.validLabelKey(value) else { return nil }
        return value
      }
      guard dimensions.count == rawDimensionNames.count else {
        throw GoogleQuotaClientError.invalidQuotaResponse
      }
      let isConcurrent: Bool?
      if let rawConcurrent = dictionary["isConcurrent"] {
        guard let value = ProviderJSON.bool(rawConcurrent) else {
          throw GoogleQuotaClientError.invalidQuotaResponse
        }
        isConcurrent = value
      } else {
        isConcurrent = nil
      }
      let rawDimensions: [Any]
      if let raw = dictionary["dimensionsInfos"] {
        guard let values = raw as? [Any] else { throw GoogleQuotaClientError.invalidQuotaResponse }
        rawDimensions = values
      } else {
        rawDimensions = []
      }
      var dimensionInfos = try rawDimensions.map(decodeDimensionInfo)
      if dimensionInfos.isEmpty {
        dimensionInfos = [
          GoogleQuotaDimensionInfo(dimensions: [:], effectiveLimit: nil, applicableLocations: [])
        ]
      }

      infos.append(
        GoogleQuotaInfo(
          quotaID: quotaID,
          metric: metric,
          displayName: GoogleQuotaValidation.safeDisplayText(displayName, maximumLength: 256) ?? quotaID,
          metricUnit: unit,
          refreshInterval: refreshInterval,
          isPrecise: isPrecise,
          dimensions: dimensions,
          isConcurrent: isConcurrent,
          dimensionInfos: dimensionInfos
        )
      )
    }

    let token: String?
    if let rawToken = root["nextPageToken"] {
      guard let value = rawToken as? String else { throw GoogleQuotaClientError.invalidQuotaResponse }
      token = value.isEmpty ? nil : value
    } else {
      token = nil
    }
    return GoogleQuotaPage(quotaInfos: infos, nextPageToken: token)
  }

  private static func decodeDimensionInfo(_ raw: Any) throws -> GoogleQuotaDimensionInfo {
    guard let dictionary = raw as? [String: Any] else {
      throw GoogleQuotaClientError.invalidQuotaResponse
    }
    let rawDimensions: [String: Any]
    if let raw = dictionary["dimensions"] {
      guard let decoded = raw as? [String: Any] else {
        throw GoogleQuotaClientError.invalidQuotaResponse
      }
      rawDimensions = decoded
    } else {
      rawDimensions = [:]
    }
    var dimensions = [String: String]()
    for (key, rawValue) in rawDimensions {
      guard GoogleQuotaValidation.validLabelKey(key),
            let value = ProviderJSON.string(rawValue),
            let safeValue = GoogleQuotaValidation.safeLabelValue(value)
      else {
        throw GoogleQuotaClientError.invalidQuotaResponse
      }
      dimensions[key] = safeValue
    }

    let details: [String: Any]?
    if let raw = dictionary["details"] {
      guard let decoded = raw as? [String: Any] else {
        throw GoogleQuotaClientError.invalidQuotaResponse
      }
      details = decoded
    } else {
      details = nil
    }
    let effectiveLimit: Double?
    if let raw = details?["value"], !(raw is NSNull) {
      guard let value = ProviderJSON.number(raw), value >= 0 else {
        throw GoogleQuotaClientError.invalidQuotaResponse
      }
      effectiveLimit = value
    } else {
      effectiveLimit = nil
    }
    let rawLocations: [Any]
    if let raw = dictionary["applicableLocations"] {
      guard let decoded = raw as? [Any] else {
        throw GoogleQuotaClientError.invalidQuotaResponse
      }
      rawLocations = decoded
    } else {
      rawLocations = []
    }
    let locations: [String] = rawLocations.compactMap { raw -> String? in
      guard let value = raw as? String else { return nil }
      return GoogleQuotaValidation.safeLabelValue(value)
    }
    guard locations.count == rawLocations.count else {
      throw GoogleQuotaClientError.invalidQuotaResponse
    }
    return GoogleQuotaDimensionInfo(
      dimensions: dimensions,
      effectiveLimit: effectiveLimit,
      applicableLocations: locations
    )
  }
}

struct GoogleMonitoringPage {
  let series: [GoogleMonitoringSeries]
  let nextPageToken: String?
}

enum GoogleMetricKind: String, Hashable {
  case delta = "DELTA"
  case gauge = "GAUGE"
  case cumulative = "CUMULATIVE"
  case unknown
}

struct GoogleMonitoringPoint: Hashable {
  let start: Date?
  let end: Date
  let value: Double
}

struct GoogleMonitoringSeries: Hashable {
  let metricType: String
  let metricKind: GoogleMetricKind
  let metricLabels: [String: String]
  let resourceLabels: [String: String]
  let points: [GoogleMonitoringPoint]

  var coreSignature: String {
    var labels = metricLabels
    labels.removeValue(forKey: "method")
    let metricParts = labels.map { "m:\($0.key)=\($0.value)" }
    let resourceParts = resourceLabels.map { "r:\($0.key)=\($0.value)" }
    return (metricParts + resourceParts).sorted().joined(separator: "|")
  }
}

private struct GoogleMonitoringSeriesKey: Hashable {
  let metricType: String
  let metricKind: GoogleMetricKind
  let metricLabels: [String: String]
  let resourceLabels: [String: String]
}

enum GoogleMonitoringPayloadDecoder {
  static func decode(_ object: Any, expectedMetricType: String) throws -> GoogleMonitoringPage {
    guard let root = object as? [String: Any] else {
      throw GoogleQuotaClientError.invalidMonitoringResponse
    }
    let rawSeries: [Any]
    if let raw = root["timeSeries"] {
      guard let decoded = raw as? [Any] else {
        throw GoogleQuotaClientError.invalidMonitoringResponse
      }
      rawSeries = decoded
    } else {
      rawSeries = []
    }
    var series = [GoogleMonitoringSeries]()

    for raw in rawSeries {
      guard let dictionary = raw as? [String: Any],
            let metric = dictionary["metric"] as? [String: Any],
            let metricType = metric["type"] as? String,
            metricType == expectedMetricType
      else { throw GoogleQuotaClientError.invalidMonitoringResponse }

      let metricLabels = try decodeLabels(metric["labels"])
      let resource: [String: Any]?
      if let rawResource = dictionary["resource"] {
        guard let decoded = rawResource as? [String: Any] else {
          throw GoogleQuotaClientError.invalidMonitoringResponse
        }
        resource = decoded
      } else {
        resource = nil
      }
      let resourceLabels = try decodeLabels(resource?["labels"])
      let kind = GoogleMetricKind(rawValue: dictionary["metricKind"] as? String ?? "") ?? .unknown
      let rawPoints: [Any]
      if let raw = dictionary["points"] {
        guard let decoded = raw as? [Any] else {
          throw GoogleQuotaClientError.invalidMonitoringResponse
        }
        rawPoints = decoded
      } else {
        rawPoints = []
      }
      let points = try rawPoints.map { try decodePoint($0) }
      series.append(
        GoogleMonitoringSeries(
          metricType: metricType,
          metricKind: kind,
          metricLabels: metricLabels,
          resourceLabels: resourceLabels,
          points: points
        )
      )
    }

    let token: String?
    if let rawToken = root["nextPageToken"] {
      guard let value = rawToken as? String else {
        throw GoogleQuotaClientError.invalidMonitoringResponse
      }
      token = value.isEmpty ? nil : value
    } else {
      token = nil
    }
    return GoogleMonitoringPage(series: series, nextPageToken: token)
  }

  private static func decodeLabels(_ raw: Any?) throws -> [String: String] {
    guard let raw else { return [:] }
    guard let values = raw as? [String: Any] else {
      throw GoogleQuotaClientError.invalidMonitoringResponse
    }
    var result = [String: String]()
    for (key, rawValue) in values {
      guard GoogleQuotaValidation.validLabelKey(key),
            let value = ProviderJSON.string(rawValue),
            let safeValue = GoogleQuotaValidation.safeLabelValue(value)
      else {
        throw GoogleQuotaClientError.invalidMonitoringResponse
      }
      result[key] = safeValue
    }
    return result
  }

  private static func decodePoint(_ raw: Any) throws -> GoogleMonitoringPoint {
    guard let dictionary = raw as? [String: Any],
          let interval = dictionary["interval"] as? [String: Any],
          let end = GoogleQuotaValidation.date(interval["endTime"]),
          let valueObject = dictionary["value"] as? [String: Any]
    else {
      throw GoogleQuotaClientError.invalidMonitoringResponse
    }
    let valueKeys = ["doubleValue", "int64Value"].filter(valueObject.keys.contains)
    guard valueKeys.count == 1,
          let value = ProviderJSON.number(valueObject[valueKeys[0]])
    else {
      throw GoogleQuotaClientError.invalidMonitoringResponse
    }
    let start: Date?
    if let rawStart = interval["startTime"] {
      guard let decoded = GoogleQuotaValidation.date(rawStart) else {
        throw GoogleQuotaClientError.invalidMonitoringResponse
      }
      start = decoded
    } else {
      start = nil
    }
    return GoogleMonitoringPoint(
      start: start,
      end: end,
      value: value
    )
  }
}

struct GoogleQuotaMetricPair: Hashable {
  static let servicePrefix = "generativelanguage.googleapis.com/"

  let limit: String
  let usage: String

  init?(quotaMetric: String) {
    guard quotaMetric.hasPrefix(Self.servicePrefix) else { return nil }
    var suffix = String(quotaMetric.dropFirst(Self.servicePrefix.count))
    if suffix.hasPrefix("quota/") {
      suffix.removeFirst("quota/".count)
    }
    if suffix.hasSuffix("/limit") {
      suffix.removeLast("/limit".count)
    } else if suffix.hasSuffix("/usage") {
      suffix.removeLast("/usage".count)
    }
    guard GoogleQuotaValidation.validMetricSuffix(suffix) else { return nil }
    limit = "\(Self.servicePrefix)quota/\(suffix)/limit"
    usage = "\(Self.servicePrefix)quota/\(suffix)/usage"
  }
}

struct GoogleQuotaDerivationResult {
  let windows: [QuotaWindow]
  let warnings: [ProviderWarning]
}

enum GoogleQuotaDeriver {
  static func derive(
    quota: GoogleQuotaInfo,
    limitSeries: [GoogleMonitoringSeries],
    usageSeries: [GoogleMonitoringSeries],
    now: Date
  ) -> GoogleQuotaDerivationResult {
    let cadence = quota.isConcurrent == true
      ? GoogleQuotaCadence.concurrent
      : GoogleQuotaCadence(refreshInterval: quota.refreshInterval)
    guard let cadence else {
      let windows = quota.dimensionInfos.enumerated().map { index, dimension in
        unavailableWindow(
          quota: quota,
          dimension: dimension,
          index: index,
          limit: dimension.effectiveLimit,
          resetsAt: nil
        )
      }
      return GoogleQuotaDerivationResult(
        windows: windows,
        warnings: [
          ProviderWarning(
            id: "google-refresh-\(GoogleQuotaValidation.operationSlug(quota.quotaID))",
            message: "\(quota.displayName) has an unknown refresh interval; remaining is unavailable."
          )
        ]
      )
    }

    var windows = [QuotaWindow]()
    var warnings = [ProviderWarning]()
    let currentBounds = cadence.bounds(containing: now)
    if quota.isPrecise == false {
      warnings.append(
        ProviderWarning(
          id: "google-imprecise-\(GoogleQuotaValidation.operationSlug(quota.quotaID))",
          message: "\(quota.displayName) is marked imprecise by Cloud Quotas."
        )
      )
    }

    let exactLimitSeries = limitSeries.filter { belongsToQuota($0, quota: quota) }
    let exactUsageSeries = usageSeries.filter { belongsToQuota($0, quota: quota) }
    if (!limitSeries.isEmpty || !usageSeries.isEmpty)
      && exactLimitSeries.isEmpty
      && exactUsageSeries.isEmpty {
      warnings.append(
        ProviderWarning(
          id: "google-limit-name-\(GoogleQuotaValidation.operationSlug(quota.quotaID))",
          message: "\(quota.displayName) could not be matched to Monitoring limit_name; remaining is unavailable."
        )
      )
    }

    for (dimensionIndex, dimension) in quota.dimensionInfos.enumerated() {
      let matchingLimits = assignedSeries(exactLimitSeries, quota: quota, dimensionIndex: dimensionIndex)
      let matchingUsage = assignedSeries(exactUsageSeries, quota: quota, dimensionIndex: dimensionIndex)
      let limitGroups = Dictionary(grouping: matchingLimits) { signature($0, quota: quota) }
      let usageGroups = Dictionary(grouping: matchingUsage) { signature($0, quota: quota) }
      var signatures = Set(limitGroups.keys).union(usageGroups.keys)
      if signatures.isEmpty {
        signatures.insert("")
      }

      for (signatureIndex, signature) in signatures.sorted().enumerated() {
        let usageForSignature = usageGroups[signature] ?? []
        let boundsResult = derivationBounds(
          cadence: cadence,
          usageSeries: usageForSignature,
          now: now
        )
        let bounds = boundsResult.bounds
        let monitoredLimit = latestLimit(
          from: limitGroups[signature] ?? [],
          bounds: boundsResult.isHistorical ? bounds : currentBounds
        )
        let limit: Double?
        if let effective = dimension.effectiveLimit,
           let monitoredLimit,
           !approximatelyEqual(effective, monitoredLimit) {
          limit = nil
          warnings.append(
            ProviderWarning(
              id: "google-limit-mismatch-\(GoogleQuotaValidation.operationSlug(quota.quotaID))-\(dimensionIndex)-\(signatureIndex)",
              message: "\(quota.displayName) has conflicting Cloud Quotas and Monitoring limits; remaining is unavailable."
            )
          )
        } else if boundsResult.isHistorical {
          // A current Cloud Quotas value has no historical validity timestamp.
          // Short-window historical usage therefore requires a Monitoring limit
          // at or before the same as-of boundary before remaining is derivable.
          limit = monitoredLimit
        } else {
          limit = dimension.effectiveLimit ?? monitoredLimit
        }
        let usage = aggregateUsage(
          from: usageForSignature,
          bounds: bounds,
          concurrent: quota.isConcurrent == true
        )
        let remaining = limit.flatMap { limit in usage.map { limit - $0 } }
        let usedPercentage = percentage(usage, of: limit)
        let remainingPercentage = percentage(remaining, of: limit)
        let labelSuffix = displayDimensions(
          dimension: dimension,
          signature: signature,
          cadence: cadence,
          historicalAsOf: boundsResult.isHistorical ? bounds.end : nil
        )

        windows.append(
          QuotaWindow(
            id: [
              "google",
              GoogleQuotaValidation.operationSlug(quota.quotaID),
              String(dimensionIndex),
              String(signatureIndex)
            ].joined(separator: "-"),
            label: labelSuffix.isEmpty ? quota.displayName : "\(quota.displayName) · \(labelSuffix)",
            used: usage,
            limit: limit,
            remaining: remaining,
            usedPercentage: usedPercentage,
            remainingPercentage: remainingPercentage,
            resetsAt: cadence.resetDate(from: bounds),
            unit: quota.metricUnit,
            isEstimated: true
          )
        )

        if usage == nil {
          warnings.append(
            ProviderWarning(
              id: [
                "google-no-usage",
                GoogleQuotaValidation.operationSlug(quota.quotaID),
                String(dimensionIndex),
                String(signatureIndex)
              ].joined(separator: "-"),
              message: "\(quota.displayName) has no reliably matched usage series for this window."
            )
          )
        }
        if boundsResult.isHistorical {
          warnings.append(
            ProviderWarning(
              id: [
                "google-historical-window",
                GoogleQuotaValidation.operationSlug(quota.quotaID),
                String(dimensionIndex),
                String(signatureIndex)
              ].joined(separator: "-"),
              message: "\(quota.displayName) uses the latest complete Monitoring window ending \(ISO8601DateFormatter.providerStandard.string(from: bounds.end)); it is delayed historical usage, not a live current-window balance."
            )
          )
        }
        if limit == nil {
          warnings.append(
            ProviderWarning(
              id: [
                "google-no-limit",
                GoogleQuotaValidation.operationSlug(quota.quotaID),
                String(dimensionIndex),
                String(signatureIndex)
              ].joined(separator: "-"),
              message: "\(quota.displayName) has no reliably matched active limit."
            )
          )
        }
      }
    }
    return GoogleQuotaDerivationResult(windows: windows, warnings: warnings)
  }

  static func windowOrder(_ lhs: QuotaWindow, _ rhs: QuotaWindow) -> Bool {
    let left = lhs.remainingPercentage ?? .greatestFiniteMagnitude
    let right = rhs.remainingPercentage ?? .greatestFiniteMagnitude
    if left == right { return lhs.label < rhs.label }
    return left < right
  }

  private static func matches(
    _ series: GoogleMonitoringSeries,
    dimension: GoogleQuotaDimensionInfo
  ) -> Bool {
    for (key, expected) in dimension.dimensions {
      let actual: String?
      if key == "region" || key == "zone" {
        actual = series.metricLabels[key]
          ?? series.resourceLabels[key]
          ?? series.metricLabels["location"]
          ?? series.resourceLabels["location"]
      } else {
        actual = series.metricLabels[key] ?? series.resourceLabels[key]
      }
      guard actual == expected else { return false }
    }
    guard !dimension.applicableLocations.isEmpty else { return true }
    let location = series.metricLabels["location"] ?? series.resourceLabels["location"]
    return location.map(dimension.applicableLocations.contains) == true
  }

  private static func belongsToQuota(
    _ series: GoogleMonitoringSeries,
    quota: GoogleQuotaInfo
  ) -> Bool {
    let limitName = series.metricLabels["limit_name"] ?? series.resourceLabels["limit_name"]
    return limitName == quota.quotaID
  }

  private static func assignedSeries(
    _ series: [GoogleMonitoringSeries],
    quota: GoogleQuotaInfo,
    dimensionIndex: Int
  ) -> [GoogleMonitoringSeries] {
    series.filter { item in
      // Cloud Quotas guarantees dimensionInfos are ordered from most to least
      // specific. Assign each series exactly once to the first matching entry.
      quota.dimensionInfos.indices.first(where: { index in
        matches(item, dimension: quota.dimensionInfos[index])
      }) == dimensionIndex
    }
  }

  private static func signature(
    _ series: GoogleMonitoringSeries,
    quota: GoogleQuotaInfo
  ) -> String {
    var keys = Set(quota.dimensions)
    quota.dimensionInfos.forEach { keys.formUnion($0.dimensions.keys) }
    keys.remove("method")
    keys.insert("limit_name")
    keys.insert("location")
    return keys.sorted().compactMap { key in
      let value = series.metricLabels[key] ?? series.resourceLabels[key]
      return value.map { "\(key)=\($0)" }
    }.joined(separator: "|")
  }

  private static func latestLimit(
    from series: [GoogleMonitoringSeries],
    bounds: GoogleQuotaBounds
  ) -> Double? {
    let values = series.compactMap { item -> (Date, Double)? in
      guard item.metricKind == .gauge,
            let point = item.points
              .filter({ $0.end <= bounds.end && $0.value >= 0 })
              .max(by: { $0.end < $1.end })
      else {
        return nil
      }
      return (point.end, point.value)
    }
    guard !values.isEmpty else { return nil }
    let newest = values.max(by: { $0.0 < $1.0 })!
    let contemporaneous = values.filter { abs($0.0.timeIntervalSince(newest.0)) < 1 }
    let unique = Set(contemporaneous.map(\.1))
    return unique.count == 1 ? newest.1 : nil
  }

  private static func aggregateUsage(
    from series: [GoogleMonitoringSeries],
    bounds: GoogleQuotaBounds,
    concurrent: Bool
  ) -> Double? {
    guard !series.isEmpty else { return nil }
    var values = [Double]()
    for item in series {
      if concurrent && item.metricKind != .gauge { return nil }
      switch item.metricKind {
      case .delta:
        let completePoints = item.points.filter { point in
          guard let pointStart = point.start else { return false }
          return pointStart >= bounds.start
            && point.end <= bounds.end
            && point.end > pointStart
            && point.value >= 0
        }
        guard !completePoints.isEmpty else { return nil }
        values.append(completePoints.reduce(0) { $0 + $1.value })
      case .gauge:
        guard let point = item.points
          .filter({ $0.end >= bounds.start && $0.end <= bounds.end && $0.value >= 0 })
          .max(by: { $0.end < $1.end })
        else {
          return nil
        }
        values.append(point.value)
      case .cumulative, .unknown:
        return nil
      }
    }
    return values.reduce(0, +)
  }

  private static func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
    abs(lhs - rhs) <= max(0.000_001, max(abs(lhs), abs(rhs)) * 0.000_001)
  }

  private static func percentage(_ value: Double?, of limit: Double?) -> Double? {
    guard let value, let limit, limit > 0 else { return nil }
    return value / limit * 100
  }

  private static func unavailableWindow(
    quota: GoogleQuotaInfo,
    dimension: GoogleQuotaDimensionInfo,
    index: Int,
    limit: Double?,
    resetsAt: Date?
  ) -> QuotaWindow {
    QuotaWindow(
      id: "google-\(GoogleQuotaValidation.operationSlug(quota.quotaID))-\(index)",
      label: quota.displayName,
      used: nil,
      limit: limit,
      remaining: nil,
      usedPercentage: nil,
      remainingPercentage: nil,
      resetsAt: resetsAt,
      unit: quota.metricUnit,
      isEstimated: true
    )
  }

  private static func displayDimensions(
    dimension: GoogleQuotaDimensionInfo,
    signature: String,
    cadence: GoogleQuotaCadence,
    historicalAsOf: Date?
  ) -> String {
    var values = dimension.dimensions
      .sorted(by: { $0.key < $1.key })
      .map { "\($0.key): \($0.value)" }
    if values.isEmpty, !signature.isEmpty {
      let model = signature.split(separator: "|")
        .first(where: { $0.hasPrefix("model=") })
        .map { String($0.dropFirst("model=".count)) }
      if let model { values.append("model: \(model)") }
    }
    values.append(cadence.label)
    if let historicalAsOf {
      values.append("as of \(ISO8601DateFormatter.providerStandard.string(from: historicalAsOf))")
    }
    return values.joined(separator: " · ")
  }

  private static func derivationBounds(
    cadence: GoogleQuotaCadence,
    usageSeries: [GoogleMonitoringSeries],
    now: Date
  ) -> (bounds: GoogleQuotaBounds, isHistorical: Bool) {
    let defaultBounds = cadence.bounds(containing: now)
    let windowDuration: TimeInterval
    let maximumAge: TimeInterval
    switch cadence {
    case .minute:
      windowDuration = 60
      maximumAge = 10 * 60
    case .hour:
      windowDuration = 60 * 60
      maximumAge = 2 * 60 * 60
    case .pacificDay, .concurrent:
      return (defaultBounds, false)
    }

    guard !usageSeries.isEmpty,
          usageSeries.allSatisfy({ $0.metricKind == .delta })
    else {
      return (defaultBounds, false)
    }
    let latestVisibleEnds = usageSeries.compactMap { series in
      series.points
        .filter { point in
          guard let start = point.start else { return false }
          return start < point.end && point.end <= now && point.value >= 0
        }
        .map(\.end)
        .max()
    }
    guard latestVisibleEnds.count == usageSeries.count,
          let asOf = latestVisibleEnds.min(),
          now.timeIntervalSince(asOf) >= 0,
          now.timeIntervalSince(asOf) <= maximumAge
    else {
      return (defaultBounds, false)
    }
    return (
      GoogleQuotaBounds(
        start: asOf.addingTimeInterval(-windowDuration),
        end: asOf,
        reset: nil
      ),
      true
    )
  }
}

struct GoogleQuotaBounds: Hashable {
  let start: Date
  let end: Date
  let reset: Date?
}

enum GoogleQuotaCadence: Hashable {
  case minute
  case hour
  case pacificDay
  case concurrent

  init?(refreshInterval: String?) {
    guard let refreshInterval,
          let seconds = GoogleQuotaValidation.durationSeconds(refreshInterval)
    else {
      return nil
    }
    switch seconds {
    case 60:
      self = .minute
    case 3_600:
      self = .hour
    case 86_400:
      self = .pacificDay
    default:
      return nil
    }
  }

  var label: String {
    switch self {
    case .minute: "per minute"
    case .hour: "per hour"
    case .pacificDay: "per Pacific day"
    case .concurrent: "concurrent"
    }
  }

  func bounds(containing date: Date) -> GoogleQuotaBounds {
    switch self {
    case .minute:
      return GoogleQuotaBounds(start: date.addingTimeInterval(-60), end: date, reset: nil)
    case .hour:
      return GoogleQuotaBounds(start: date.addingTimeInterval(-3_600), end: date, reset: nil)
    case .pacificDay:
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
      let start = calendar.startOfDay(for: date)
      let next = calendar.date(byAdding: .day, value: 1, to: start)
      return GoogleQuotaBounds(start: start, end: date, reset: next)
    case .concurrent:
      return GoogleQuotaBounds(start: date.addingTimeInterval(-5 * 60), end: date, reset: nil)
    }
  }

  func resetDate(from bounds: GoogleQuotaBounds) -> Date? {
    switch self {
    case .minute, .hour, .concurrent:
      // RPM/TPM-style quotas are rolling windows, so there is no single trustworthy reset instant.
      nil
    case .pacificDay:
      bounds.reset
    }
  }
}

enum GoogleQuotaValidation {
  static func validProjectID(_ value: String) -> Bool {
    value.range(of: #"^[a-z][a-z0-9-]{4,28}[a-z0-9]$"#, options: .regularExpression) != nil
      || value.range(of: #"^[0-9]{6,32}$"#, options: .regularExpression) != nil
  }

  static func validQuotaID(_ value: String) -> Bool {
    !value.isEmpty
      && value.count <= 256
      && value.range(of: #"^[A-Za-z0-9_./:\-]+$"#, options: .regularExpression) != nil
  }

  static func validMetricSuffix(_ value: String) -> Bool {
    !value.isEmpty
      && value.count <= 512
      && !value.hasPrefix("/")
      && !value.hasSuffix("/")
      && !value.contains("..")
      && value.range(of: #"^[A-Za-z0-9_./-]+$"#, options: .regularExpression) != nil
  }

  static func validLabelKey(_ value: String) -> Bool {
    !value.isEmpty
      && value.count <= 128
      && value.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
  }

  static func safeLabelValue(_ value: String) -> String? {
    safeDisplayText(value, maximumLength: 512)
  }

  static func safeDisplayText(_ value: String, maximumLength: Int) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          trimmed.count <= maximumLength,
          !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
      return nil
    }
    return trimmed
  }

  static func safeDuration(_ value: String) -> String? {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return durationSeconds(normalized) == nil ? nil : normalized
  }

  static func durationSeconds(_ value: String) -> Int? {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch normalized {
    case "minute", "1 minute":
      return 60
    case "hour", "1 hour":
      return 3_600
    case "day", "1 day":
      return 86_400
    default:
      break
    }
    if normalized.range(of: #"^[0-9]{1,9}s$"#, options: .regularExpression) != nil {
      return Int(normalized.dropLast())
    }
    if let match = normalized.wholeMatch(of: #/^([0-9]{1,9}) seconds?$/#) {
      return Int(match.1)
    }
    return nil
  }

  static func date(_ value: Any?) -> Date? {
    guard let value = ProviderJSON.string(value) else { return nil }
    return ISO8601DateFormatter.providerFlexible.date(from: value)
      ?? ISO8601DateFormatter.providerStandard.date(from: value)
  }

  static func operationSlug(_ value: String) -> String {
    let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
      CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "-"
    }
    let slug = String(scalars)
      .split(separator: "-", omittingEmptySubsequences: true)
      .joined(separator: "-")
    return String((slug.isEmpty ? "quota" : slug).prefix(80))
  }
}

private struct ManualReading {
  let used: Double?
  let limit: Double?
  let remaining: Double?

  init(context: GoogleConsumerManualContext) {
    var normalizedUsed = context.used.flatMap { $0.isFinite ? $0 : nil }
    var normalizedLimit = context.limit.flatMap { $0.isFinite ? $0 : nil }
    var normalizedRemaining = context.remaining.flatMap { $0.isFinite ? $0 : nil }
    if normalizedLimit == nil, let normalizedUsed, let normalizedRemaining {
      let candidate = normalizedUsed + normalizedRemaining
      normalizedLimit = candidate.isFinite ? candidate : nil
    }
    if normalizedUsed == nil, let normalizedLimit, let normalizedRemaining {
      let candidate = normalizedLimit - normalizedRemaining
      normalizedUsed = candidate.isFinite ? candidate : nil
    }
    if normalizedRemaining == nil, let normalizedLimit, let normalizedUsed {
      let candidate = normalizedLimit - normalizedUsed
      normalizedRemaining = candidate.isFinite ? candidate : nil
    }
    used = normalizedUsed
    limit = normalizedLimit
    remaining = normalizedRemaining
  }

  var hasAnyValue: Bool {
    used != nil || limit != nil || remaining != nil
  }

  var usedPercentage: Double? {
    guard let used, let limit, limit > 0 else { return nil }
    let percentage = used / limit * 100
    return percentage.isFinite ? percentage : nil
  }

  var remainingPercentage: Double? {
    guard let remaining, let limit, limit > 0 else { return nil }
    let percentage = remaining / limit * 100
    return percentage.isFinite ? percentage : nil
  }

  var isInconsistent: Bool {
    guard let used, let limit, let remaining else { return false }
    let reconstructedLimit = used + remaining
    guard reconstructedLimit.isFinite else { return true }
    let tolerance = max(0.000_001, abs(limit) * 0.000_001)
    let delta = reconstructedLimit - limit
    guard delta.isFinite else { return true }
    return abs(delta) > tolerance
  }
}
