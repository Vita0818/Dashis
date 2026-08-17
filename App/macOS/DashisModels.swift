import Foundation

enum DashisSelection {
  static let dashboard = "dashboard"
  static let providers = "providers"
  static let settings = "settings"

  static func normalizedRootSelection(_ selectionID: String) -> String {
    selectionID == providers ? dashboard : selectionID
  }
}

enum DashisProviderTone: String {
  case connected
  case watch
  case incident
}

enum DashisProviderIntegration: String, Hashable {
  case native
  case collector
  case catalogOnly
}

struct DashisProvider: Identifiable, Hashable {
  let id: String
  let catalogProviderID: String
  let integration: DashisProviderIntegration
  var name: String
  var kind: String
  var primary: String
  var caption: String
  var statusLabel: String
  var sourceLabel: String
  var freshnessLabel: String
  var tone: DashisProviderTone
  var progress: Double
  var stats: [DashisProviderStat]
  var lines: [DashisProviderLine]
  var actionTitle: String?
  var detailTitle: String
  var detailNote: String

  var isBuiltIn: Bool {
    integration == .native
  }
}

struct DashisProviderStat: Hashable {
  let title: String
  let value: String
}

struct DashisProviderLine: Hashable, Identifiable {
  var id: String { "\(title)\u{1F}\(value)" }
  let title: String
  let value: String
}

extension DashisProvider {
  static let codex = DashisProvider(
    id: "codex",
    catalogProviderID: "codex",
    integration: .native,
    name: "Codex",
    kind: "Native desktop",
    primary: "Not checked",
    caption: "Personal allowance follows the account's reported plan, credits, and any returned usage windows.",
    statusLabel: "not checked",
    sourceLabel: "Experimental",
    freshnessLabel: "No data",
    tone: .watch,
    progress: 0,
    stats: [
      DashisProviderStat(title: "Credits", value: "-"),
      DashisProviderStat(title: "Window", value: "-"),
      DashisProviderStat(title: "Reset credits", value: "-")
    ],
    lines: [
      DashisProviderLine(title: "Desktop auth", value: "Not checked")
    ],
    actionTitle: "Check Codex",
    detailTitle: "Codex native checks",
    detailNote: "Desktop usage shows credits and only the windows returned for the signed-in account; Dashis does not assume a fixed rolling window. Workspace analytics uses an analytics-scoped API key kept only in app memory."
  )

  static let claude = DashisProvider(
    id: "claude",
    catalogProviderID: "claude",
    integration: .native,
    name: "Claude",
    kind: "Claude Code status line",
    primary: "Not connected",
    caption: "A local, opt-in bridge stores only the sanitized 5-hour and 7-day rate-limit windows.",
    statusLabel: "not connected",
    sourceLabel: "Official · Local",
    freshnessLabel: "No data",
    tone: .watch,
    progress: 0,
    stats: [
      DashisProviderStat(title: "5 hour", value: "-"),
      DashisProviderStat(title: "7 day", value: "-"),
      DashisProviderStat(title: "Observed", value: "-")
    ],
    lines: [
      DashisProviderLine(title: "Bridge", value: "Disabled"),
      DashisProviderLine(title: "Refresh", value: "After a Claude Code response")
    ],
    actionTitle: "Reload snapshot",
    detailTitle: "Claude Code local bridge",
    detailNote: "Dashis never sends a Claude request to refresh quota. Connect is explicit and reads only the user statusLine setting."
  )

  static let googleAI = DashisProvider(
    id: "google",
    catalogProviderID: "gemini",
    integration: .native,
    name: "Gemini",
    kind: "Consumer or Cloud project",
    primary: "No quota data",
    caption: "Consumer subscription quota has no supported third-party balance API. Cloud project quota can be derived from official APIs.",
    statusLabel: "manual",
    sourceLabel: "Manual check",
    freshnessLabel: "No data",
    tone: .watch,
    progress: 0,
    stats: [
      DashisProviderStat(title: "Mode", value: "Consumer"),
      DashisProviderStat(title: "Quota", value: "-"),
      DashisProviderStat(title: "Observed", value: "-")
    ],
    lines: [
      DashisProviderLine(title: "Consumer quota", value: "Open official UI"),
      DashisProviderLine(title: "Automation", value: "Not available")
    ],
    actionTitle: "Open official page",
    detailTitle: "Google AI quota modes",
    detailNote: "Consumer mode never reads browser cookies or private CLI state. Project mode uses an explicit Google OAuth grant kept in memory."
  )

  static let openRouter = DashisProvider(
    id: "openrouter",
    catalogProviderID: "openrouter",
    integration: .native,
    name: "OpenRouter",
    kind: "Account analytics or single API key",
    primary: "Not checked",
    caption: "Native Swift client checks credits, activity, analytics, and optional generation detail.",
    statusLabel: "not checked",
    sourceLabel: "Official",
    freshnessLabel: "No data",
    tone: .watch,
    progress: 0,
    stats: [
      DashisProviderStat(title: "Requests", value: "-"),
      DashisProviderStat(title: "Tokens", value: "-"),
      DashisProviderStat(title: "Models", value: "-")
    ],
    lines: [
      DashisProviderLine(title: "Credits", value: "Not checked"),
      DashisProviderLine(title: "Activity", value: "Not checked")
    ],
    actionTitle: "Set up account",
    detailTitle: "OpenRouter native checks",
    detailNote: "Account mode reads account-wide credits, activity, and analytics with a session-only management key. Single-key OAuth remains optional."
  )

  static func custom(name: String, kind: String) -> DashisProvider {
    let id = "custom-\(UUID().uuidString)"
    return DashisProvider(
      id: id,
      catalogProviderID: id,
      integration: .catalogOnly,
      name: name,
      kind: kind,
      primary: "Adapter needed",
      caption: "This provider is registered in the native app session. Add a native adapter before live checks are available.",
      statusLabel: "local only",
      sourceLabel: "Manual",
      freshnessLabel: "No data",
      tone: .watch,
      progress: 0,
      stats: [
        DashisProviderStat(title: "Status", value: "-"),
        DashisProviderStat(title: "Checks", value: "-"),
        DashisProviderStat(title: "Tokens", value: "-")
      ],
      lines: [
        DashisProviderLine(title: "Adapter", value: "Not installed"),
        DashisProviderLine(title: "Persistence", value: "Session only")
      ],
      actionTitle: nil,
      detailTitle: "\(name) adapter",
      detailNote: "Custom providers stay adapter-required until a provider-specific Swift service is added."
    )
  }

  static func collector(
    id: String,
    name: String,
    preparedSourceSummary: String
  ) -> DashisProvider {
    DashisProvider(
      id: id,
      catalogProviderID: id,
      integration: .collector,
      name: name,
      kind: "Collector adapter",
      primary: "Not checked",
      caption: "Runs the selected CodexBar adapter in the isolated collector worker.",
      statusLabel: "not checked",
      sourceLabel: preparedSourceSummary,
      freshnessLabel: "No data",
      tone: .watch,
      progress: 0,
      stats: [],
      lines: [],
      actionTitle: "Configure",
      detailTitle: "\(name) collection",
      detailNote: "Choose one exact collection method. Temporary fields stay in app memory and are supplied to the worker only for that run."
    )
  }
}
