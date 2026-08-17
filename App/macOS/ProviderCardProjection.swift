import Foundation

enum ProviderProgressKind: Hashable {
  case remaining
  case used
}

struct ProviderUsageCard: Identifiable, Hashable {
  let id: String
  let title: String
  let headline: String
  let descriptor: String
  let supportingText: String?
  let progressFraction: Double?
  let progressKind: ProviderProgressKind?
  let progressAccessibilityValue: String?
  let statusLabel: String?
  let tone: DashisProviderTone
}

struct ProviderVisualization: Hashable {
  let primaryCards: [ProviderUsageCard]
  let additionalCards: [ProviderUsageCard]
  let metadata: [DashisProviderLine]
}

enum ProviderVisualizationProjection {
  static func make(
    snapshot: ProviderSnapshot,
    now: Date = Date()
  ) -> ProviderVisualization {
    let freshness = FreshnessPolicy.freshness(of: snapshot, now: now)
    let historical = historicalWarning(in: snapshot) != nil
    let resetCredits = snapshot.metrics.first(where: { $0.key == "reset_credits" })

    let visibleWindows = snapshot.windows.filter { window in
      guard snapshot.providerID == .openRouter, let balance = snapshot.balance else { return true }
      return !isDuplicate(window: window, balance: balance)
    }
    let windowCards = visibleWindows.compactMap {
      windowCard($0, freshness: freshness, historical: historical)
    }
    let balanceCards = snapshot.balance.flatMap {
      balanceCard($0, resetCredits: resetCredits, freshness: freshness, historical: historical)
    }.map { [$0] } ?? []
    let metricCards = snapshot.metrics
      .filter { $0.key != "reset_credits" }
      .map { metricCard($0, freshness: freshness, historical: historical) }

    let primaryCards: [ProviderUsageCard]
    let additionalCards: [ProviderUsageCard]
    if !windowCards.isEmpty {
      primaryCards = Array(windowCards.prefix(2))
      additionalCards = Array(windowCards.dropFirst(2)) + balanceCards + metricCards
    } else if !balanceCards.isEmpty {
      primaryCards = balanceCards
      additionalCards = metricCards
    } else {
      primaryCards = Array(metricCards.prefix(2))
      additionalCards = Array(metricCards.dropFirst(2))
    }

    return ProviderVisualization(
      primaryCards: primaryCards,
      additionalCards: additionalCards,
      metadata: [
        DashisProviderLine(title: "Source", value: snapshot.sourceKind.label),
        DashisProviderLine(title: "Scope", value: snapshot.scope.label),
        DashisProviderLine(
          title: "Observed",
          value: ProviderProjectionFormatters.dateTime.string(from: snapshot.observedAt)
        )
      ]
    )
  }

  private static func windowCard(
    _ window: QuotaWindow,
    freshness: SnapshotFreshness,
    historical: Bool
  ) -> ProviderUsageCard? {
    let value: (headline: String, descriptor: String, progress: Double?, kind: ProviderProgressKind?, accessibility: String?)?

    if let remainingPercentage = finite(window.remainingPercentage) {
      let display = formatNumber(remainingPercentage)
      value = (
        "\(display)%",
        "remaining",
        fraction(percent: remainingPercentage),
        .remaining,
        "\(display)% remaining"
      )
    } else if let remaining = finite(window.remaining) {
      let progress = ratio(numerator: remaining, denominator: window.limit)
      value = (
        format(remaining, unit: window.unit),
        "remaining",
        progress,
        progress == nil ? nil : .remaining,
        progress.map { "\(formatNumber($0 * 100))% remaining" }
      )
    } else if let usedPercentage = finite(window.usedPercentage) {
      let display = formatNumber(usedPercentage)
      value = (
        "\(display)%",
        "used",
        fraction(percent: usedPercentage),
        .used,
        "\(display)% used"
      )
    } else if let used = finite(window.used) {
      let progress = ratio(numerator: used, denominator: window.limit)
      value = (
        format(used, unit: window.unit),
        "used",
        progress,
        progress == nil ? nil : .used,
        progress.map { "\(formatNumber($0 * 100))% used" }
      )
    } else if let limit = finite(window.limit) {
      value = (format(limit, unit: window.unit), "limit", nil, nil, nil)
    } else {
      value = nil
    }

    guard let value else { return nil }
    let state = presentationState(
      exceeded: window.isExceeded,
      estimated: window.isEstimated,
      freshness: freshness,
      historical: historical
    )
    return ProviderUsageCard(
      id: "window-\(window.id)",
      title: window.label,
      headline: value.headline,
      descriptor: value.descriptor,
      supportingText: resetText(window.resetsAt),
      progressFraction: value.progress,
      progressKind: value.kind,
      progressAccessibilityValue: value.accessibility,
      statusLabel: state.label,
      tone: state.tone
    )
  }

  private static func balanceCard(
    _ balance: ProviderBalance,
    resetCredits: ProviderMetric?,
    freshness: SnapshotFreshness,
    historical: Bool
  ) -> ProviderUsageCard? {
    let headline: String
    let descriptor: String
    let progress: Double?
    let kind: ProviderProgressKind?
    let progressAccessibilityValue: String?

    if let valueDescription = balance.valueDescription, !valueDescription.isEmpty {
      headline = valueDescription
      descriptor = ""
      progress = nil
      kind = nil
      progressAccessibilityValue = nil
    } else if let remaining = finite(balance.remaining) {
      let label = balance.label.lowercased()
      let repeatsUnit = !balance.unit.isEmpty && label.contains(balance.unit.lowercased())
      headline = format(remaining, unit: repeatsUnit ? "" : balance.unit)
      descriptor = label.contains("remaining") ? "" : "remaining"
      progress = ratio(numerator: remaining, denominator: balance.limit)
      kind = progress == nil ? nil : .remaining
      progressAccessibilityValue = progress.map { "\(formatNumber($0 * 100))% remaining" }
    } else if let used = finite(balance.used) {
      headline = format(used, unit: balance.unit)
      descriptor = "used"
      progress = ratio(numerator: used, denominator: balance.limit)
      kind = progress == nil ? nil : .used
      progressAccessibilityValue = progress.map { "\(formatNumber($0 * 100))% used" }
    } else if let limit = finite(balance.limit) {
      headline = format(limit, unit: balance.unit)
      descriptor = "limit"
      progress = nil
      kind = nil
      progressAccessibilityValue = nil
    } else {
      return nil
    }

    let resetCreditText = resetCredits.map {
      "\(format($0.value, unit: $0.unit)) reset available"
    }
    let supporting = [balance.resetDescription, resetCreditText]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: " · ")
    let state = presentationState(
      exceeded: balance.isExceeded,
      estimated: false,
      freshness: freshness,
      historical: historical
    )
    return ProviderUsageCard(
      id: "balance-\(balance.label)",
      title: balance.label,
      headline: headline,
      descriptor: descriptor,
      supportingText: supporting.isEmpty ? nil : supporting,
      progressFraction: progress,
      progressKind: kind,
      progressAccessibilityValue: progressAccessibilityValue,
      statusLabel: state.label,
      tone: state.tone
    )
  }

  private static func metricCard(
    _ metric: ProviderMetric,
    freshness: SnapshotFreshness,
    historical: Bool
  ) -> ProviderUsageCard {
    let state = presentationState(
      exceeded: false,
      estimated: false,
      freshness: freshness,
      historical: historical
    )
    return ProviderUsageCard(
      id: "metric-\(metric.key)",
      title: metric.label,
      headline: format(metric.value, unit: ""),
      descriptor: metric.unit,
      supportingText: nil,
      progressFraction: nil,
      progressKind: nil,
      progressAccessibilityValue: nil,
      statusLabel: state.label,
      tone: state.tone
    )
  }

  private static func presentationState(
    exceeded: Bool,
    estimated: Bool,
    freshness: SnapshotFreshness,
    historical: Bool
  ) -> (label: String?, tone: DashisProviderTone) {
    if exceeded { return ("Exceeded", .incident) }
    if freshness == .expired { return ("Expired", .watch) }
    if freshness == .stale { return ("Stale", .watch) }
    if historical { return ("Historical", .watch) }
    if estimated { return ("Estimated", .watch) }
    return (nil, .connected)
  }

  private static func resetText(_ date: Date?) -> String? {
    guard let date, date > Date(timeIntervalSince1970: 0) else { return nil }
    return "Resets \(ProviderProjectionFormatters.resetDateTime.string(from: date))"
  }

  private static func fraction(percent: Double) -> Double {
    max(0, min(1, percent / 100))
  }

  private static func ratio(numerator: Double, denominator: Double?) -> Double? {
    guard let denominator = finite(denominator), denominator > 0 else { return nil }
    return max(0, min(1, numerator / denominator))
  }

  private static func finite(_ value: Double?) -> Double? {
    guard let value, value.isFinite else { return nil }
    return value
  }

  private static func isDuplicate(window: QuotaWindow, balance: ProviderBalance) -> Bool {
    guard window.unit.caseInsensitiveCompare(balance.unit) == .orderedSame else { return false }
    let pairs = [
      (window.used, balance.used),
      (window.limit, balance.limit),
      (window.remaining, balance.remaining)
    ]
    let comparable = pairs.compactMap { lhs, rhs -> Bool? in
      guard let lhs, let rhs, lhs.isFinite, rhs.isFinite else { return nil }
      return abs(lhs - rhs) < 0.000_001
    }
    return !comparable.isEmpty && comparable.allSatisfy { $0 }
  }

  private static func historicalWarning(in snapshot: ProviderSnapshot) -> ProviderWarning? {
    snapshot.warnings.first { $0.id.hasPrefix("google-historical-window") }
  }

  private static func format(_ value: Double, unit: String) -> String {
    if unit == "USD" || unit == "$" { return String(format: "$%.2f", value) }
    if unit == "%" { return "\(formatNumber(value))%" }
    return unit.isEmpty ? formatNumber(value) : "\(formatNumber(value)) \(unit)"
  }

  private static func formatNumber(_ value: Double) -> String {
    if value.rounded() == value {
      return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
    return String(format: "%.2f", value)
  }
}

enum ProviderCardProjection {
  static func apply(
    snapshot: ProviderSnapshot,
    to base: DashisProvider,
    now: Date = Date()
  ) -> DashisProvider {
    var provider = base
    let freshness = FreshnessPolicy.freshness(of: snapshot, now: now)
    let urgent = snapshot.mostUrgentWindow
    let historical = historicalWarning(in: snapshot) != nil

    provider.sourceLabel = snapshot.sourceKind.label
    provider.freshnessLabel = historical ? "Historical" : freshness.label
    provider.statusLabel = statusLabel(snapshot: snapshot, freshness: freshness)
    provider.tone = tone(snapshot: snapshot, freshness: freshness)
    provider.progress = displayProgress(window: urgent, balance: snapshot.balance)
    provider.primary = primaryValue(snapshot: snapshot, window: urgent, balance: snapshot.balance)
    provider.caption = caption(snapshot: snapshot, freshness: freshness)
    provider.stats = stats(snapshot: snapshot)
    provider.lines = lines(snapshot: snapshot)
    return provider
  }

  private static func statusLabel(
    snapshot: ProviderSnapshot,
    freshness: SnapshotFreshness
  ) -> String {
    if freshness == .expired { return "expired" }
    if snapshot.sourceKind == .manualOnly && !snapshot.hasData { return "manual" }
    if !snapshot.hasData && !snapshot.partialFailures.isEmpty { return "failed" }
    if !snapshot.hasData { return "no data" }
    if !snapshot.partialFailures.isEmpty { return "partial" }
    if historicalWarning(in: snapshot) != nil { return "historical" }
    if snapshot.windows.contains(where: \.isExceeded) || snapshot.balance?.isExceeded == true {
      return "exceeded"
    }
    return snapshot.hasData ? "connected" : "no data"
  }

  private static func tone(
    snapshot: ProviderSnapshot,
    freshness: SnapshotFreshness
  ) -> DashisProviderTone {
    if !snapshot.hasData && !snapshot.partialFailures.isEmpty {
      return .incident
    }
    if snapshot.windows.contains(where: \.isExceeded) || snapshot.balance?.isExceeded == true {
      return .incident
    }
    if freshness != .fresh || !snapshot.partialFailures.isEmpty || !snapshot.warnings.isEmpty {
      return .watch
    }
    return .connected
  }

  private static func displayProgress(window: QuotaWindow?, balance: ProviderBalance?) -> Double {
    let used = window?.usedPercentage ?? balance?.usedPercentage ?? 0
    return ProviderJSON.clampForDisplay(used)
  }

  private static func primaryValue(
    snapshot: ProviderSnapshot,
    window: QuotaWindow?,
    balance: ProviderBalance?
  ) -> String {
    if snapshot.sourceKind == .manualOnly && !snapshot.hasData {
      return "No quota data"
    }
    if let remaining = window?.remainingPercentage {
      let value = "\(formatNumber(remaining))% left"
      return historicalWarning(in: snapshot) == nil ? value : "\(value) · historical"
    }
    if let remaining = window?.remaining {
      let value = format(remaining, unit: window?.unit ?? "")
      return historicalWarning(in: snapshot) == nil ? value : "\(value) · historical"
    }
    if let valueDescription = balance?.valueDescription, !valueDescription.isEmpty {
      return valueDescription
    }
    if let remaining = balance?.remaining {
      return format(remaining, unit: balance?.unit ?? "")
    }
    let preferredMetric = snapshot.metrics.first(where: {
      ["turns", "requests", "total_tokens", "credits"].contains($0.key)
    }) ?? snapshot.metrics.first
    if let preferredMetric {
      return format(preferredMetric.value, unit: preferredMetric.unit)
    }
    return "No quota data"
  }

  private static func caption(
    snapshot: ProviderSnapshot,
    freshness: SnapshotFreshness
  ) -> String {
    let observed = ProviderProjectionFormatters.dateTime.string(from: snapshot.observedAt)
    var value = "\(snapshot.sourceKind.label) · \(snapshot.scope.label) · observed \(observed)."
    if let historical = historicalWarning(in: snapshot) {
      value += " Latest complete historical window only: \(historical.message)"
    }
    if freshness == .stale { value += " This snapshot is stale." }
    if freshness == .expired { value += " This snapshot is expired and is not current quota." }
    if !snapshot.partialFailures.isEmpty {
      value += " \(snapshot.partialFailures.count) subcheck(s) failed."
    }
    return value
  }

  private static func historicalWarning(in snapshot: ProviderSnapshot) -> ProviderWarning? {
    snapshot.warnings.first { $0.id.hasPrefix("google-historical-window") }
  }

  private static func stats(snapshot: ProviderSnapshot) -> [DashisProviderStat] {
    var result = snapshot.windows.prefix(3).map { window in
      DashisProviderStat(
        title: window.label,
        value: window.remainingPercentage.map { "\(formatNumber($0))% left" }
          ?? window.remaining.map { format($0, unit: window.unit) }
          ?? "-"
      )
    }
    if result.count < 3, let balance = snapshot.balance {
      result.append(DashisProviderStat(
        title: balance.label,
        value: balance.valueDescription
          ?? balance.remaining.map { format($0, unit: balance.unit) }
          ?? "-"
      ))
    }
    for metric in snapshot.metrics where result.count < 3 {
      result.append(DashisProviderStat(title: metric.label, value: format(metric.value, unit: metric.unit)))
    }
    while result.count < 3 {
      result.append(DashisProviderStat(title: result.isEmpty ? "Quota" : "Metric", value: "-"))
    }
    return Array(result.prefix(3))
  }

  private static func lines(snapshot: ProviderSnapshot) -> [DashisProviderLine] {
    var result = [
      DashisProviderLine(title: "Source", value: snapshot.sourceKind.label),
      DashisProviderLine(title: "Scope", value: snapshot.scope.label),
      DashisProviderLine(
        title: "Observed",
        value: ProviderProjectionFormatters.dateTime.string(from: snapshot.observedAt)
      )
    ]

    for window in snapshot.windows {
      let value = window.remainingPercentage.map { "\(formatNumber($0))% remaining" }
        ?? window.remaining.map { format($0, unit: window.unit) }
        ?? window.usedPercentage.map { "\(formatNumber($0))% used" }
        ?? "Unavailable"
      result.append(DashisProviderLine(title: window.label, value: value))
      if let used = window.used {
        result.append(DashisProviderLine(title: "\(window.label) used", value: format(used, unit: window.unit)))
      }
      if let limit = window.limit {
        result.append(DashisProviderLine(title: "\(window.label) limit", value: format(limit, unit: window.unit)))
      }
      if let reset = window.resetsAt, reset > Date(timeIntervalSince1970: 0) {
        result.append(DashisProviderLine(
          title: "\(window.label) reset",
          value: ProviderProjectionFormatters.dateTime.string(from: reset)
        ))
      }
    }

    if let balance = snapshot.balance {
      result.append(DashisProviderLine(
        title: balance.label,
        value: balance.valueDescription
          ?? balance.remaining.map { format($0, unit: balance.unit) }
          ?? "Unavailable"
      ))
      if let used = balance.used {
        result.append(DashisProviderLine(title: "\(balance.label) used", value: format(used, unit: balance.unit)))
      }
      if let limit = balance.limit {
        result.append(DashisProviderLine(title: "\(balance.label) limit", value: format(limit, unit: balance.unit)))
      }
      if let reset = balance.resetDescription, !reset.isEmpty {
        result.append(DashisProviderLine(title: "\(balance.label) reset", value: reset))
      }
    }
    result += snapshot.metrics.map { metric in
      DashisProviderLine(title: metric.label, value: format(metric.value, unit: metric.unit))
    }
    result += snapshot.warnings.map { DashisProviderLine(title: "Warning", value: $0.message) }
    result += snapshot.partialFailures.map {
      DashisProviderLine(title: "Partial failure · \($0.operation)", value: $0.message)
    }
    return result
  }

  private static func format(_ value: Double, unit: String) -> String {
    if unit == "USD" || unit == "$" { return String(format: "$%.2f", value) }
    if unit == "%" { return "\(formatNumber(value))%" }
    return unit.isEmpty ? formatNumber(value) : "\(formatNumber(value)) \(unit)"
  }

  private static func formatNumber(_ value: Double) -> String {
    if value.rounded() == value {
      return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
    return String(format: "%.2f", value)
  }
}

private enum ProviderProjectionFormatters {
  static let dateTime: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
  }()

  static let resetDateTime: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }()
}
