import Foundation

/// Effects observed while auditing the pinned CodexBar strategy source.
///
/// This is a review aid, not an authorization manifest. A strategy remains
/// opaque until every phase (`resolveStrategies`, `isAvailable`, and `fetch`)
/// has a complete endpoint/credential/effect manifest and brokered host path.
public enum CollectorObservedEffect: String, Codable, CaseIterable, Sendable {
    case network
    case credentialRead
    case providerLocalStateRead
    case browserSessionRead
    case browserLaunch
    case keychainRead
    case subprocess
    case processInspection
    /// Includes CodexBar-owned caches, UserDefaults, and internal Keychain cache
    /// entries. It does not by itself mean the provider's credential source was
    /// rewritten.
    case localStateWrite
    /// Creates, refreshes, or persists provider/host credential material
    /// outside CodexBar's internal session cache, including a host token-update
    /// callback or an external CLI login.
    case credentialWrite
    case remoteStateMutation
    case potentiallyBillable
    case configurableEndpoint
}

public enum CollectorRolloutGate: String, Codable, CaseIterable, Sendable {
    case exactEffectManifest
    case brokeredHostServices
    case operationScopedHardTermination
    case signedRelease
    case explicitSourceBinding
}

/// A pinned upstream strategy selected for Dashis rollout preparation.
///
/// `explicitSources` never contains `.auto`. An empty list means the strategy
/// is reachable only through CodexBar's automatic planner and therefore cannot
/// become a Dashis route without an upstream source split or another exact
/// entry point.
public struct CollectorStagedStrategy: Codable, Equatable, Sendable {
    public let provider: CollectorProviderID
    public let strategyID: String
    public let kind: CollectorStrategyKind
    public let explicitSources: [CollectorSourceMode]
    public let observedEffects: [CollectorObservedEffect]

    public init(
        provider: CollectorProviderID,
        strategyID: String,
        kind: CollectorStrategyKind,
        explicitSources: [CollectorSourceMode],
        observedEffects: [CollectorObservedEffect])
    {
        self.provider = provider
        self.strategyID = strategyID
        self.kind = kind
        self.explicitSources = explicitSources
        self.observedEffects = observedEffects
    }

    public var isExplicitlyRoutable: Bool {
        !self.explicitSources.isEmpty
    }

    public var releaseGates: [CollectorRolloutGate] {
        var gates: [CollectorRolloutGate] = [
            .exactEffectManifest,
            .brokeredHostServices,
            .operationScopedHardTermination,
            .signedRelease,
        ]
        if !self.isExplicitlyRoutable {
            gates.append(.explicitSourceBinding)
        }
        return gates
    }
}

/// One exact, non-automatic source/strategy binding that can later be projected
/// into a product/account-specific Dashis route. It is not a live authorization.
public struct CollectorStagedBinding: Codable, Equatable, Sendable {
    public let id: String
    public let provider: CollectorProviderID
    public let source: CollectorSourceMode
    public let strategyID: String
    public let kind: CollectorStrategyKind
    public let observedEffects: [CollectorObservedEffect]
    public let releaseGates: [CollectorRolloutGate]

    public init(strategy: CollectorStagedStrategy, source: CollectorSourceMode) {
        self.id =
            "staged.\(strategy.provider.rawValue).\(source.rawValue).\(strategy.strategyID)"
        self.provider = strategy.provider
        self.source = source
        self.strategyID = strategy.strategyID
        self.kind = strategy.kind
        self.observedEffects = strategy.observedEffects
        self.releaseGates = strategy.releaseGates
    }
}

/// Dashis-owned rollout scope selected on 2026-07-30.
///
/// The App and XPC Worker both compile this Foundation-only catalog. It records
/// exact pinned strategy identities without importing CodexBarCore into the App
/// and does not itself admit a strategy to the Worker's live authorization
/// registry. Executable bindings are repeated deliberately in
/// `CollectorLiveRouteCatalog`.
public enum CollectorRolloutCatalog {
    public static let revision = "dashis.codexbar.selected-34.v1"

    public static let selectedProviderIDs: [CollectorProviderID] = [
        "codex",
        "openai",
        "azureopenai",
        "claude",
        "clinepass",
        "cursor",
        "opencode",
        "opencodego",
        "alibaba",
        "alibabatokenplan",
        "gemini",
        "antigravity",
        "copilot",
        "zai",
        "minimax",
        "kimi",
        "vertexai",
        "moonshot",
        "ollama",
        "openrouter",
        "perplexity",
        "mimo",
        "doubao",
        "sakana",
        "mistral",
        "deepseek",
        "venice",
        "commandcode",
        "qoder",
        "stepfun",
        "bedrock",
        "grok",
        "longcat",
        "zenmux",
    ]

    public static let strategies: [CollectorStagedStrategy] = [
        strategy(
            "codex", "codex.cli", .cli, [.cli],
            [.network, .credentialRead, .providerLocalStateRead, .subprocess]),
        strategy(
            "codex", "codex.oauth", .oauth, [.oauth],
            [
                .network, .credentialRead, .providerLocalStateRead, .localStateWrite,
                .credentialWrite, .configurableEndpoint,
            ]),
        strategy(
            "codex", "codex.web.dashboard", .webDashboard, [.web],
            webSession(writesLocalState: true)),

        strategy(
            "openai", "openai.api.balance", .apiToken, [.api],
            api()),
        strategy(
            "azureopenai", "azureopenai.api", .apiToken, [.api],
            api(configurableEndpoint: true)
                + [.remoteStateMutation, .potentiallyBillable]),

        strategy(
            "claude", "claude.admin-api", .apiToken, [.api],
            api()),
        strategy(
            "claude", "claude.oauth", .oauth, [.oauth],
            [
                .network, .credentialRead, .providerLocalStateRead, .keychainRead,
                .subprocess, .localStateWrite, .credentialWrite,
            ]),
        strategy(
            "claude", "claude.web", .web, [.web],
            webSession(writesLocalState: true)),
        strategy(
            "claude", "claude.cli", .cli, [.cli],
            [
                .network, .credentialRead, .providerLocalStateRead, .browserSessionRead,
                .browserLaunch, .keychainRead, .subprocess, .localStateWrite,
                .credentialWrite,
            ]),

        strategy(
            "clinepass", "clinepass.api", .apiToken, [.api],
            api()),
        strategy(
            "cursor", "cursor.web", .web, [.cli, .web],
            webSession(writesLocalState: true)),
        strategy(
            "opencode", "opencode.web", .web, [.web],
            webSession(writesLocalState: true)),
        strategy(
            "opencodego", "opencodego.local", .localProbe, [],
            [.network, .credentialRead, .providerLocalStateRead]),
        strategy(
            "opencodego", "opencodego.web", .web, [.web],
            webSession(writesLocalState: true)),

        strategy(
            "alibaba", "alibaba-coding-plan.web", .web, [.web],
            webSession(writesLocalState: true) + [.configurableEndpoint]),
        strategy(
            "alibaba", "alibaba-coding-plan.api", .apiToken, [.api],
            api(configurableEndpoint: true)),
        strategy(
            "alibabatokenplan", "alibaba-token-plan.web", .web, [.web],
            webSession(writesLocalState: true) + [.configurableEndpoint]),

        strategy(
            "gemini", "gemini.api", .apiToken, [.api],
            [
                .network, .credentialRead, .providerLocalStateRead, .subprocess,
                .localStateWrite, .credentialWrite,
            ]),
        strategy(
            "antigravity", "antigravity.app-local", .localProbe, [.cli],
            [
                .network, .credentialRead, .providerLocalStateRead, .subprocess,
                .processInspection,
            ]),
        strategy(
            "antigravity", "antigravity.cli-https", .cli, [.cli],
            [
                .network, .credentialRead, .providerLocalStateRead, .subprocess,
                .processInspection, .localStateWrite,
            ]),
        strategy(
            "antigravity", "antigravity.ide-local", .localProbe, [.cli],
            [
                .network, .credentialRead, .providerLocalStateRead, .subprocess,
                .processInspection,
            ]),
        strategy(
            "antigravity", "antigravity.oauth", .oauth, [.oauth],
            [
                .network, .credentialRead, .providerLocalStateRead, .localStateWrite,
                .credentialWrite, .remoteStateMutation,
            ]),

        strategy(
            "copilot", "copilot.api", .apiToken, [.api],
            api(configurableEndpoint: true)
                + [
                    .providerLocalStateRead, .browserSessionRead, .keychainRead,
                    .localStateWrite,
                ]),
        strategy(
            "zai", "zai.api", .apiToken, [.api],
            api(configurableEndpoint: true)),
        strategy(
            "minimax", "minimax.api", .apiToken, [.api],
            api()),
        strategy(
            "minimax", "minimax.web", .web, [.web],
            webSession(writesLocalState: true) + [.configurableEndpoint]),

        strategy(
            "kimi", "kimi.api", .apiToken, [.api],
            api(configurableEndpoint: true)),
        strategy(
            "kimi", "kimi.cli", .oauth, [],
            [
                .network, .credentialRead, .providerLocalStateRead, .localStateWrite,
            ]),
        strategy(
            "kimi", "kimi.web", .web, [.web],
            webSession(writesLocalState: false)),

        strategy(
            "vertexai", "vertexai.oauth", .oauth, [.oauth],
            [.network, .credentialRead, .providerLocalStateRead, .subprocess]),
        strategy(
            "moonshot", "moonshot.api", .apiToken, [.api],
            api()),

        strategy(
            "ollama", "ollama.web", .web, [.web],
            webSession(writesLocalState: false)),
        strategy(
            "ollama", "ollama.api", .apiToken, [.api],
            api() + [.remoteStateMutation, .potentiallyBillable]),
        strategy(
            "openrouter", "openrouter.api", .apiToken, [.api],
            api(configurableEndpoint: true)),
        strategy(
            "perplexity", "perplexity.web", .web, [.web],
            webSession(writesLocalState: true)),
        strategy(
            "mimo", "mimo.web", .web, [.web],
            webSession(writesLocalState: true) + [.configurableEndpoint]),
        strategy(
            "mimo", "mimo.local", .localProbe, [],
            [.providerLocalStateRead]),
        strategy(
            "doubao", "doubao.cli", .cli, [.cli],
            [.network, .credentialRead, .providerLocalStateRead, .subprocess]),
        strategy(
            "doubao", "doubao.api", .apiToken, [.api],
            api() + [.remoteStateMutation, .potentiallyBillable]),

        strategy(
            "sakana", "sakana.web", .web, [.web],
            [.network, .credentialRead]),
        strategy(
            "mistral", "mistral.web", .web, [.web],
            webSession(writesLocalState: true)),
        strategy(
            "deepseek", "deepseek.api", .apiToken, [.api],
            [
                .network, .credentialRead, .providerLocalStateRead,
                .browserSessionRead,
            ]),
        strategy(
            "deepseek", "deepseek.web", .web, [.web],
            [
                .network, .credentialRead, .providerLocalStateRead,
                .browserSessionRead,
            ]),
        strategy(
            "venice", "venice.api", .apiToken, [.api],
            api()),
        strategy(
            "commandcode", "commandcode.web", .web, [.web],
            webSession(writesLocalState: true)),
        strategy(
            "qoder", "qoder.web", .web, [.web],
            webSession(writesLocalState: true)),
        strategy(
            "stepfun", "stepfun.web", .web, [.web],
            [
                .network, .credentialRead, .providerLocalStateRead, .localStateWrite,
                .credentialWrite, .keychainRead, .remoteStateMutation,
            ]),
        strategy(
            "bedrock", "bedrock.api", .apiToken, [.api],
            [
                .network, .credentialRead, .providerLocalStateRead, .subprocess,
                .potentiallyBillable, .configurableEndpoint,
            ]),
        strategy(
            "grok", "grok.cli", .cli, [.cli],
            [.network, .credentialRead, .providerLocalStateRead, .subprocess]),
        strategy(
            "grok", "grok.web", .web, [.web],
            webSession(writesLocalState: true) + [.subprocess]),
        strategy(
            "longcat", "longcat.web", .web, [.web],
            webSession(writesLocalState: true)),
        strategy(
            "zenmux", "zenmux.api", .apiToken, [.api],
            api()),
    ]

    public static var bindings: [CollectorStagedBinding] {
        self.strategies.flatMap { strategy in
            strategy.explicitSources.map {
                CollectorStagedBinding(strategy: strategy, source: $0)
            }
        }
    }

    public static var automaticOnlyStrategies: [CollectorStagedStrategy] {
        self.strategies.filter { !$0.isExplicitlyRoutable }
    }

    /// The executable route count lives in the separately reviewed live
    /// catalog. Keeping the staged audit catalog and the authorization catalog
    /// separate prevents a newly audited strategy from becoming live merely by
    /// appearing in this file.
    public static var liveAuthorizationCount: Int {
        CollectorLiveRouteCatalog.routes.count
    }

    private static func strategy(
        _ provider: CollectorProviderID,
        _ strategyID: String,
        _ kind: CollectorStrategyKind,
        _ explicitSources: [CollectorSourceMode],
        _ observedEffects: [CollectorObservedEffect]) -> CollectorStagedStrategy
    {
        CollectorStagedStrategy(
            provider: provider,
            strategyID: strategyID,
            kind: kind,
            explicitSources: explicitSources,
            observedEffects: observedEffects)
    }

    private static func api(
        configurableEndpoint: Bool = false) -> [CollectorObservedEffect]
    {
        var effects: [CollectorObservedEffect] = [.network, .credentialRead]
        if configurableEndpoint {
            effects.append(.configurableEndpoint)
        }
        return effects
    }

    private static func webSession(
        writesLocalState: Bool) -> [CollectorObservedEffect]
    {
        var effects: [CollectorObservedEffect] = [
            .network,
            .credentialRead,
            .providerLocalStateRead,
            .browserSessionRead,
            .keychainRead,
        ]
        if writesLocalState {
            effects.append(.localStateWrite)
        }
        return effects
    }
}
