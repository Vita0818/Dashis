import DashisCollectorContract
import Foundation

public struct CollectorConfiguration: Sendable {
    public let runtime: CollectorRuntime
    public let environment: [String: String]
    public let providerEnvironment: [CollectorProviderID: [String: String]]
    public let webTimeout: TimeInterval
    public let costUsageHistoryDays: Int
    let now: @Sendable () -> Date

    /// Creates an empty facade-supplied environment. Some pinned Core paths
    /// still read `ProcessInfo.processInfo.environment` directly after an
    /// explicitly authorized strategy starts; this is not a process sandbox.
    public init(
        runtime: CollectorRuntime = .app,
        environment: [String: String] = [:],
        providerEnvironment: [CollectorProviderID: [String: String]] = [:],
        webTimeout: TimeInterval = 60,
        costUsageHistoryDays: Int = 30)
    {
        self.init(
            runtime: runtime,
            environment: environment,
            providerEnvironment: providerEnvironment,
            webTimeout: webTimeout,
            costUsageHistoryDays: costUsageHistoryDays,
            now: Date.init)
    }

    init(
        runtime: CollectorRuntime,
        environment: [String: String],
        providerEnvironment: [CollectorProviderID: [String: String]],
        webTimeout: TimeInterval,
        costUsageHistoryDays: Int,
        now: @escaping @Sendable () -> Date)
    {
        self.runtime = runtime
        self.environment = environment
        self.providerEnvironment = providerEnvironment
        self.webTimeout = max(1, min(webTimeout, 120))
        self.costUsageHistoryDays = max(1, min(costUsageHistoryDays, 365))
        self.now = now
    }

    /// Explicitly opts into inheriting the host process environment.
    public static func ambientProcess(
        runtime: CollectorRuntime = .app,
        providerEnvironment: [CollectorProviderID: [String: String]] = [:],
        webTimeout: TimeInterval = 60,
        costUsageHistoryDays: Int = 30) -> CollectorConfiguration
    {
        CollectorConfiguration(
            runtime: runtime,
            environment: ProcessInfo.processInfo.environment,
            providerEnvironment: providerEnvironment,
            webTimeout: webTimeout,
            costUsageHistoryDays: costUsageHistoryDays)
    }

    func resolvedEnvironment(for provider: CollectorProviderID) -> [String: String] {
        self.environment.merging(self.providerEnvironment[provider] ?? [:]) { _, providerValue in
            providerValue
        }
    }
}
