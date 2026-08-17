import CodexBarCore
import DashisCollectorContract
import Foundation

public actor CodexBarCollector {
    private let configuration: CollectorConfiguration
    private let policy: any CollectorSourcePolicy
    private let host: CodexBarHostConfiguration
    private let browserDetection: BrowserDetection
    private let descriptorFor: @Sendable (UsageProvider) -> ProviderDescriptor

    public init(
        configuration: CollectorConfiguration = CollectorConfiguration(),
        policy: any CollectorSourcePolicy = StaticCollectorSourcePolicy.denyAll,
        host: CodexBarHostConfiguration = .disabled)
    {
        self.init(
            configuration: configuration,
            policy: policy,
            host: host,
            descriptorFor: ProviderDescriptorRegistry.descriptor)
    }

    init(
        configuration: CollectorConfiguration,
        policy: any CollectorSourcePolicy,
        host: CodexBarHostConfiguration,
        descriptorFor: @escaping @Sendable (UsageProvider) -> ProviderDescriptor)
    {
        self.configuration = configuration
        self.policy = policy
        self.host = host
        self.browserDetection = BrowserDetection()
        self.descriptorFor = descriptorFor
    }

    public func catalog() -> [CollectorProvider] {
        ProviderDescriptorRegistry.all.map { descriptor in
            CollectorProvider(
                id: CodexBarTypeMapping.provider(descriptor.id),
                displayName: descriptor.metadata.displayName,
                supportedSources: descriptor.fetchPlan.sourceModes
                    .map(CodexBarTypeMapping.source)
                    .sorted { $0.rawValue < $1.rawValue },
                supportsCredits: descriptor.metadata.supportsCredits,
                primaryWindowLabel: descriptor.metadata.sessionLabel,
                secondaryWindowLabel: descriptor.metadata.weeklyLabel,
                tertiaryWindowLabel: descriptor.metadata.opusLabel,
                dashboardURL: descriptor.metadata.dashboardURL.flatMap(URL.init(string:)))
        }
    }

    public func collect(_ request: CollectorRequest) async -> CollectorOutcome {
        let startedAt = self.configuration.now()
        if Task.isCancelled {
            return self.failureOutcome(
                request: request,
                startedAt: startedAt,
                attempts: [],
                failure: CollectorFailure(
                    code: "cancelled",
                    message: "Collection was cancelled."))
        }

        guard request.account.isAmbient || request.account.id != nil else {
            return self.failureOutcome(
                request: request,
                startedAt: startedAt,
                attempts: [],
                failure: CollectorFailure(
                    code: "invalid_account_selection",
                    message: "A selected account requires a stable account ID."))
        }

        guard let provider = CodexBarTypeMapping.provider(request.provider) else {
            return self.failureOutcome(
                request: request,
                startedAt: startedAt,
                attempts: [],
                failure: CollectorFailure(
                    code: "unknown_provider",
                    message: "The requested provider is not registered in the pinned CodexBar engine."))
        }

        let policyRequest = CollectorPolicyRequest(
            provider: request.provider,
            account: request.account,
            requestedSource: request.source,
            runtime: self.configuration.runtime,
            includeCredits: request.includeCredits,
            includeOptionalUsage: request.includeOptionalUsage,
            interaction: request.interaction)
        let requestDecision = self.policy.evaluateRequest(policyRequest)
        guard requestDecision.allowed else {
            return self.failureOutcome(
                request: request,
                startedAt: startedAt,
                attempts: [],
                failure: CollectorFailure(
                    code: "request_policy_denied",
                    message: "Collection was denied by policy rule \(requestDecision.ruleID)."))
        }

        let planningCandidate = CollectorPlanningCandidate(
            request: policyRequest,
            requiredCapabilities: CodexBarTypeMapping.conservativeCapabilities)
        let planningDecision = self.policy.evaluatePlanning(planningCandidate)
        guard planningDecision.allowed else {
            return self.failureOutcome(
                request: request,
                startedAt: startedAt,
                attempts: [],
                failure: CollectorFailure(
                    code: "planning_policy_denied",
                    message: "Strategy resolution was denied by policy rule \(planningDecision.ruleID)."))
        }

        if Task.isCancelled {
            return self.failureOutcome(
                request: request,
                startedAt: startedAt,
                attempts: [],
                failure: CollectorFailure(
                    code: "cancelled",
                    message: "Collection was cancelled."))
        }

        let descriptor = self.descriptorFor(provider)
        let sourceMode = CodexBarTypeMapping.source(request.source)
        guard descriptor.fetchPlan.sourceModes.contains(sourceMode) else {
            return self.failureOutcome(
                request: request,
                startedAt: startedAt,
                attempts: [],
                failure: CollectorFailure(
                    code: "unsupported_source",
                    message: "The requested source mode is not supported by this provider."))
        }

        let hostContext: ResolvedHostContext
        do {
            hostContext = try await self.resolveHostContext(for: request)
        } catch let failure as CollectorFailureError {
            return self.failureOutcome(
                request: request,
                startedAt: startedAt,
                attempts: [],
                failure: failure.failure)
        } catch {
            return self.failureOutcome(
                request: request,
                startedAt: startedAt,
                attempts: [],
                failure: CollectorFailure(
                    code: "account_context_failed",
                    message: "The host could not resolve the selected account context."))
        }

        guard hostContext.settings?.debugKeepCLISessionsAlive != true else {
            return self.failureOutcome(
                request: request,
                startedAt: startedAt,
                attempts: [],
                accountResolution: hostContext.accountResolution,
                failure: CollectorFailure(
                    code: "persistent_cli_sessions_disallowed",
                    message: "The staging facade does not allow persistent CLI sessions."))
        }

        if Task.isCancelled {
            return self.failureOutcome(
                request: request,
                startedAt: startedAt,
                attempts: [],
                accountResolution: hostContext.accountResolution,
                failure: CollectorFailure(
                    code: "cancelled",
                    message: "Collection was cancelled."))
        }

        let environment = hostContext.environment
        let runtime = CodexBarTypeMapping.runtime(self.configuration.runtime)
        let context = ProviderFetchContext(
            runtime: runtime,
            sourceMode: sourceMode,
            includeCredits: request.includeCredits,
            includeOptionalUsage: request.includeOptionalUsage,
            webTimeout: self.configuration.webTimeout,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: hostContext.settings,
            fetcher: UsageFetcher(environment: environment),
            claudeFetcher: ClaudeUsageFetcher(
                browserDetection: self.browserDetection,
                environment: environment,
                runtime: runtime,
                keepCLISessionsAlive: false),
            browserDetection: self.browserDetection,
            selectedTokenAccountID: hostContext.selectedTokenAccountID,
            tokenAccountTokenUpdater: self.tokenAccountTokenUpdater(
                confirmedAccountID: hostContext.accountResolution.confirmedAccountID),
            providerManualTokenUpdater: self.providerManualTokenUpdater(
                accountResolution: hostContext.accountResolution),
            costUsageHistoryDays: self.configuration.costUsageHistoryDays,
            persistsCLISessions: false,
            persistentCLISessionIdleWindow: nil)

        let interaction = CodexBarTypeMapping.interaction(request.interaction)
        return await ProviderInteractionContext.$current.withValue(interaction) {
            await self.execute(
                descriptor: descriptor,
                context: context,
                policyRequest: policyRequest,
                request: request,
                startedAt: startedAt,
                accountResolution: hostContext.accountResolution,
                identityExpectation: hostContext.identityExpectation)
        }
    }

    public func shutdown() async {
        await ProviderCLISessionLifecycle.shutdownPersistentSessions()
    }

    private func tokenAccountTokenUpdater(
        confirmedAccountID: UUID?) -> ProviderFetchContext.TokenAccountTokenUpdater?
    {
        guard let updater = self.host.tokenAccountTokenUpdater else { return nil }
        return { provider, accountID, token in
            guard confirmedAccountID == nil || confirmedAccountID == accountID else { return }
            await updater(CodexBarTypeMapping.provider(provider), accountID, token)
        }
    }

    private func providerManualTokenUpdater(
        accountResolution: CollectorAccountResolution)
        -> ProviderFetchContext.ProviderManualTokenUpdater?
    {
        guard accountResolution.kind == .ambient else { return nil }
        guard let updater = self.host.providerManualTokenUpdater else { return nil }
        return { provider, token in
            await updater(CodexBarTypeMapping.provider(provider), token)
        }
    }

    private func execute(
        descriptor: ProviderDescriptor,
        context: ProviderFetchContext,
        policyRequest: CollectorPolicyRequest,
        request: CollectorRequest,
        startedAt: Date,
        accountResolution: CollectorAccountResolution,
        identityExpectation: CodexBarAccountIdentityExpectation?) async -> CollectorOutcome
    {
        if Task.isCancelled {
            return self.failureOutcome(
                request: request,
                startedAt: startedAt,
                attempts: [],
                accountResolution: accountResolution,
                failure: CollectorFailure(
                    code: "cancelled",
                    message: "Collection was cancelled."))
        }
        let strategies = await descriptor.fetchPlan.pipeline.resolveStrategies(context)
        var attempts: [CollectorAttempt] = []
        attempts.reserveCapacity(strategies.count)

        for (index, strategy) in strategies.enumerated() {
            if Task.isCancelled {
                return self.failureOutcome(
                    request: request,
                    startedAt: startedAt,
                    attempts: attempts,
                    accountResolution: accountResolution,
                    failure: CollectorFailure(
                        code: "cancelled",
                        message: "Collection was cancelled."))
            }

            let kind = CodexBarTypeMapping.strategyKind(strategy.kind)
            let candidate = CollectorSourceCandidate(
                request: policyRequest,
                strategyID: strategy.id,
                kind: kind,
                requiredCapabilities: CodexBarTypeMapping.conservativeCapabilities)
            let decision = self.policy.evaluateStrategy(candidate)
            guard decision.allowed else {
                attempts.append(CollectorAttempt(
                    index: index,
                    strategyID: strategy.id,
                    kind: kind,
                    disposition: .policyDenied,
                    policyRuleID: decision.ruleID,
                    failure: CollectorFailure(
                        code: "strategy_policy_denied",
                        message: "Strategy was denied before its availability probe.")))
                continue
            }

            let available = await strategy.isAvailable(context)
            if Task.isCancelled {
                attempts.append(CollectorAttempt(
                    index: index,
                    strategyID: strategy.id,
                    kind: kind,
                    disposition: .cancelled,
                    policyRuleID: decision.ruleID,
                    failure: CollectorFailure(
                        code: "cancelled",
                        message: "Collection was cancelled during strategy availability.")))
                return self.failureOutcome(
                    request: request,
                    startedAt: startedAt,
                    attempts: attempts,
                    accountResolution: accountResolution,
                    failure: CollectorFailure(
                        code: "cancelled",
                        message: "Collection was cancelled."))
            }
            guard available else {
                attempts.append(CollectorAttempt(
                    index: index,
                    strategyID: strategy.id,
                    kind: kind,
                    disposition: .unavailable,
                    policyRuleID: decision.ruleID))
                continue
            }

            do {
                let result = try await strategy.fetch(context)
                try Task.checkCancellation()

                guard result.strategyID == strategy.id,
                      result.strategyKind == strategy.kind
                else {
                    let failure = CollectorFailure(
                        code: "strategy_provenance_mismatch",
                        message: "CodexBar returned data for a strategy other than the exact policy-approved strategy.")
                    attempts.append(CollectorAttempt(
                        index: index,
                        strategyID: strategy.id,
                        kind: kind,
                        disposition: .failed,
                        policyRuleID: decision.ruleID,
                        fallbackAllowed: false,
                        failure: failure))
                    return self.failureOutcome(
                        request: request,
                        startedAt: startedAt,
                        attempts: attempts,
                        accountResolution: accountResolution,
                        failure: failure)
                }

                var successfulAccountResolution = accountResolution
                if let identityExpectation {
                    let validation = identityExpectation.validate(
                        CodexBarResultMapper.identity(result.usage.identity),
                        additionalAccountEmail: result.dashboard?.signedInEmail)
                    guard validation == .verified else {
                        let failure = switch validation {
                        case .insufficientEvidence:
                            CollectorFailure(
                                code: "account_identity_insufficient",
                                message: "The result did not contain enough provider identity evidence for the selected account.")
                        case .mismatch:
                            CollectorFailure(
                                code: "account_identity_mismatch",
                                message: "The provider-reported identity did not match the selected account.")
                        case .verified:
                            preconditionFailure("Verified account identity passed the guard.")
                        }
                        attempts.append(CollectorAttempt(
                            index: index,
                            strategyID: strategy.id,
                            kind: kind,
                            disposition: .identityRejected,
                            policyRuleID: decision.ruleID,
                            fallbackAllowed: false,
                            failure: failure))
                        return self.failureOutcome(
                            request: request,
                            startedAt: startedAt,
                            attempts: attempts,
                            accountResolution: accountResolution,
                            failure: failure)
                    }
                    successfulAccountResolution = CollectorAccountResolution(
                        kind: .resultVerified,
                        confirmedAccountID: accountResolution.confirmedAccountID)
                }

                attempts.append(CollectorAttempt(
                    index: index,
                    strategyID: strategy.id,
                    kind: kind,
                    disposition: .succeeded,
                    policyRuleID: decision.ruleID))
                return self.successOutcome(
                    request: request,
                    startedAt: startedAt,
                    attempts: attempts,
                    result: result,
                    metadata: descriptor.metadata,
                    accountResolution: successfulAccountResolution)
            } catch {
                if Task.isCancelled || error is CancellationError {
                    attempts.append(CollectorAttempt(
                        index: index,
                        strategyID: strategy.id,
                        kind: kind,
                        disposition: .cancelled,
                        policyRuleID: decision.ruleID,
                        failure: CollectorFailure(
                            code: "cancelled",
                            message: "Collection was cancelled during strategy execution.")))
                    return self.failureOutcome(
                        request: request,
                        startedAt: startedAt,
                        attempts: attempts,
                        accountResolution: accountResolution,
                        failure: CollectorFailure(
                            code: "cancelled",
                            message: "Collection was cancelled."))
                }

                let fallbackAllowed = strategy.shouldFallback(on: error, context: context)
                attempts.append(CollectorAttempt(
                    index: index,
                    strategyID: strategy.id,
                    kind: kind,
                    disposition: .failed,
                    policyRuleID: decision.ruleID,
                    fallbackAllowed: fallbackAllowed,
                    failure: CollectorFailure(
                        code: "strategy_failed",
                        message: "The allowed CodexBar strategy failed.")))
                if fallbackAllowed {
                    continue
                }
                return self.failureOutcome(
                    request: request,
                    startedAt: startedAt,
                    attempts: attempts,
                    accountResolution: accountResolution,
                    failure: CollectorFailure(
                        code: "fetch_failed",
                        message: "CodexBar collection failed without an allowed fallback."))
            }
        }

        return self.failureOutcome(
            request: request,
            startedAt: startedAt,
            attempts: attempts,
            accountResolution: accountResolution,
            failure: CollectorFailure(
                code: "no_allowed_available_strategy",
                message: "No strategy was both policy-allowed and available."))
    }

    private func successOutcome(
        request: CollectorRequest,
        startedAt: Date,
        attempts: [CollectorAttempt],
        result: ProviderFetchResult,
        metadata: ProviderMetadata,
        accountResolution: CollectorAccountResolution) -> CollectorOutcome
    {
        let finishedAt = self.configuration.now()
        let usage = CodexBarResultMapper.usage(result.usage, metadata: metadata)
        let credits = CodexBarResultMapper.credits(result.credits, dashboard: result.dashboard)
        return CollectorOutcome(
            provider: request.provider,
            account: request.account,
            accountResolution: accountResolution,
            requestedSource: request.source,
            resolvedSource: CollectorResolvedSource(
                label: result.sourceLabel,
                strategyID: result.strategyID,
                kind: CodexBarTypeMapping.strategyKind(result.strategyKind)),
            startedAt: startedAt,
            finishedAt: finishedAt,
            attempts: attempts,
            usage: usage,
            credits: credits,
            artifacts: CodexBarArtifactMapper.artifacts(provider: request.provider, result: result),
            diagnostics: CodexBarArtifactMapper.diagnostics(result),
            credentialOwnership: CodexBarArtifactMapper.credentialOwnership(
                provider: request.provider,
                result: result),
            freshness: CollectorFreshness(
                collectedAt: finishedAt,
                usageObservedAt: usage.observedAt,
                creditsObservedAt: credits?.observedAt,
                costObservedAt: usage.cost?.observedAt),
            failure: nil)
    }

    private func failureOutcome(
        request: CollectorRequest,
        startedAt: Date,
        attempts: [CollectorAttempt],
        accountResolution: CollectorAccountResolution = CollectorAccountResolution(kind: .unresolved),
        failure: CollectorFailure) -> CollectorOutcome
    {
        let finishedAt = self.configuration.now()
        return CollectorOutcome(
            provider: request.provider,
            account: request.account,
            accountResolution: accountResolution,
            requestedSource: request.source,
            resolvedSource: nil,
            startedAt: startedAt,
            finishedAt: finishedAt,
            attempts: attempts,
            usage: nil,
            credits: nil,
            artifacts: [],
            diagnostics: [],
            credentialOwnership: nil,
            freshness: CollectorFreshness(
                collectedAt: finishedAt,
                usageObservedAt: nil,
                creditsObservedAt: nil,
                costObservedAt: nil),
            failure: failure)
    }

    private func resolveHostContext(for request: CollectorRequest) async throws -> ResolvedHostContext {
        let baseEnvironment = self.configuration.resolvedEnvironment(for: request.provider)
        guard !request.account.isAmbient else {
            return ResolvedHostContext(
                environment: baseEnvironment,
                settings: self.host.settings,
                selectedTokenAccountID: nil,
                accountResolution: CollectorAccountResolution(kind: .ambient),
                identityExpectation: nil)
        }

        guard let requestedID = request.account.id else {
            throw CollectorFailureError(CollectorFailure(
                code: "invalid_account_selection",
                message: "A selected account requires a stable account ID."))
        }
        guard let resolver = self.host.accountResolver else {
            throw CollectorFailureError(CollectorFailure(
                code: "account_context_required",
                message: "A selected account requires an explicit host account resolver."))
        }

        let resolved = try await resolver(request.provider, request.account)
        guard resolved.confirmedAccountID == requestedID else {
            throw CollectorFailureError(CollectorFailure(
                code: "account_context_mismatch",
                message: "The host resolved a different account than the one requested."))
        }
        guard resolved.identityExpectation.provider == request.provider,
              resolved.identityExpectation.hasStableAnchor
        else {
            throw CollectorFailureError(CollectorFailure(
                code: "account_identity_expectation_invalid",
                message: "The selected account requires an exact provider identity expectation."))
        }
        return ResolvedHostContext(
            environment: resolved.environment,
            settings: resolved.settings,
            selectedTokenAccountID: resolved.selectedTokenAccountID,
            accountResolution: CollectorAccountResolution(
                kind: .hostResolved,
                confirmedAccountID: resolved.confirmedAccountID),
            identityExpectation: resolved.identityExpectation)
    }
}

private struct ResolvedHostContext: Sendable {
    let environment: [String: String]
    let settings: ProviderSettingsSnapshot?
    let selectedTokenAccountID: UUID?
    let accountResolution: CollectorAccountResolution
    let identityExpectation: CodexBarAccountIdentityExpectation?
}

private struct CollectorFailureError: Error {
    let failure: CollectorFailure

    init(_ failure: CollectorFailure) {
        self.failure = failure
    }
}
