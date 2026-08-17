import CodexBarCore
import DashisCollectorContract
import Foundation

enum CodexBarTypeMapping {
    static func provider(_ id: CollectorProviderID) -> UsageProvider? {
        UsageProvider(rawValue: id.rawValue)
    }

    static func provider(_ provider: UsageProvider) -> CollectorProviderID {
        CollectorProviderID(rawValue: provider.rawValue)
    }

    static func source(_ source: CollectorSourceMode) -> ProviderSourceMode {
        switch source {
        case .auto: .auto
        case .web: .web
        case .cli: .cli
        case .oauth: .oauth
        case .api: .api
        }
    }

    static func source(_ source: ProviderSourceMode) -> CollectorSourceMode {
        switch source {
        case .auto: .auto
        case .web: .web
        case .cli: .cli
        case .oauth: .oauth
        case .api: .api
        }
    }

    static func runtime(_ runtime: CollectorRuntime) -> ProviderRuntime {
        switch runtime {
        case .app: .app
        case .cli: .cli
        }
    }

    static func interaction(_ interaction: CollectorInteraction) -> ProviderInteraction {
        switch interaction {
        case .background: .background
        case .userInitiated: .userInitiated
        }
    }

    static func strategyKind(_ kind: ProviderFetchKind) -> CollectorStrategyKind {
        switch kind {
        case .cli: .cli
        case .web: .web
        case .oauth: .oauth
        case .apiToken: .apiToken
        case .localProbe: .localProbe
        case .webDashboard: .webDashboard
        }
    }

    /// Pinned Core strategies are not capability-pure: a strategy reported as
    /// API, OAuth, CLI, or web can internally invoke other probes. Until a
    /// reviewed exact-strategy effect manifest exists, both planning and
    /// execution require acknowledgement of the complete authority envelope.
    static var conservativeCapabilities: Set<CollectorCapability> {
        Set(CollectorCapability.allCases)
    }
}
