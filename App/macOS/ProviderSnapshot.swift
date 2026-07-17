import Foundation

struct ProviderID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  init(stringLiteral value: String) {
    rawValue = value
  }

  static let codex: ProviderID = "codex"
  static let claude: ProviderID = "claude"
  static let google: ProviderID = "google"
  static let openRouter: ProviderID = "openrouter"
}

enum ProviderScopeKind: String, Codable, Hashable, Sendable {
  case personal
  case apiKey
  case workspace
  case project
  case manual
}

struct ProviderScope: Hashable, Codable, Sendable {
  let kind: ProviderScopeKind
  let label: String

  static func personal(_ label: String) -> ProviderScope {
    ProviderScope(kind: .personal, label: label)
  }

  static func project(_ label: String) -> ProviderScope {
    ProviderScope(kind: .project, label: label)
  }

  static func workspace(_ label: String) -> ProviderScope {
    ProviderScope(kind: .workspace, label: label)
  }
}

enum UsageSourceKind: String, Codable, Hashable, Sendable {
  case officialDirect
  case officialDerived
  case officialLocalBridge
  case experimentalPrivate
  case manualOnly

  var label: String {
    switch self {
    case .officialDirect: "Official"
    case .officialDerived: "Official · Estimated"
    case .officialLocalBridge: "Official · Local"
    case .experimentalPrivate: "Experimental"
    case .manualOnly: "Manual check"
    }
  }

  var defaultStaleInterval: TimeInterval {
    switch self {
    case .officialLocalBridge: 15 * 60
    case .manualOnly: 24 * 60 * 60
    case .officialDirect, .officialDerived, .experimentalPrivate: 5 * 60
    }
  }

  var defaultExpirationInterval: TimeInterval {
    switch self {
    case .manualOnly:
      7 * 24 * 60 * 60
    case .officialDirect, .officialDerived, .officialLocalBridge, .experimentalPrivate:
      24 * 60 * 60
    }
  }
}

struct QuotaWindow: Identifiable, Hashable, Codable, Sendable {
  let id: String
  let label: String
  let used: Double?
  let limit: Double?
  let remaining: Double?
  let usedPercentage: Double?
  let remainingPercentage: Double?
  let resetsAt: Date?
  let unit: String
  let isEstimated: Bool

  var isExceeded: Bool {
    if let remaining { return remaining < 0 }
    if let used, let limit { return used > limit }
    if let usedPercentage { return usedPercentage > 100 }
    return false
  }
}

struct ProviderBalance: Hashable, Codable, Sendable {
  let label: String
  let used: Double?
  let limit: Double?
  let remaining: Double?
  let unit: String
  let resetDescription: String?
  let valueDescription: String?

  init(
    label: String,
    used: Double?,
    limit: Double?,
    remaining: Double?,
    unit: String,
    resetDescription: String?,
    valueDescription: String? = nil
  ) {
    self.label = label
    self.used = used
    self.limit = limit
    self.remaining = remaining
    self.unit = unit
    self.resetDescription = resetDescription
    self.valueDescription = valueDescription
  }

  var usedPercentage: Double? {
    guard let used, let limit, limit > 0 else { return nil }
    return used / limit * 100
  }

  var isExceeded: Bool {
    if let remaining { return remaining < 0 }
    if let used, let limit { return used > limit }
    return false
  }
}

struct ProviderMetric: Identifiable, Hashable, Codable, Sendable {
  var id: String { key }
  let key: String
  let label: String
  let value: Double
  let unit: String
}

struct ProviderWarning: Identifiable, Hashable, Codable, Sendable {
  let id: String
  let message: String

  init(id: String, message: String) {
    self.id = id
    self.message = message
  }
}

struct ProviderFailure: Identifiable, Hashable, Codable, Sendable {
  let id: String
  let operation: String
  let message: String

  init(operation: String, message: String) {
    id = operation
    self.operation = operation
    self.message = message
  }
}

struct ProviderSnapshot: Hashable, Codable, Sendable {
  let providerID: ProviderID
  let scope: ProviderScope
  let sourceKind: UsageSourceKind
  let observedAt: Date
  let windows: [QuotaWindow]
  let balance: ProviderBalance?
  let metrics: [ProviderMetric]
  let warnings: [ProviderWarning]
  let partialFailures: [ProviderFailure]

  var hasData: Bool {
    let hasWindowValue = windows.contains { window in
      [
        window.used,
        window.limit,
        window.remaining,
        window.usedPercentage,
        window.remainingPercentage
      ].compactMap { $0 }.contains(where: \.isFinite)
    }
    let hasBalanceValue = balance.map { balance in
      [balance.used, balance.limit, balance.remaining]
        .compactMap { $0 }
        .contains(where: \.isFinite)
        || !(balance.valueDescription?.isEmpty ?? true)
    } ?? false
    return hasWindowValue || hasBalanceValue || metrics.contains { $0.value.isFinite }
  }

  var mostUrgentWindow: QuotaWindow? {
    windows.min { lhs, rhs in
      let left = lhs.remainingPercentage ?? .greatestFiniteMagnitude
      let right = rhs.remainingPercentage ?? .greatestFiniteMagnitude
      if left == right {
        return (lhs.resetsAt ?? .distantFuture) < (rhs.resetsAt ?? .distantFuture)
      }
      return left < right
    }
  }
}

enum SnapshotFreshness: String, Hashable, Codable, Sendable {
  case fresh
  case stale
  case expired
  case missing

  var label: String {
    switch self {
    case .fresh: "Updated now"
    case .stale: "Stale"
    case .expired: "Expired"
    case .missing: "No data"
    }
  }
}

enum FreshnessPolicy {
  static func freshness(of snapshot: ProviderSnapshot?, now: Date = Date()) -> SnapshotFreshness {
    guard let snapshot, snapshot.hasData else { return .missing }
    let age = now.timeIntervalSince(snapshot.observedAt)
    guard age >= -60 else { return .missing }
    if age <= snapshot.sourceKind.defaultStaleInterval { return .fresh }
    if age <= snapshot.sourceKind.defaultExpirationInterval { return .stale }
    return .expired
  }
}
