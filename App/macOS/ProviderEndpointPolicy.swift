import Foundation

enum ProviderEndpointPolicy {
  static func allows(_ request: URLRequest) -> Bool {
    guard let url = request.url,
          url.scheme?.lowercased() == "https",
          clean(url),
          let host = url.host?.lowercased(),
          let method = request.httpMethod?.uppercased()
    else {
      return false
    }

    switch host {
    case "chatgpt.com":
      return allowsCodexDesktop(url: url, method: method, body: request.httpBody)
    case "api.chatgpt.com":
      return allowsCodexAnalytics(url: url, method: method, body: request.httpBody)
    case "openrouter.ai":
      return allowsOpenRouter(request: request, url: url, method: method)
    case "oauth2.googleapis.com":
      return allowsGoogleToken(request: request, url: url, method: method)
    case "cloudquotas.googleapis.com":
      return allowsGoogleQuotas(url: url, method: method, body: request.httpBody)
    case "monitoring.googleapis.com":
      return allowsGoogleMonitoring(url: url, method: method, body: request.httpBody)
    default:
      return false
    }
  }

  static func sanitizeIdentifier(_ value: String, maximumLength: Int = 128) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          trimmed != ".",
          trimmed != "..",
          trimmed.count <= maximumLength,
          trimmed.range(of: #"^[A-Za-z0-9_.:\-]+$"#, options: .regularExpression) != nil
    else {
      return nil
    }
    return trimmed
  }

    static func isOpenRouterGenerationID(_ value: String) -> Bool {
        let bytes = value.utf8
        return value != "."
            && value != ".."
            && !bytes.isEmpty
            && bytes.count <= 512
            && bytes.allSatisfy { (0x21...0x7E).contains($0) }
    }

  private static func allowsCodexDesktop(url: URL, method: String, body: Data?) -> Bool {
    method == "GET"
      && body == nil
      && url.query == nil
      && [
        "/backend-api/wham/usage",
        "/backend-api/wham/rate-limit-reset-credits"
      ].contains(percentEncodedPath(url))
  }

  private static func allowsCodexAnalytics(url: URL, method: String, body: Data?) -> Bool {
    guard method == "GET", body == nil else { return false }
    let segments = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    guard segments.count == 6,
          Array(segments.prefix(4)) == ["v1", "analytics", "codex", "workspaces"],
          segments[5] == "usage",
          sanitizeIdentifier(segments[4]) == segments[4]
    else {
      return false
    }

    return validateQuery(url, allowedNames: ["start_time", "end_time", "group_by", "group", "limit", "page"]) { item in
      guard let value = item.value else { return false }
      switch item.name {
      case "start_time", "end_time":
        return value.range(of: #"^\d{1,12}$"#, options: .regularExpression) != nil
      case "group_by":
        return value == "day" || value == "week"
      case "group":
        return value == "workspace" || value.isEmpty
      case "limit":
        guard let limit = Int(value) else { return false }
        return (1...500).contains(limit)
      case "page":
        return sanitizeIdentifier(value) == value
      default:
        return false
      }
    }
  }

  private static func allowsOpenRouter(request: URLRequest, url: URL, method: String) -> Bool {
    switch (method, percentEncodedPath(url)) {
    case ("GET", "/api/v1/key"),
         ("GET", "/api/v1/credits"),
         ("GET", "/api/v1/analytics/meta"):
      return request.httpBody == nil && url.query == nil
    case ("POST", "/api/v1/auth/keys"):
      return url.query == nil
        && isContentType(request, "application/json")
        && validOpenRouterOAuthBody(request.httpBody)
    case ("POST", "/api/v1/analytics/query"):
      return url.query == nil
        && isContentType(request, "application/json")
        && validOpenRouterAnalyticsBody(request.httpBody)
    case ("GET", "/api/v1/activity"):
      guard request.httpBody == nil else { return false }
      return validateQuery(url, allowedNames: ["date", "api_key_hash", "user_id"]) { item in
        guard let value = item.value else { return false }
        switch item.name {
        case "date":
          return value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        case "api_key_hash":
          return value.range(of: #"^[a-f0-9]{64}$"#, options: [.regularExpression, .caseInsensitive]) != nil
        case "user_id":
          return sanitizeIdentifier(value) == value
        default:
          return false
        }
      }
    case ("GET", "/api/v1/generation"):
      guard request.httpBody == nil else { return false }
      return validateQuery(url, allowedNames: ["id"], requiredNames: ["id"]) { item in
        guard let value = item.value else { return false }
        return isOpenRouterGenerationID(value)
      }
    default:
      return false
    }
  }

  private static func allowsGoogleToken(request: URLRequest, url: URL, method: String) -> Bool {
    method == "POST"
      && percentEncodedPath(url) == "/token"
      && url.query == nil
      && isContentType(request, "application/x-www-form-urlencoded")
      && validGoogleTokenBody(request.httpBody)
  }

  private static func allowsGoogleQuotas(url: URL, method: String, body: Data?) -> Bool {
    guard method == "GET", body == nil else { return false }
    let segments = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    guard segments.count == 8,
          segments[0] == "v1",
          segments[1] == "projects",
          sanitizeIdentifier(segments[2]) == segments[2],
          Array(segments[3...7]) == ["locations", "global", "services", "generativelanguage.googleapis.com", "quotaInfos"]
    else {
      return false
    }

    return validateQuery(url, allowedNames: ["pageSize", "pageToken"]) { item in
      guard let value = item.value else { return false }
      if item.name == "pageSize" {
        guard let size = Int(value) else { return false }
        return (1...1000).contains(size)
      }
      return !value.isEmpty && value.count <= 2048
    }
  }

  private static func allowsGoogleMonitoring(url: URL, method: String, body: Data?) -> Bool {
    guard method == "GET", body == nil else { return false }
    let segments = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    guard segments.count == 4,
          Array(segments.prefix(2)) == ["v3", "projects"],
          sanitizeIdentifier(segments[2]) == segments[2],
          segments[3] == "timeSeries"
    else {
      return false
    }

    return validateQuery(
      url,
      allowedNames: ["filter", "interval.startTime", "interval.endTime", "view", "pageSize", "pageToken"],
      requiredNames: ["filter", "interval.startTime", "interval.endTime", "view"]
    ) { item in
      guard let value = item.value, !value.isEmpty else { return false }
      switch item.name {
      case "filter":
        return value.count <= 1024
          && value.range(
            of: #"^metric\.type = \"generativelanguage\.googleapis\.com/quota/[A-Za-z0-9_./-]+/(limit|usage)\"$"#,
            options: .regularExpression
          ) != nil
      case "interval.startTime", "interval.endTime":
        return ISO8601DateFormatter().date(from: value) != nil
      case "view":
        return value == "FULL"
      case "pageSize":
        guard let size = Int(value) else { return false }
        return (1...10_000).contains(size)
      case "pageToken":
        return value.count <= 2048
      default:
        return false
      }
    }
  }

  private static func clean(_ url: URL) -> Bool {
    let rawPath = percentEncodedPath(url)
    let pathSegments = rawPath.split(separator: "/", omittingEmptySubsequences: false)
    return (url.port == nil || url.port == 443)
      && url.user == nil
      && url.password == nil
      && url.fragment == nil
      && !rawPath.hasSuffix("/")
      && !rawPath.contains("//")
      && !rawPath.contains("%")
      && pathSegments.allSatisfy { $0 != "." && $0 != ".." }
  }

  private static func isContentType(_ request: URLRequest, _ expected: String) -> Bool {
    request.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix(expected) == true
  }

  private static func validOpenRouterOAuthBody(_ data: Data?) -> Bool {
    guard let object = jsonDictionary(data),
          Set(object.keys) == ["code", "code_verifier", "code_challenge_method"],
          let code = object["code"] as? String,
          !code.isEmpty,
          code.count <= 2_048,
          let verifier = object["code_verifier"] as? String,
          (43...128).contains(verifier.count),
          verifier.range(of: #"^[A-Za-z0-9._~-]+$"#, options: .regularExpression) != nil,
          object["code_challenge_method"] as? String == "S256"
    else {
      return false
    }
    return !code.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
  }

  private static func validOpenRouterAnalyticsBody(_ data: Data?) -> Bool {
    guard let object = jsonDictionary(data) else { return false }
    let required: Set<String> = ["metrics", "limit", "time_range"]
    let allowed = required.union(["dimensions", "granularity", "group_limit"])
    guard required.isSubset(of: Set(object.keys)),
          Set(object.keys).isSubset(of: allowed),
          let metrics = object["metrics"] as? [String],
          !metrics.isEmpty,
          metrics.count <= 32,
          metrics.allSatisfy(safeAnalyticsName),
          let limit = ProviderJSON.int(object["limit"]),
          (1...1_000).contains(limit),
          let timeRange = object["time_range"] as? [String: Any],
          Set(timeRange.keys) == ["start", "end"],
          let startValue = timeRange["start"] as? String,
          let endValue = timeRange["end"] as? String,
          let start = ProviderJSON.date(startValue),
          let end = ProviderJSON.date(endValue),
          start < end
    else {
      return false
    }
    let dimensions: [String]
    if let rawDimensions = object["dimensions"] as? [String] {
      guard rawDimensions.count <= 2, rawDimensions.allSatisfy(safeAnalyticsName) else { return false }
      dimensions = rawDimensions
    } else if object["dimensions"] != nil {
      return false
    } else {
      dimensions = []
    }
    let granularity: String?
    if let rawGranularity = object["granularity"] as? String {
      guard ["hour", "day", "week"].contains(rawGranularity) else { return false }
      granularity = rawGranularity
    } else if object["granularity"] != nil {
      return false
    } else {
      granularity = nil
    }
    let groupLimit: Int?
    if let rawGroupLimit = object["group_limit"] {
      guard let parsed = ProviderJSON.int(rawGroupLimit), (1...1_000).contains(parsed) else {
        return false
      }
      groupLimit = parsed
    } else {
      groupLimit = nil
    }
    if dimensions.contains("generation_id") {
      let allowedGenerationMetrics: Set<String> = [
        "total_usage", "usage", "tokens_total", "total_tokens", "request_count"
      ]
      guard dimensions.first == "generation_id",
            Set(dimensions).count == dimensions.count,
            dimensions.dropFirst().allSatisfy({ ["api_key_id", "model"].contains($0) }),
            requestedNamesAreUnique(metrics),
            metrics.count <= 2,
            metrics.allSatisfy(allowedGenerationMetrics.contains),
            groupLimit == 1,
            limit <= 50,
            granularity == "hour" || granularity == "day",
            end.timeIntervalSince(start) <= 31 * 86_400
      else {
        return false
      }
    } else if groupLimit != nil {
      return false
    }
    return true
  }

  private static func requestedNamesAreUnique(_ names: [String]) -> Bool {
    Set(names).count == names.count
  }

  private static func validGoogleTokenBody(_ data: Data?) -> Bool {
    guard let data,
          data.count <= 16_384,
          let body = String(data: data, encoding: .utf8)
    else {
      return false
    }
    var fields: [String: String] = [:]
    for pair in body.split(separator: "&", omittingEmptySubsequences: false) {
      let components = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard components.count == 2,
            let name = decodeFormComponent(String(components[0])),
            let value = decodeFormComponent(String(components[1])),
            fields.updateValue(value, forKey: name) == nil
      else {
        return false
      }
    }
    let required: Set<String> = ["client_id", "code", "code_verifier", "grant_type", "redirect_uri"]
    guard Set(fields.keys) == required,
          fields["grant_type"] == "authorization_code",
          let clientID = fields["client_id"],
          clientID.count <= 512,
          clientID.range(of: #"^[A-Za-z0-9._-]+\.apps\.googleusercontent\.com$"#, options: .regularExpression) != nil,
          let code = fields["code"],
          !code.isEmpty,
          code.count <= 4_096,
          let verifier = fields["code_verifier"],
          (43...128).contains(verifier.count),
          verifier.range(of: #"^[A-Za-z0-9._~-]+$"#, options: .regularExpression) != nil,
          let redirectValue = fields["redirect_uri"],
          let redirect = URL(string: redirectValue),
          redirect.scheme == "http",
          redirect.host == "127.0.0.1",
          redirect.port != nil,
          redirect.path.hasPrefix("/dashis/google/oauth/"),
          redirect.query == nil,
          redirect.fragment == nil,
          redirect.user == nil,
          redirect.password == nil
    else {
      return false
    }
    return !code.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
  }

  private static func jsonDictionary(_ data: Data?) -> [String: Any]? {
    guard let data,
          data.count <= 64 * 1_024,
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    return object
  }

  private static func safeAnalyticsName(_ value: String) -> Bool {
    !value.isEmpty
      && value.count <= 128
      && value.range(of: #"^[A-Za-z0-9_.:\-]+$"#, options: .regularExpression) != nil
  }

  private static func decodeFormComponent(_ value: String) -> String? {
    value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
  }

  private static func percentEncodedPath(_ url: URL) -> String {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path
  }

  private static func validateQuery(
    _ url: URL,
    allowedNames: Set<String>,
    requiredNames: Set<String> = [],
    validate: (URLQueryItem) -> Bool
  ) -> Bool {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let names = items.map(\.name)
    guard Set(names).count == names.count,
          Set(names).isSubset(of: allowedNames),
          requiredNames.isSubset(of: Set(names))
    else {
      return false
    }
    return items.allSatisfy(validate)
  }
}
