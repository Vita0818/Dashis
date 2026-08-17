import CodexBarCore
@testable import CodexBarCollector
import DashisCollectorContract
import XCTest

final class CodexBarCollectorTests: XCTestCase {
    func testCatalogMatchesEveryPinnedCoreProvider() async {
        let collector = CodexBarCollector()
        let catalog = await collector.catalog()

        XCTAssertEqual(catalog.count, 63)
        XCTAssertEqual(
            Set(catalog.map(\.id.rawValue)),
            Set(UsageProvider.allCases.map(\.rawValue)))
    }

    func testRolloutCatalogLocksSelectedProviderAndStrategyScope() {
        let providerIDs = CollectorRolloutCatalog.selectedProviderIDs.map(\.rawValue)
        XCTAssertEqual(providerIDs.count, 34)
        XCTAssertEqual(Set(providerIDs).count, 34)
        XCTAssertEqual(
            providerIDs,
            [
                "codex", "openai", "azureopenai", "claude", "clinepass", "cursor",
                "opencode", "opencodego", "alibaba", "alibabatokenplan", "gemini",
                "antigravity", "copilot", "zai", "minimax", "kimi", "vertexai",
                "moonshot", "ollama", "openrouter", "perplexity", "mimo", "doubao",
                "sakana", "mistral", "deepseek", "venice", "commandcode", "qoder",
                "stepfun", "bedrock", "grok", "longcat", "zenmux",
            ])

        let strategies = CollectorRolloutCatalog.strategies
        XCTAssertEqual(strategies.count, 52)
        XCTAssertEqual(
            Set(strategies.map(\.provider.rawValue)),
            Set(providerIDs))
        XCTAssertEqual(
            Set(strategies.map { "\($0.provider.rawValue):\($0.strategyID)" }).count,
            strategies.count)

        let bindings = CollectorRolloutCatalog.bindings
        XCTAssertEqual(bindings.count, 50)
        XCTAssertEqual(Set(bindings.map(\.id)).count, bindings.count)
        XCTAssertTrue(bindings.allSatisfy { $0.source != .auto })
        XCTAssertTrue(bindings.allSatisfy {
            $0.releaseGates == [
                .exactEffectManifest,
                .brokeredHostServices,
                .operationScopedHardTermination,
                .signedRelease,
            ]
        })
        XCTAssertEqual(
            CollectorRolloutCatalog.liveAuthorizationCount,
            CollectorLiveRouteCatalog.routes.count)
    }

    func testLiveCatalogPublishesAllExplicitRoutesForThirtyExtendedProviders() {
        let routes = CollectorLiveRouteCatalog.routes
        XCTAssertEqual(routes.count, 41)
        XCTAssertEqual(Set(routes.map(\.id)).count, routes.count)
        XCTAssertEqual(CollectorLiveRouteCatalog.providerIDs.count, 30)
        XCTAssertEqual(Set(CollectorLiveRouteCatalog.providerIDs).count, 30)
        XCTAssertTrue(routes.allSatisfy { $0.source != .auto })
        XCTAssertTrue(routes.allSatisfy {
            !CollectorLiveRouteCatalog.nativeFrontendProviderIDs.contains($0.provider)
        })
        XCTAssertTrue(routes.allSatisfy { route in
            CollectorRolloutCatalog.bindings.contains { binding in
                binding.provider == route.provider
                    && binding.source == route.source
                    && binding.strategyID == route.strategyID
                    && binding.kind == route.strategyKind
            }
        })
        XCTAssertFalse(routes.contains { route in
            ["opencodego.local", "kimi.cli", "mimo.local"]
                .contains(route.strategyID)
        })
        XCTAssertTrue(routes.filter(\.requiresConsent).allSatisfy {
            !$0.riskSummary.isEmpty
        })
        XCTAssertTrue(routes.allSatisfy {
            Set($0.allowedConfigurationKeys).count
                == $0.allowedConfigurationKeys.count
        })
        XCTAssertEqual(
            CollectorRolloutCatalog.liveAuthorizationCount,
            routes.count)
    }

    func testRolloutCatalogKeepsAutomaticOnlyAndRiskyStrategiesBlocked() {
        XCTAssertEqual(
            Set(CollectorRolloutCatalog.automaticOnlyStrategies.map(\.strategyID)),
            Set(["opencodego.local", "kimi.cli", "mimo.local"]))
        XCTAssertTrue(
            CollectorRolloutCatalog.automaticOnlyStrategies.allSatisfy {
                $0.releaseGates.contains(.explicitSourceBinding)
            })

        let cursor = CollectorRolloutCatalog.strategies.first {
            $0.strategyID == "cursor.web"
        }
        XCTAssertEqual(cursor?.explicitSources, [.cli, .web])

        let billable = Set(CollectorRolloutCatalog.strategies.compactMap {
            $0.observedEffects.contains(.potentiallyBillable)
                ? $0.strategyID
                : nil
        })
        XCTAssertEqual(
            billable,
            Set([
                "azureopenai.api",
                "ollama.api",
                "doubao.api",
                "bedrock.api",
            ]))
    }

    func testRolloutCatalogRecordsAuditedInteractiveAndProcessEffects() {
        let byID = Dictionary(
            uniqueKeysWithValues: CollectorRolloutCatalog.strategies.map {
                ($0.strategyID, Set($0.observedEffects))
            })

        XCTAssertFalse(
            byID["openai.api.balance"]?.contains(.configurableEndpoint) ?? true)
        XCTAssertFalse(
            byID["minimax.api"]?.contains(.configurableEndpoint) ?? true)
        XCTAssertTrue(byID["claude.cli"]?.contains(.browserLaunch) == true)
        XCTAssertTrue(byID["claude.cli"]?.contains(.credentialWrite) == true)
        XCTAssertTrue(byID["antigravity.app-local"]?.contains(.subprocess) == true)
        XCTAssertTrue(byID["antigravity.ide-local"]?.contains(.subprocess) == true)
        XCTAssertTrue(byID["bedrock.api"]?.contains(.configurableEndpoint) == true)
        XCTAssertTrue(
            byID["deepseek.api"]?.isSuperset(
                of: [.providerLocalStateRead, .browserSessionRead]) == true)
        XCTAssertFalse(byID["deepseek.web"]?.contains(.keychainRead) ?? true)
        XCTAssertTrue(
            byID["commandcode.web"]?.contains(.localStateWrite) == true)
        XCTAssertTrue(byID["stepfun.web"]?.contains(.keychainRead) == true)
        XCTAssertTrue(byID["grok.web"]?.contains(.subprocess) == true)
        XCTAssertTrue(byID["grok.web"]?.contains(.localStateWrite) == true)
        XCTAssertTrue(byID["longcat.web"]?.contains(.localStateWrite) == true)
    }

    func testSelectedRolloutBindingsExistInPinnedProviderCatalog() async {
        let collector = CodexBarCollector()
        let catalog = await collector.catalog()
        let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })

        XCTAssertTrue(CollectorRolloutCatalog.selectedProviderIDs.allSatisfy {
            byID[$0] != nil
        })
        XCTAssertTrue(CollectorRolloutCatalog.bindings.allSatisfy { binding in
            byID[binding.provider]?.supportedSources.contains(binding.source) == true
        })
    }

    func testDefaultPolicyDeniesBeforeStrategyResolution() async {
        let collector = CodexBarCollector()
        let result = await collector.collect(CollectorRequest(
            provider: "openrouter",
            source: .api))

        XCTAssertEqual(result.failure?.code, "request_policy_denied")
        XCTAssertTrue(result.attempts.isEmpty)
        XCTAssertNil(result.usage)
    }

    func testStaticPolicyFailsClosedOnMissingCapabilities() {
        let policy = StaticCollectorSourcePolicy(
            allowedCapabilities: [.network],
            requestRules: [
                CollectorRequestRule(
                    id: "allow-request",
                    provider: "openrouter",
                    account: .ambient,
                    source: .api,
                    runtime: .app,
                    includeCredits: false,
                    includeOptionalUsage: false,
                    interaction: .userInitiated,
                    allow: true,
                    reason: "test"),
            ],
            strategyRules: [
                CollectorStrategyRule(
                    id: "allow-strategy",
                    provider: "openrouter",
                    account: .ambient,
                    source: .api,
                    runtime: .app,
                    includeCredits: false,
                    includeOptionalUsage: false,
                    interaction: .userInitiated,
                    strategyID: "openrouter.api",
                    kind: .apiToken,
                    allow: true,
                    reason: "test"),
            ])
        let request = CollectorPolicyRequest(
            provider: "openrouter",
            account: .ambient,
            requestedSource: .api,
            runtime: .app,
            includeCredits: false,
            includeOptionalUsage: false,
            interaction: .userInitiated)
        let candidate = CollectorSourceCandidate(
            request: request,
            strategyID: "openrouter.api",
            kind: .apiToken,
            requiredCapabilities: [.network, .providerLocalState])

        let decision = policy.evaluateStrategy(candidate)

        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.ruleID, "capability-deny-strategy")
    }

    func testMapperPreservesOverQuotaAndUnknownExtraWindow() {
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let primary = RateWindow(
            usedPercent: 125,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: nil)
        let resetOnly = RateWindow(
            usedPercent: 0,
            windowMinutes: 10_080,
            resetsAt: observedAt.addingTimeInterval(3600),
            resetDescription: "later",
            isSyntheticPlaceholder: true)
        let snapshot = UsageSnapshot(
            primary: primary,
            secondary: nil,
            extraRateWindows: [
                NamedRateWindow(
                    id: "reset-only",
                    title: "Reset only",
                    window: resetOnly,
                    usageKnown: false),
            ],
            updatedAt: observedAt,
            dataConfidence: .exact)

        let metadata = ProviderDescriptorRegistry.descriptor(for: .openrouter).metadata
        let mapped = CodexBarResultMapper.usage(snapshot, metadata: metadata)

        XCTAssertEqual(mapped.windows[0].usedPercent, 125)
        XCTAssertEqual(mapped.windows[0].remainingPercent, -25)
        XCTAssertTrue(mapped.windows[1].isSyntheticPlaceholder)
        XCTAssertFalse(mapped.windows[1].usageKnown)
    }

    func testFreshnessUsesOldestComponentTimestamp() {
        let usageAt = Date(timeIntervalSince1970: 300)
        let creditsAt = Date(timeIntervalSince1970: 200)
        let costAt = Date(timeIntervalSince1970: 400)

        let freshness = CollectorFreshness(
            collectedAt: Date(timeIntervalSince1970: 500),
            usageObservedAt: usageAt,
            creditsObservedAt: creditsAt,
            costObservedAt: costAt)

        XCTAssertEqual(freshness.conservativeObservedAt, creditsAt)
    }

    func testDefaultConfigurationDoesNotInheritProcessEnvironment() {
        let configuration = CollectorConfiguration()

        XCTAssertTrue(configuration.resolvedEnvironment(for: "codex").isEmpty)
    }

    func testPlanningDenialDoesNotInvokeResolver() async {
        let recorder = CallRecorder()
        let descriptor = self.stubDescriptor(strategies: [], recorder: recorder)
        let policy = self.policy(
            planningAllowed: false,
            strategyIDs: [])
        let collector = CodexBarCollector(
            configuration: CollectorConfiguration(),
            policy: policy,
            host: .disabled,
            descriptorFor: { _ in descriptor })

        let outcome = await collector.collect(self.request())
        let calls = await recorder.values()

        XCTAssertEqual(outcome.failure?.code, "planning_policy_denied")
        XCTAssertEqual(calls, [])
    }

    func testStrategyDenialDoesNotProbeAvailability() async {
        let recorder = CallRecorder()
        let strategy = StubStrategy(
            id: "stub.denied",
            kind: .apiToken,
            recorder: recorder,
            available: true,
            result: self.fetchResult(strategyID: "stub.denied"),
            fallbackAllowed: false)
        let descriptor = self.stubDescriptor(strategies: [strategy], recorder: recorder)
        let policy = self.policy(planningAllowed: true, strategyIDs: [])
        let collector = CodexBarCollector(
            configuration: CollectorConfiguration(),
            policy: policy,
            host: .disabled,
            descriptorFor: { _ in descriptor })

        let outcome = await collector.collect(self.request())
        let calls = await recorder.values()

        XCTAssertEqual(outcome.failure?.code, "no_allowed_available_strategy")
        XCTAssertEqual(calls, ["resolve"])
        XCTAssertEqual(outcome.attempts.map(\.disposition), [.policyDenied])
    }

    func testFallbackOrderIsPreserved() async {
        let recorder = CallRecorder()
        let first = StubStrategy(
            id: "stub.first",
            kind: .apiToken,
            recorder: recorder,
            available: true,
            error: StubError.failed,
            fallbackAllowed: true)
        let second = StubStrategy(
            id: "stub.second",
            kind: .apiToken,
            recorder: recorder,
            available: true,
            result: self.fetchResult(
                strategyID: "stub.second",
                diagnostic: "suppressed detail"),
            fallbackAllowed: false)
        let descriptor = self.stubDescriptor(strategies: [first, second], recorder: recorder)
        let collector = CodexBarCollector(
            configuration: CollectorConfiguration(),
            policy: self.policy(
                planningAllowed: true,
                strategyIDs: ["stub.first", "stub.second"]),
            host: .disabled,
            descriptorFor: { _ in descriptor })

        let outcome = await collector.collect(self.request())
        let calls = await recorder.values()

        XCTAssertNil(outcome.failure)
        XCTAssertEqual(outcome.diagnostics.map(\.code), ["upstream_diagnostic_present"])
        XCTAssertEqual(outcome.resolvedSource?.strategyID, "stub.second")
        XCTAssertEqual(outcome.attempts.map(\.disposition), [.failed, .succeeded])
        XCTAssertEqual(
            calls,
            ["resolve", "available:stub.first", "fetch:stub.first",
             "available:stub.second", "fetch:stub.second"])
    }

    func testStrategyResultMustMatchTheExactApprovedStrategy() async {
        let recorder = CallRecorder()
        let strategy = StubStrategy(
            id: "stub.approved",
            kind: .apiToken,
            recorder: recorder,
            available: true,
            result: self.fetchResult(strategyID: "stub.unapproved"),
            fallbackAllowed: true)
        let descriptor = self.stubDescriptor(strategies: [strategy], recorder: recorder)
        let collector = CodexBarCollector(
            configuration: CollectorConfiguration(),
            policy: self.policy(
                planningAllowed: true,
                strategyIDs: ["stub.approved"]),
            host: .disabled,
            descriptorFor: { _ in descriptor })

        let outcome = await collector.collect(self.request())
        let calls = await recorder.values()

        XCTAssertEqual(outcome.failure?.code, "strategy_provenance_mismatch")
        XCTAssertNil(outcome.resolvedSource)
        XCTAssertNil(outcome.usage)
        XCTAssertEqual(outcome.attempts.map(\.disposition), [.failed])
        XCTAssertEqual(outcome.attempts.first?.fallbackAllowed, false)
        XCTAssertEqual(calls, ["resolve", "available:stub.approved", "fetch:stub.approved"])
    }

    func testSelectedAccountRequiresHostResolution() async {
        let accountID = UUID()
        let recorder = CallRecorder()
        let descriptor = self.stubDescriptor(strategies: [], recorder: recorder)
        let request = self.request(account: CollectorAccountSelection(id: accountID, label: "Work"))
        let collector = CodexBarCollector(
            configuration: CollectorConfiguration(),
            policy: self.policy(
                account: .selected(accountID),
                planningAllowed: true,
                strategyIDs: []),
            host: .disabled,
            descriptorFor: { _ in descriptor })

        let outcome = await collector.collect(request)
        let calls = await recorder.values()

        XCTAssertEqual(outcome.failure?.code, "account_context_required")
        XCTAssertEqual(outcome.accountResolution.kind, .unresolved)
        XCTAssertEqual(calls, [])
    }

    func testSelectedAccountResolverInjectsConfirmedContext() async throws {
        let accountID = UUID()
        let recorder = CallRecorder()
        let identity = ProviderIdentitySnapshot(
            providerID: .openrouter,
            accountEmail: "work@example.com",
            accountOrganization: nil,
            loginMethod: "token")
        let result = self.fetchResult(
            strategyID: "stub.account",
            identity: identity)
        let strategy = ContextCheckingStrategy(
            id: "stub.account",
            recorder: recorder,
            expectedEnvironment: ["TEST_ACCOUNT_TOKEN": "secret"],
            expectedAccountID: accountID,
            expectsSettingsNil: true,
            result: result)
        let descriptor = self.stubDescriptor(strategies: [strategy], recorder: recorder)
        let host = CodexBarHostConfiguration(
            settings: ProviderSettingsSnapshot.make(debugMenuEnabled: true),
            accountResolver: { _, _ in
                CodexBarResolvedAccountContext(
                    confirmedAccountID: accountID,
                    environment: ["TEST_ACCOUNT_TOKEN": "secret"],
                    selectedTokenAccountID: accountID,
                    identityExpectation: CodexBarAccountIdentityExpectation(
                        provider: "openrouter",
                        accountEmail: "work@example.com",
                        loginMethod: "token"))
            })
        let collector = CodexBarCollector(
            configuration: CollectorConfiguration(
                environment: [
                    "TEST_ACCOUNT_TOKEN": "ambient",
                    "AMBIENT_ONLY_TOKEN": "must-not-leak",
                ]),
            policy: self.policy(
                account: .selected(accountID),
                planningAllowed: true,
                strategyIDs: ["stub.account"]),
            host: host,
            descriptorFor: { _ in descriptor })

        let outcome = await collector.collect(
            self.request(account: CollectorAccountSelection(id: accountID, label: "Work")))
        let calls = await recorder.values()

        XCTAssertNil(outcome.failure)
        XCTAssertEqual(outcome.schemaVersion, 2)
        XCTAssertEqual(outcome.accountResolution.kind, .resultVerified)
        XCTAssertEqual(outcome.accountResolution.confirmedAccountID, accountID)
        XCTAssertEqual(calls, ["resolve", "available:stub.account", "fetch:stub.account"])
        let encoded = try JSONEncoder().encode(outcome)
        XCTAssertEqual(try JSONDecoder().decode(CollectorOutcome.self, from: encoded), outcome)
    }

    func testSelectedAccountResolverRejectsMismatchedHostAccountID() async {
        let accountID = UUID()
        let recorder = CallRecorder()
        let descriptor = self.stubDescriptor(strategies: [], recorder: recorder)
        let host = CodexBarHostConfiguration(accountResolver: { _, _ in
            CodexBarResolvedAccountContext(
                confirmedAccountID: UUID(),
                environment: [:],
                identityExpectation: CodexBarAccountIdentityExpectation(
                    provider: "openrouter",
                    accountEmail: "work@example.com"))
        })
        let collector = CodexBarCollector(
            configuration: CollectorConfiguration(),
            policy: self.policy(
                account: .selected(accountID),
                planningAllowed: true,
                strategyIDs: []),
            host: host,
            descriptorFor: { _ in descriptor })

        let outcome = await collector.collect(
            self.request(account: CollectorAccountSelection(id: accountID, label: "Work")))
        let calls = await recorder.values()

        XCTAssertEqual(outcome.failure?.code, "account_context_mismatch")
        XCTAssertEqual(outcome.accountResolution.kind, .unresolved)
        XCTAssertEqual(calls, [])
    }

    func testSelectedAccountRejectsIdentityExpectationWithoutStableAnchor() async {
        let accountID = UUID()
        let recorder = CallRecorder()
        let descriptor = self.stubDescriptor(strategies: [], recorder: recorder)
        let host = CodexBarHostConfiguration(accountResolver: { _, _ in
            CodexBarResolvedAccountContext(
                confirmedAccountID: accountID,
                environment: [:],
                identityExpectation: CodexBarAccountIdentityExpectation(
                    provider: "openrouter",
                    accountEmail: "   "))
        })
        let collector = CodexBarCollector(
            configuration: CollectorConfiguration(),
            policy: self.policy(
                account: .selected(accountID),
                planningAllowed: true,
                strategyIDs: []),
            host: host,
            descriptorFor: { _ in descriptor })

        let outcome = await collector.collect(
            self.request(account: CollectorAccountSelection(id: accountID, label: "Work")))
        let calls = await recorder.values()

        XCTAssertEqual(outcome.failure?.code, "account_identity_expectation_invalid")
        XCTAssertEqual(outcome.accountResolution.kind, .unresolved)
        XCTAssertEqual(calls, [])
    }

    func testSelectedAccountRejectsMismatchedProviderReportedIdentity() async {
        let accountID = UUID()
        let recorder = CallRecorder()
        let result = self.fetchResult(
            strategyID: "stub.account",
            identity: ProviderIdentitySnapshot(
                providerID: .openrouter,
                accountEmail: "other@example.com",
                accountOrganization: nil,
                loginMethod: nil))
        let strategy = StubStrategy(
            id: "stub.account",
            kind: .apiToken,
            recorder: recorder,
            available: true,
            result: result,
            fallbackAllowed: true)
        let descriptor = self.stubDescriptor(strategies: [strategy], recorder: recorder)
        let host = CodexBarHostConfiguration(accountResolver: { _, _ in
            CodexBarResolvedAccountContext(
                confirmedAccountID: accountID,
                environment: [:],
                identityExpectation: CodexBarAccountIdentityExpectation(
                    provider: "openrouter",
                    accountEmail: "work@example.com"))
        })
        let collector = CodexBarCollector(
            configuration: CollectorConfiguration(),
            policy: self.policy(
                account: .selected(accountID),
                planningAllowed: true,
                strategyIDs: ["stub.account"]),
            host: host,
            descriptorFor: { _ in descriptor })

        let outcome = await collector.collect(
            self.request(account: CollectorAccountSelection(id: accountID, label: "Work")))
        let calls = await recorder.values()

        XCTAssertEqual(outcome.failure?.code, "account_identity_mismatch")
        XCTAssertEqual(outcome.accountResolution.kind, .hostResolved)
        XCTAssertNil(outcome.usage)
        XCTAssertEqual(outcome.attempts.map(\.disposition), [.identityRejected])
        XCTAssertEqual(outcome.attempts.first?.fallbackAllowed, false)
        XCTAssertEqual(calls, ["resolve", "available:stub.account", "fetch:stub.account"])
    }

    func testSelectedAccountRejectsMissingProviderIdentityWithoutFallback() async {
        let accountID = UUID()
        let recorder = CallRecorder()
        let first = StubStrategy(
            id: "stub.missing-identity",
            kind: .apiToken,
            recorder: recorder,
            available: true,
            result: self.fetchResult(strategyID: "stub.missing-identity"),
            fallbackAllowed: true)
        let second = StubStrategy(
            id: "stub.must-not-run",
            kind: .apiToken,
            recorder: recorder,
            available: true,
            result: self.fetchResult(
                strategyID: "stub.must-not-run",
                identity: ProviderIdentitySnapshot(
                    providerID: .openrouter,
                    accountEmail: "work@example.com",
                    accountOrganization: nil,
                    loginMethod: nil)),
            fallbackAllowed: false)
        let descriptor = self.stubDescriptor(
            strategies: [first, second],
            recorder: recorder)
        let host = self.selectedAccountHost(
            accountID: accountID,
            expectedEmail: "work@example.com")
        let collector = CodexBarCollector(
            configuration: CollectorConfiguration(),
            policy: self.policy(
                account: .selected(accountID),
                planningAllowed: true,
                strategyIDs: ["stub.missing-identity", "stub.must-not-run"]),
            host: host,
            descriptorFor: { _ in descriptor })

        let outcome = await collector.collect(
            self.request(account: CollectorAccountSelection(id: accountID, label: "Work")))
        let calls = await recorder.values()

        XCTAssertEqual(outcome.failure?.code, "account_identity_insufficient")
        XCTAssertEqual(outcome.accountResolution.kind, .hostResolved)
        XCTAssertNil(outcome.usage)
        XCTAssertNil(outcome.credits)
        XCTAssertTrue(outcome.artifacts.isEmpty)
        XCTAssertTrue(outcome.diagnostics.isEmpty)
        XCTAssertEqual(outcome.attempts.map(\.disposition), [.identityRejected])
        XCTAssertEqual(
            calls,
            ["resolve", "available:stub.missing-identity", "fetch:stub.missing-identity"])
    }

    func testSelectedAccountRejectsProviderIdentityForAnotherProvider() async {
        let accountID = UUID()
        let recorder = CallRecorder()
        let strategy = StubStrategy(
            id: "stub.wrong-provider",
            kind: .apiToken,
            recorder: recorder,
            available: true,
            result: self.fetchResult(
                strategyID: "stub.wrong-provider",
                identity: ProviderIdentitySnapshot(
                    providerID: .claude,
                    accountEmail: "work@example.com",
                    accountOrganization: nil,
                    loginMethod: nil)),
            fallbackAllowed: false)
        let descriptor = self.stubDescriptor(strategies: [strategy], recorder: recorder)
        let collector = CodexBarCollector(
            configuration: CollectorConfiguration(),
            policy: self.policy(
                account: .selected(accountID),
                planningAllowed: true,
                strategyIDs: ["stub.wrong-provider"]),
            host: self.selectedAccountHost(
                accountID: accountID,
                expectedEmail: "work@example.com"),
            descriptorFor: { _ in descriptor })

        let outcome = await collector.collect(
            self.request(account: CollectorAccountSelection(id: accountID, label: "Work")))

        XCTAssertEqual(outcome.failure?.code, "account_identity_mismatch")
        XCTAssertEqual(outcome.attempts.map(\.disposition), [.identityRejected])
    }

    func testSelectedAccountRejectsConflictingDashboardIdentity() async {
        let accountID = UUID()
        let recorder = CallRecorder()
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let result = ProviderFetchResult(
            usage: UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: observedAt,
                identity: ProviderIdentitySnapshot(
                    providerID: .openrouter,
                    accountEmail: "work@example.com",
                    accountOrganization: nil,
                    loginMethod: nil)),
            credits: nil,
            dashboard: self.dashboard(
                at: observedAt,
                creditsRemaining: 10,
                signedInEmail: "other@example.com"),
            sourceLabel: "Stub",
            strategyID: "stub.dashboard",
            strategyKind: .apiToken)
        let strategy = StubStrategy(
            id: "stub.dashboard",
            kind: .apiToken,
            recorder: recorder,
            available: true,
            result: result,
            fallbackAllowed: false)
        let descriptor = self.stubDescriptor(strategies: [strategy], recorder: recorder)
        let collector = CodexBarCollector(
            configuration: CollectorConfiguration(),
            policy: self.policy(
                account: .selected(accountID),
                planningAllowed: true,
                strategyIDs: ["stub.dashboard"]),
            host: self.selectedAccountHost(
                accountID: accountID,
                expectedEmail: "work@example.com"),
            descriptorFor: { _ in descriptor })

        let outcome = await collector.collect(
            self.request(account: CollectorAccountSelection(id: accountID, label: "Work")))

        XCTAssertEqual(outcome.failure?.code, "account_identity_mismatch")
        XCTAssertNil(outcome.credits)
        XCTAssertTrue(outcome.artifacts.isEmpty)
        XCTAssertEqual(outcome.attempts.map(\.disposition), [.identityRejected])
    }

    func testLiveArtifactsDashboardDiagnosticsAndOwnershipArePreserved() {
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let zai = ZaiUsageSnapshot(
            tokenLimit: nil,
            timeLimit: nil,
            planName: "Pro",
            updatedAt: observedAt)
        let minimax = MiniMaxUsageSnapshot(
            planName: "Team",
            availablePrompts: 100,
            currentPrompts: 5,
            remainingPrompts: 95,
            windowMinutes: 300,
            usedPercent: 5,
            resetsAt: observedAt,
            updatedAt: observedAt)
        let deepseek = DeepSeekUsageSummary(
            todayTokens: 10,
            currentMonthTokens: 20,
            todayCost: 0.1,
            currentMonthCost: 0.2,
            requestCount: 1,
            currentMonthRequestCount: 2,
            topModel: "chat",
            categoryBreakdown: [],
            daily: [],
            currency: "USD",
            updatedAt: observedAt)
        let opencodego = OpenCodeGoUsageSnapshot(
            hasMonthlyUsage: true,
            rollingUsagePercent: 1,
            weeklyUsagePercent: 2,
            monthlyUsagePercent: 3,
            rollingResetInSec: 60,
            weeklyResetInSec: 120,
            monthlyResetInSec: 180,
            updatedAt: observedAt)
        let usage = UsageSnapshot(
            primary: nil,
            secondary: nil,
            zaiUsage: zai,
            minimaxUsage: minimax,
            deepseekUsage: deepseek,
            deepseekDetailedUsageState: .available,
            deepseekPlatformProfiles: [DeepSeekPlatformProfile(id: "p1", name: "Main")],
            opencodegoUsage: opencodego,
            cursorRequests: CursorRequestUsage(used: 5, limit: 10),
            commandCodeHasSubscriptionPlan: true,
            updatedAt: observedAt)
        let dashboard = self.dashboard(at: observedAt, creditsRemaining: 0)
        let result = ProviderFetchResult(
            usage: usage,
            credits: nil,
            dashboard: dashboard,
            sourceLabel: "Stub",
            strategyID: "stub.artifacts",
            strategyKind: .apiToken,
            diagnostic: "sensitive upstream detail",
            claudeOAuthKeychainPersistentRefHash: "transient",
            claudeOAuthHistoryOwnerIdentifier: "owner",
            claudeOAuthKeychainCredentialMismatch: true)

        let artifacts = CodexBarArtifactMapper.artifacts(provider: "commandcode", result: result)
        let schemaIDs = Set(artifacts.map(\.schemaID))

        XCTAssertEqual(schemaIDs, [
            "codexbar.live.zai.v1",
            "codexbar.live.minimax.v1",
            "codexbar.live.deepseek.v1",
            "codexbar.live.opencodego.v1",
            "codexbar.live.cursor-requests.v1",
            "codexbar.live.commandcode.v1",
            "codexbar.openai-dashboard.v1",
        ])
        XCTAssertEqual(CodexBarArtifactMapper.diagnostics(result).count, 2)
        XCTAssertEqual(
            CodexBarArtifactMapper.credentialOwnership(provider: "claude", result: result),
            CollectorCredentialOwnership(historyOwnerIdentifier: "owner", comparison: .mismatch))
        let mappedUsage = CodexBarResultMapper.usage(
            usage,
            metadata: ProviderDescriptorRegistry.descriptor(for: .commandcode).metadata)
        XCTAssertNotNil(mappedUsage.extensions["codexbar.persisted-usage.v1"])
        XCTAssertNil(mappedUsage.extensions["codexbar.usage.v1"])
    }

    func testClaudeCredentialMatchPreservesStateWithoutPersistingEvidence() {
        let result = ProviderFetchResult(
            usage: UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            credits: nil,
            dashboard: nil,
            sourceLabel: "oauth",
            strategyID: "claude.oauth",
            strategyKind: .oauth,
            claudeOAuthKeychainPersistentRefHash: "transient",
            claudeOAuthHistoryOwnerIdentifier: "owner")

        XCTAssertEqual(
            CodexBarArtifactMapper.credentialOwnership(provider: "claude", result: result),
            CollectorCredentialOwnership(historyOwnerIdentifier: "owner", comparison: .matched))
        XCTAssertEqual(
            CodexBarArtifactMapper.diagnostics(result).map(\.code),
            ["transient_credential_evidence_omitted"])
    }

    func testClaudeCredentialComparisonCanBeNotApplicable() {
        let result = ProviderFetchResult(
            usage: UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            credits: nil,
            dashboard: nil,
            sourceLabel: "cli",
            strategyID: "claude.cli",
            strategyKind: .cli)

        XCTAssertEqual(
            CodexBarArtifactMapper.credentialOwnership(provider: "claude", result: result),
            CollectorCredentialOwnership(
                historyOwnerIdentifier: nil,
                comparison: .notApplicable))
    }

    func testUnknownCreditBalanceRemainsUnknown() {
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let limit = CodexCreditLimitSnapshot(
            used: 10,
            limit: 100,
            remainingPercent: 90,
            resetsAt: nil,
            updatedAt: observedAt)
        let credits = CreditsSnapshot(
            remaining: 0,
            events: [],
            updatedAt: observedAt,
            codexCreditLimit: limit)

        let unknown = CodexBarResultMapper.credits(credits, dashboard: nil)
        let knownZero = CodexBarResultMapper.credits(
            credits,
            dashboard: self.dashboard(at: observedAt, creditsRemaining: 0))

        XCTAssertNil(unknown?.remaining)
        XCTAssertEqual(knownZero?.remaining, 0)
    }

    func testCancellationBeforeCollectionDoesNotResolveStrategies() async {
        let recorder = CallRecorder()
        let descriptor = self.stubDescriptor(strategies: [], recorder: recorder)
        let collector = CodexBarCollector(
            configuration: CollectorConfiguration(),
            policy: self.policy(planningAllowed: true, strategyIDs: []),
            host: .disabled,
            descriptorFor: { _ in descriptor })
        let request = self.request()

        let outcome = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await collector.collect(request)
        }.value
        let calls = await recorder.values()

        XCTAssertEqual(outcome.failure?.code, "cancelled")
        XCTAssertEqual(calls, [])
    }

    private func request(
        account: CollectorAccountSelection = .ambient) -> CollectorRequest
    {
        CollectorRequest(
            provider: "openrouter",
            account: account,
            source: .api,
            includeCredits: false,
            includeOptionalUsage: false,
            interaction: .userInitiated)
    }

    private func policy(
        account: CollectorAccountScope = .ambient,
        planningAllowed: Bool,
        strategyIDs: [String]) -> StaticCollectorSourcePolicy
    {
        StaticCollectorSourcePolicy(
            allowedCapabilities: Set(CollectorCapability.allCases),
            requestRules: [
                CollectorRequestRule(
                    id: "request",
                    provider: "openrouter",
                    account: account,
                    source: .api,
                    runtime: .app,
                    includeCredits: false,
                    includeOptionalUsage: false,
                    interaction: .userInitiated,
                    allow: true,
                    reason: "test"),
            ],
            planningRules: planningAllowed ? [
                CollectorPlanningRule(
                    id: "planning",
                    provider: "openrouter",
                    account: account,
                    source: .api,
                    runtime: .app,
                    includeCredits: false,
                    includeOptionalUsage: false,
                    interaction: .userInitiated,
                    allow: true,
                    reason: "test"),
            ] : [],
            strategyRules: strategyIDs.map {
                CollectorStrategyRule(
                    id: "strategy-\($0)",
                    provider: "openrouter",
                    account: account,
                    source: .api,
                    runtime: .app,
                    includeCredits: false,
                    includeOptionalUsage: false,
                    interaction: .userInitiated,
                    strategyID: $0,
                    kind: .apiToken,
                    allow: true,
                    reason: "test")
            })
    }

    private func stubDescriptor(
        strategies: [any ProviderFetchStrategy],
        recorder: CallRecorder) -> ProviderDescriptor
    {
        let base = ProviderDescriptorRegistry.descriptor(for: .openrouter)
        return ProviderDescriptor(
            id: base.id,
            metadata: base.metadata,
            branding: base.branding,
            tokenCost: base.tokenCost,
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.api],
                pipeline: ProviderFetchPipeline { _ in
                    await recorder.append("resolve")
                    return strategies
                }),
            cli: base.cli)
    }

    private func fetchResult(
        strategyID: String,
        diagnostic: String? = nil,
        identity: ProviderIdentitySnapshot? = nil) -> ProviderFetchResult
    {
        ProviderFetchResult(
            usage: UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 25,
                    windowMinutes: 300,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                identity: identity),
            credits: nil,
            dashboard: nil,
            sourceLabel: "Stub",
            strategyID: strategyID,
            strategyKind: .apiToken,
            diagnostic: diagnostic)
    }

    private func dashboard(
        at observedAt: Date,
        creditsRemaining: Double?,
        signedInEmail: String? = "user@example.com") -> OpenAIDashboardSnapshot
    {
        OpenAIDashboardSnapshot(
            signedInEmail: signedInEmail,
            codeReviewRemainingPercent: nil,
            creditEvents: [],
            dailyBreakdown: [],
            usageBreakdown: [],
            creditsPurchaseURL: nil,
            creditsRemaining: creditsRemaining,
            updatedAt: observedAt)
    }

    private func selectedAccountHost(
        accountID: UUID,
        expectedEmail: String) -> CodexBarHostConfiguration
    {
        CodexBarHostConfiguration(accountResolver: { _, _ in
            CodexBarResolvedAccountContext(
                confirmedAccountID: accountID,
                environment: [:],
                identityExpectation: CodexBarAccountIdentityExpectation(
                    provider: "openrouter",
                    accountEmail: expectedEmail))
        })
    }
}

private enum StubError: Error {
    case failed
}

private actor CallRecorder {
    private var entries: [String] = []

    func append(_ value: String) {
        self.entries.append(value)
    }

    func values() -> [String] {
        self.entries
    }
}

private struct StubStrategy: ProviderFetchStrategy {
    let id: String
    let kind: ProviderFetchKind
    let recorder: CallRecorder
    let available: Bool
    let result: ProviderFetchResult?
    let error: (any Error)?
    let fallbackAllowed: Bool

    init(
        id: String,
        kind: ProviderFetchKind,
        recorder: CallRecorder,
        available: Bool,
        result: ProviderFetchResult? = nil,
        error: (any Error)? = nil,
        fallbackAllowed: Bool)
    {
        self.id = id
        self.kind = kind
        self.recorder = recorder
        self.available = available
        self.result = result
        self.error = error
        self.fallbackAllowed = fallbackAllowed
    }

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        await self.recorder.append("available:\(self.id)")
        return self.available
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        await self.recorder.append("fetch:\(self.id)")
        if let error {
            throw error
        }
        return self.result!
    }

    func shouldFallback(on error: any Error, context: ProviderFetchContext) -> Bool {
        self.fallbackAllowed
    }
}

private struct ContextCheckingStrategy: ProviderFetchStrategy {
    let id: String
    let kind: ProviderFetchKind = .apiToken
    let recorder: CallRecorder
    let expectedEnvironment: [String: String]
    let expectedAccountID: UUID
    let expectsSettingsNil: Bool
    let result: ProviderFetchResult

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        await self.recorder.append("available:\(self.id)")
        return context.env == self.expectedEnvironment
            && context.selectedTokenAccountID == self.expectedAccountID
            && (!self.expectsSettingsNil || context.settings == nil)
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        await self.recorder.append("fetch:\(self.id)")
        return self.result
    }

    func shouldFallback(on error: any Error, context: ProviderFetchContext) -> Bool {
        false
    }
}
