import DashisCollectorContract
import Foundation

/// The reviewed product projection of the selected collector rollout.
///
/// The contract catalog owns provider order and collector identity. Dashis
/// owns names, symbols and navigation identity. Extended providers are
/// projected only from the executable live route catalog shared with Worker.
enum DashisProviderCatalog {
  static let providers: [DashisProvider] = CollectorRolloutCatalog.selectedProviderIDs.map {
    provider(for: $0.rawValue)
  }

  static func preparedSourceLabels(for catalogProviderID: String) -> [String] {
    var seen = Set<String>()
    return CollectorLiveRouteCatalog.routes.compactMap { route in
      guard route.provider.rawValue == catalogProviderID else { return nil }
      let label = sourceLabel(for: route.strategyKind)
      guard seen.insert(label).inserted else { return nil }
      return label
    }
  }

  static func liveRoutes(for catalogProviderID: String)
    -> [CollectorLiveRouteDefinition]
  {
    CollectorLiveRouteCatalog.routes.filter {
      $0.provider.rawValue == catalogProviderID
    }
  }

  static func defaultLiveRoute(for catalogProviderID: String)
    -> CollectorLiveRouteDefinition?
  {
    let routes = liveRoutes(for: catalogProviderID)
    guard let preferredStrategy = preferredStrategyIDs[catalogProviderID] else {
      return routes.first
    }
    let preferredSource = preferredSources[catalogProviderID]
    return routes.first {
      $0.strategyID == preferredStrategy
        && (preferredSource == nil || $0.source == preferredSource)
    } ?? routes.first { $0.strategyID == preferredStrategy } ?? routes.first
  }

  static func preparedSourceSummary(for catalogProviderID: String) -> String {
    let labels = preparedSourceLabels(for: catalogProviderID)
    return labels.isEmpty ? "No explicit source" : labels.joined(separator: " · ")
  }

  private static let presentations: [String: String] = [
    "openai": "OpenAI",
    "azureopenai": "Azure OpenAI",
    "clinepass": "ClinePass",
    "cursor": "Cursor",
    "opencode": "OpenCode",
    "opencodego": "OpenCode Go",
    "alibaba": "Alibaba",
    "alibabatokenplan": "Alibaba Token Plan",
    "antigravity": "Antigravity",
    "copilot": "Copilot",
    "zai": "z.ai",
    "minimax": "MiniMax",
    "kimi": "Kimi",
    "vertexai": "Vertex AI",
    "moonshot": "Moonshot / Kimi API",
    "ollama": "Ollama",
    "perplexity": "Perplexity",
    "mimo": "Xiaomi MiMo",
    "doubao": "Doubao",
    "sakana": "Sakana AI",
    "mistral": "Mistral",
    "deepseek": "DeepSeek",
    "venice": "Venice",
    "commandcode": "Command Code",
    "qoder": "Qoder",
    "stepfun": "StepFun",
    "bedrock": "AWS Bedrock",
    "grok": "Grok",
    "longcat": "LongCat",
    "zenmux": "ZenMux"
  ]

  private static let preferredStrategyIDs: [String: String] = [
    "openai": "openai.api.balance",
    "azureopenai": "azureopenai.api",
    "clinepass": "clinepass.api",
    "cursor": "cursor.web",
    "opencode": "opencode.web",
    "opencodego": "opencodego.web",
    "alibaba": "alibaba-coding-plan.web",
    "alibabatokenplan": "alibaba-token-plan.web",
    "antigravity": "antigravity.app-local",
    "copilot": "copilot.api",
    "zai": "zai.api",
    "minimax": "minimax.web",
    "kimi": "kimi.web",
    "vertexai": "vertexai.oauth",
    "moonshot": "moonshot.api",
    "ollama": "ollama.web",
    "perplexity": "perplexity.web",
    "mimo": "mimo.web",
    "doubao": "doubao.cli",
    "sakana": "sakana.web",
    "mistral": "mistral.web",
    "deepseek": "deepseek.web",
    "venice": "venice.api",
    "commandcode": "commandcode.web",
    "qoder": "qoder.web",
    "stepfun": "stepfun.web",
    "bedrock": "bedrock.api",
    "grok": "grok.cli",
    "longcat": "longcat.web",
    "zenmux": "zenmux.api",
  ]

  private static let preferredSources: [String: CollectorSourceMode] = [
    "cursor": .web,
  ]

  private static func provider(for catalogProviderID: String) -> DashisProvider {
    switch catalogProviderID {
    case "codex":
      return .codex
    case "claude":
      return .claude
    case "gemini":
      return .googleAI
    case "openrouter":
      return .openRouter
    default:
      guard let presentation = presentations[catalogProviderID] else {
        preconditionFailure("Missing reviewed frontend presentation for \(catalogProviderID)")
      }
      return .collector(
        id: catalogProviderID,
        name: presentation,
        preparedSourceSummary: preparedSourceSummary(for: catalogProviderID)
      )
    }
  }

  private static func sourceLabel(for kind: CollectorStrategyKind) -> String {
    switch kind {
    case .apiToken:
      return "API"
    case .oauth:
      return "OAuth"
    case .web, .webDashboard:
      return "Web"
    case .cli:
      return "CLI"
    case .localProbe:
      return "Local"
    }
  }
}

extension DashisProvider {
  var preparedSourceLabels: [String] {
    DashisProviderCatalog.preparedSourceLabels(for: catalogProviderID)
  }
}
