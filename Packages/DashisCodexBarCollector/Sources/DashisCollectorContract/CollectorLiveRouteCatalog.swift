import Foundation

public enum CollectorConfigurationFieldKind: String, Codable, Sendable {
    case secret
    case text
}

public struct CollectorConfigurationField: Codable, Equatable, Sendable {
    public let key: String
    public let label: String
    public let kind: CollectorConfigurationFieldKind
    public let required: Bool
    public let placeholder: String?

    public init(
        key: String,
        label: String,
        kind: CollectorConfigurationFieldKind,
        required: Bool = false,
        placeholder: String? = nil)
    {
        self.key = key
        self.label = label
        self.kind = kind
        self.required = required
        self.placeholder = placeholder
    }
}

/// A Dashis-owned, executable binding to one exact strategy in the pinned
/// CodexBar engine.
///
/// The catalog is compiled into both the App and Worker. It intentionally
/// contains configuration *names*, never configuration values. Values are
/// supplied through a connection-scoped, one-operation XPC broker.
public struct CollectorLiveRouteDefinition: Codable, Equatable, Sendable {
    public let id: String
    public let provider: CollectorProviderID
    public let source: CollectorSourceMode
    public let strategyID: String
    public let strategyKind: CollectorStrategyKind
    public let includeCredits: Bool
    public let includeOptionalUsage: Bool
    public let interaction: CollectorInteraction
    public let observedEffects: [CollectorObservedEffect]
    public let configurationFields: [CollectorConfigurationField]
    public let requiresConsent: Bool
    public let riskSummary: String
    public let upstreamPin: String

    public init(
        binding: CollectorStagedBinding,
        configurationFields: [CollectorConfigurationField],
        requiresConsent: Bool,
        riskSummary: String)
    {
        self.id =
            "collector.live.\(binding.provider.rawValue).\(binding.source.rawValue).\(binding.strategyID)"
        self.provider = binding.provider
        self.source = binding.source
        self.strategyID = binding.strategyID
        self.strategyKind = binding.kind
        self.includeCredits = true
        // Optional usage often enters a second, less constrained branch in the
        // pinned upstream strategies. Each route starts with that branch off.
        self.includeOptionalUsage = false
        self.interaction = .userInitiated
        self.observedEffects = binding.observedEffects
        self.configurationFields = configurationFields
        self.requiresConsent = requiresConsent
        self.riskSummary = riskSummary
        self.upstreamPin = CollectorWireIdentity.codexBarUpstreamPin
    }

    public var allowedConfigurationKeys: [String] {
        configurationFields.map(\.key)
    }

    /// Stable, delimiter-safe material hashed independently by the App and
    /// Worker. Adding or changing any execution-affecting field changes the
    /// authorization digest.
    public var manifestMaterial: String {
        [
            CollectorLiveRouteCatalog.revision,
            upstreamPin,
            id,
            provider.rawValue,
            source.rawValue,
            strategyID,
            strategyKind.rawValue,
            includeCredits ? "credits=1" : "credits=0",
            includeOptionalUsage ? "optional=1" : "optional=0",
            interaction.rawValue,
            requiresConsent ? "consent=1" : "consent=0",
            observedEffects.map(\.rawValue).sorted().joined(separator: ","),
            configurationFields.map {
                "\($0.key):\($0.kind.rawValue):\($0.required ? "1" : "0")"
            }.sorted().joined(separator: ","),
        ].map(Self.lengthPrefixed).joined()
    }

    private static func lengthPrefixed(_ value: String) -> String {
        "\(value.utf8.count):\(value)"
    }
}

public enum CollectorLiveRouteCatalog {
    public static let revision = "dashis.codexbar.live-30.v1"

    /// The executable set is intentionally repeated here instead of deriving
    /// every explicit staged binding. Extending the audit catalog must never
    /// make a new strategy live without a second, deliberate authorization
    /// change in this list.
    private static let authorizedBindingIDs: [String] = [
        "staged.openai.api.openai.api.balance",
        "staged.azureopenai.api.azureopenai.api",
        "staged.clinepass.api.clinepass.api",
        "staged.cursor.cli.cursor.web",
        "staged.cursor.web.cursor.web",
        "staged.opencode.web.opencode.web",
        "staged.opencodego.web.opencodego.web",
        "staged.alibaba.web.alibaba-coding-plan.web",
        "staged.alibaba.api.alibaba-coding-plan.api",
        "staged.alibabatokenplan.web.alibaba-token-plan.web",
        "staged.antigravity.cli.antigravity.app-local",
        "staged.antigravity.cli.antigravity.cli-https",
        "staged.antigravity.cli.antigravity.ide-local",
        "staged.antigravity.oauth.antigravity.oauth",
        "staged.copilot.api.copilot.api",
        "staged.zai.api.zai.api",
        "staged.minimax.api.minimax.api",
        "staged.minimax.web.minimax.web",
        "staged.kimi.api.kimi.api",
        "staged.kimi.web.kimi.web",
        "staged.vertexai.oauth.vertexai.oauth",
        "staged.moonshot.api.moonshot.api",
        "staged.ollama.web.ollama.web",
        "staged.ollama.api.ollama.api",
        "staged.perplexity.web.perplexity.web",
        "staged.mimo.web.mimo.web",
        "staged.doubao.cli.doubao.cli",
        "staged.doubao.api.doubao.api",
        "staged.sakana.web.sakana.web",
        "staged.mistral.web.mistral.web",
        "staged.deepseek.api.deepseek.api",
        "staged.deepseek.web.deepseek.web",
        "staged.venice.api.venice.api",
        "staged.commandcode.web.commandcode.web",
        "staged.qoder.web.qoder.web",
        "staged.stepfun.web.stepfun.web",
        "staged.bedrock.api.bedrock.api",
        "staged.grok.cli.grok.cli",
        "staged.grok.web.grok.web",
        "staged.longcat.web.longcat.web",
        "staged.zenmux.api.zenmux.api",
    ]

    /// Codex, Claude, Gemini and OpenRouter keep their established native
    /// frontend flows. Every explicit staged binding for the other 30 selected
    /// providers is executable through this catalog.
    public static let nativeFrontendProviderIDs: Set<CollectorProviderID> = [
        "codex", "claude", "gemini", "openrouter",
    ]

    public static let routes: [CollectorLiveRouteDefinition] = {
        let stagedBindings = Dictionary(
            uniqueKeysWithValues: CollectorRolloutCatalog.bindings.map {
                ($0.id, $0)
            })
        precondition(
            Set(authorizedBindingIDs).count == authorizedBindingIDs.count,
            "Live collector binding IDs must be unique.")
        return authorizedBindingIDs.map { bindingID in
            guard let binding = stagedBindings[bindingID],
                  !nativeFrontendProviderIDs.contains(binding.provider)
            else {
                preconditionFailure(
                    "Missing or invalid live collector binding: \(bindingID)")
            }
            let effects = Set(binding.observedEffects)
            return CollectorLiveRouteDefinition(
                binding: binding,
                configurationFields: configurationFields(
                    provider: binding.provider,
                    strategyID: binding.strategyID),
                requiresConsent: requiresConsent(effects),
                riskSummary: riskSummary(effects))
        }
    }()

    public static var providerIDs: [CollectorProviderID] {
        var seen = Set<CollectorProviderID>()
        return routes.compactMap { seen.insert($0.provider).inserted ? $0.provider : nil }
    }

    public static func routes(for provider: CollectorProviderID) -> [CollectorLiveRouteDefinition] {
        routes.filter { $0.provider == provider }
    }

    public static func route(id: String) -> CollectorLiveRouteDefinition? {
        routes.first { $0.id == id }
    }

    public static var manifestSetMaterial: String {
        routes
            .sorted { $0.id < $1.id }
            .map { "\($0.id.utf8.count):\($0.id)\($0.manifestMaterial)" }
            .joined()
    }

    private static func requiresConsent(_ effects: Set<CollectorObservedEffect>) -> Bool {
        !effects.isDisjoint(with: [
            .browserSessionRead,
            .browserLaunch,
            .keychainRead,
            .subprocess,
            .processInspection,
            .localStateWrite,
            .credentialWrite,
            .remoteStateMutation,
            .potentiallyBillable,
            .configurableEndpoint,
        ])
    }

    private static func riskSummary(_ effects: Set<CollectorObservedEffect>) -> String {
        var labels: [String] = []
        if effects.contains(.browserSessionRead) || effects.contains(.browserLaunch) {
            labels.append("browser session")
        }
        if effects.contains(.keychainRead) {
            labels.append("Keychain")
        }
        if effects.contains(.providerLocalStateRead) {
            labels.append("local provider data")
        }
        if effects.contains(.subprocess) || effects.contains(.processInspection) {
            labels.append("local processes")
        }
        if effects.contains(.localStateWrite) || effects.contains(.credentialWrite) {
            labels.append("local state updates")
        }
        if effects.contains(.remoteStateMutation) {
            labels.append("remote state changes")
        }
        if effects.contains(.potentiallyBillable) {
            labels.append("a potentially billable probe")
        }
        if effects.contains(.configurableEndpoint) {
            labels.append("a configured endpoint")
        }
        return labels.isEmpty
            ? "Reads usage data from the provider."
            : "May access " + labels.joined(separator: ", ") + "."
    }

    private static func configurationFields(
        provider: CollectorProviderID,
        strategyID: String) -> [CollectorConfigurationField]
    {
        func secret(_ key: String, _ label: String, required: Bool = false)
            -> CollectorConfigurationField
        {
            CollectorConfigurationField(
                key: key,
                label: label,
                kind: .secret,
                required: required)
        }
        func text(_ key: String, _ label: String, placeholder: String? = nil)
            -> CollectorConfigurationField
        {
            CollectorConfigurationField(
                key: key,
                label: label,
                kind: .text,
                placeholder: placeholder)
        }

        switch (provider.rawValue, strategyID) {
        case ("openai", _):
            return [
                secret("OPENAI_ADMIN_KEY", "Admin key"),
                secret("OPENAI_API_KEY", "API key"),
                text("OPENAI_PROJECT_ID", "Project ID"),
            ]
        case ("azureopenai", _):
            return [
                secret("AZURE_OPENAI_API_KEY", "API key"),
                text("AZURE_OPENAI_ENDPOINT", "Azure endpoint"),
                text("AZURE_OPENAI_DEPLOYMENT_NAME", "Deployment"),
                text("AZURE_OPENAI_API_VERSION", "API version"),
            ]
        case ("clinepass", _):
            return [
                secret("CLINE_API_KEY", "API key"),
                secret("CLINEPASS_API_KEY", "ClinePass API key"),
            ]
        case ("opencode", _):
            return [text("CODEXBAR_OPENCODE_WORKSPACE_ID", "Workspace ID")]
        case ("opencodego", _):
            return [text("CODEXBAR_OPENCODEGO_WORKSPACE_ID", "Workspace ID")]
        case ("alibaba", "alibaba-coding-plan.api"):
            return [
                secret("ALIBABA_CODING_PLAN_API_KEY", "Coding Plan API key"),
                secret("ALIBABA_QWEN_API_KEY", "Qwen API key"),
                secret("DASHSCOPE_API_KEY", "DashScope API key"),
            ]
        case ("alibaba", _):
            return [secret("ALIBABA_CODING_PLAN_COOKIE", "Session cookie")]
        case ("alibabatokenplan", _):
            return [secret("ALIBABA_TOKEN_PLAN_COOKIE", "Session cookie")]
        case ("antigravity", "antigravity.cli-https"):
            return [text("ANTIGRAVITY_CLI_PATH", "Antigravity CLI path")]
        case ("antigravity", "antigravity.oauth"):
            return [
                secret(
                    "ANTIGRAVITY_OAUTH_CREDENTIALS_JSON",
                    "OAuth credentials JSON"),
                text("ANTIGRAVITY_OAUTH_CLIENT_ID", "OAuth client ID"),
                secret(
                    "ANTIGRAVITY_OAUTH_CLIENT_SECRET",
                    "OAuth client secret"),
            ]
        case ("copilot", _):
            return [secret("COPILOT_API_TOKEN", "Copilot token")]
        case ("zai", _):
            return [
                secret("Z_AI_API_KEY", "API key"),
                text("Z_AI_BIGMODEL_ORGANIZATION", "Team organization"),
                text("Z_AI_BIGMODEL_PROJECT", "Team project"),
            ]
        case ("minimax", "minimax.api"):
            return [
                secret("MINIMAX_CODING_API_KEY", "Coding Plan key"),
                secret("MINIMAX_API_KEY", "API key"),
                secret("MINIMAX_COOKIE", "Session cookie"),
                secret("MINIMAX_COOKIE_HEADER", "Cookie header"),
            ]
        case ("minimax", _):
            return [
                secret("MINIMAX_COOKIE", "Session cookie"),
                secret("MINIMAX_COOKIE_HEADER", "Cookie header"),
            ]
        case ("kimi", "kimi.api"):
            return [secret("KIMI_CODE_API_KEY", "API key")]
        case ("kimi", _):
            return [
                secret("KIMI_AUTH_TOKEN", "Auth token"),
                secret("KIMI_MANUAL_COOKIE", "Session cookie"),
            ]
        case ("moonshot", _):
            return [
                secret("MOONSHOT_API_KEY", "API key"),
                secret("MOONSHOT_KEY", "Alternate API key"),
                text("MOONSHOT_REGION", "Region", placeholder: "global"),
            ]
        case ("vertexai", _):
            return [
                text("GOOGLE_APPLICATION_CREDENTIALS", "Service account file"),
                text("CLOUDSDK_CONFIG", "gcloud config directory"),
                text("GOOGLE_CLOUD_PROJECT", "Google Cloud project"),
                text("GCLOUD_PROJECT", "Alternate project"),
                text("CLOUDSDK_CORE_PROJECT", "gcloud core project"),
            ]
        case ("ollama", "ollama.api"):
            return [
                secret("OLLAMA_API_KEY", "API key"),
                secret("OLLAMA_KEY", "Alternate API key"),
            ]
        case ("perplexity", _):
            return [
                secret("PERPLEXITY_SESSION_TOKEN", "Session token"),
                secret("PERPLEXITY_COOKIE", "Session cookie"),
            ]
        case ("mimo", _):
            // The pinned web strategy accepts browser/settings cookie state,
            // not an environment cookie. No fake field is exposed here.
            return []
        case ("doubao", "doubao.api"):
            return [
                secret("ARK_API_KEY", "Ark API key"),
                secret("VOLCENGINE_API_KEY", "Volcengine API key"),
                secret("DOUBAO_API_KEY", "Doubao API key"),
                secret("VOLCENGINE_ACCESS_KEY_ID", "Access key ID"),
                secret("VOLCENGINE_SECRET_ACCESS_KEY", "Secret access key"),
                text("VOLCENGINE_REGION", "Region"),
            ]
        case ("doubao", "doubao.cli"):
            return [text("ARKCLI_PATH", "arkcli path")]
        case ("sakana", _):
            return [secret("SAKANA_COOKIE", "Session cookie")]
        case ("deepseek", "deepseek.api"):
            return [
                secret("DEEPSEEK_API_KEY", "API key"),
                secret("DEEPSEEK_KEY", "Alternate API key"),
            ]
        case ("deepseek", _):
            return [
                secret("DEEPSEEK_API_KEY", "API key"),
                secret("DEEPSEEK_KEY", "Alternate API key"),
                secret("DEEPSEEK_PLATFORM_TOKEN", "Platform token"),
                secret("DEEPSEEK_USER_TOKEN", "User token"),
                text("CODEXBAR_DEEPSEEK_PROFILE_ID", "Chrome profile ID"),
                text("CODEXBAR_DEEPSEEK_PROFILE_SCOPE", "Chrome profile scope"),
            ]
        case ("venice", _):
            return [
                secret("VENICE_API_KEY", "API key"),
                secret("VENICE_KEY", "Alternate API key"),
            ]
        case ("longcat", _):
            return [secret("LONGCAT_MANUAL_COOKIE", "Session cookie")]
        case ("stepfun", _):
            return [
                secret("STEPFUN_TOKEN", "Session token"),
                text("STEPFUN_USERNAME", "Username"),
                secret("STEPFUN_PASSWORD", "Password"),
            ]
        case ("bedrock", _):
            return [
                secret("AWS_ACCESS_KEY_ID", "AWS access key ID"),
                secret("AWS_SECRET_ACCESS_KEY", "AWS secret access key"),
                secret("AWS_SESSION_TOKEN", "AWS session token"),
                text("AWS_REGION", "AWS region"),
                text("AWS_DEFAULT_REGION", "Default AWS region"),
                text("AWS_PROFILE", "AWS profile"),
                text("AWS_CLI_PATH", "AWS CLI path"),
                text("CODEXBAR_BEDROCK_BUDGET", "Monthly budget"),
                text("CODEXBAR_BEDROCK_AUTH_MODE", "Auth mode"),
            ]
        case ("grok", _):
            return [
                text("GROK_CLI_PATH", "Grok CLI path"),
                text("GROK_HOME", "Grok home"),
            ]
        case ("zenmux", _):
            return [secret("ZENMUX_MANAGEMENT_API_KEY", "Management API key")]
        default:
            // These routes use an existing local CLI/browser/provider session.
            return []
        }
    }
}
