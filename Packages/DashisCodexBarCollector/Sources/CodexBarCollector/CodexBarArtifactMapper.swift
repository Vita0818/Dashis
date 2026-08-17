import CodexBarCore
import DashisCollectorContract
import Foundation

enum CodexBarArtifactMapper {
    static func artifacts(
        provider: CollectorProviderID,
        result: ProviderFetchResult) -> [CollectorProviderArtifact]
    {
        let snapshot = result.usage
        var artifacts: [CollectorProviderArtifact] = []

        if let value = snapshot.zaiUsage {
            artifacts.append(self.artifact(
                "codexbar.live.zai.v1",
                at: value.updatedAt,
                payload: self.zai(value)))
        }
        if let value = snapshot.minimaxUsage {
            artifacts.append(self.artifact(
                "codexbar.live.minimax.v1",
                at: value.updatedAt,
                payload: self.minimax(value)))
        }
        if snapshot.deepseekUsage != nil
            || snapshot.deepseekDetailedUsageState != .notRequested
            || !snapshot.deepseekPlatformProfiles.isEmpty
        {
            artifacts.append(self.artifact(
                "codexbar.live.deepseek.v1",
                at: snapshot.deepseekUsage?.updatedAt ?? snapshot.updatedAt,
                payload: self.deepseek(snapshot)))
        }
        if let value = snapshot.opencodegoUsage {
            artifacts.append(self.artifact(
                "codexbar.live.opencodego.v1",
                at: value.updatedAt,
                payload: self.openCodeGo(value)))
        }
        if let value = snapshot.cursorRequests {
            artifacts.append(self.artifact(
                "codexbar.live.cursor-requests.v1",
                at: snapshot.updatedAt,
                payload: .object([
                    "used": self.int(value.used),
                    "limit": self.int(value.limit),
                ])))
        }
        if provider.rawValue == "commandcode"
            || snapshot.commandCodeSubscriptionEnrichmentUnavailable
            || snapshot.commandCodeHasSubscriptionPlan
            || snapshot.commandCodeMonthlyGrantDepleted
        {
            artifacts.append(self.artifact(
                "codexbar.live.commandcode.v1",
                at: snapshot.updatedAt,
                payload: .object([
                    "subscriptionEnrichmentUnavailable":
                        .bool(snapshot.commandCodeSubscriptionEnrichmentUnavailable),
                    "hasSubscriptionPlan":
                        .bool(snapshot.commandCodeHasSubscriptionPlan),
                    "monthlyGrantDepleted":
                        .bool(snapshot.commandCodeMonthlyGrantDepleted),
                ])))
        }
        if let dashboard = result.dashboard,
           let payload = self.codable(dashboard)
        {
            artifacts.append(self.artifact(
                "codexbar.openai-dashboard.v1",
                at: dashboard.updatedAt,
                payload: payload))
        }

        return artifacts
    }

    static func credentialOwnership(
        provider: CollectorProviderID,
        result: ProviderFetchResult) -> CollectorCredentialOwnership?
    {
        guard provider.rawValue == "claude"
            || result.claudeOAuthHistoryOwnerIdentifier != nil
            || result.claudeOAuthKeychainCredentialMismatch
            || result.claudeOAuthKeychainCredentialAbsent
            || result.claudeOAuthKeychainCredentialUnavailable
        else {
            return nil
        }

        let comparison: CollectorCredentialComparison
        if result.claudeOAuthKeychainCredentialMismatch {
            comparison = .mismatch
        } else if result.claudeOAuthKeychainCredentialAbsent {
            comparison = .absent
        } else if result.claudeOAuthKeychainCredentialUnavailable {
            comparison = .unavailable
        } else if result.claudeOAuthKeychainPersistentRefHash != nil {
            comparison = .matched
        } else if provider.rawValue == "claude" {
            comparison = .notApplicable
        } else {
            comparison = .notObserved
        }
        return CollectorCredentialOwnership(
            historyOwnerIdentifier: result.claudeOAuthHistoryOwnerIdentifier,
            comparison: comparison)
    }

    static func diagnostics(_ result: ProviderFetchResult) -> [CollectorDiagnostic] {
        var diagnostics: [CollectorDiagnostic] = []
        if result.diagnostic != nil {
            diagnostics.append(CollectorDiagnostic(
                code: "upstream_diagnostic_present",
                message: "CodexBar returned a diagnostic alongside usable data; details were suppressed."))
        }
        if result.claudeOAuthKeychainPersistentRefHash != nil {
            diagnostics.append(CollectorDiagnostic(
                code: "transient_credential_evidence_omitted",
                message: "Transient Keychain reference evidence was intentionally not placed in the Codable result."))
        }
        return diagnostics
    }

    private static func artifact(
        _ schemaID: String,
        at observedAt: Date,
        payload: CollectorValue) -> CollectorProviderArtifact
    {
        CollectorProviderArtifact(schemaID: schemaID, observedAt: observedAt, payload: payload)
    }

    private static func zai(_ snapshot: ZaiUsageSnapshot) -> CollectorValue {
        .object([
            "tokenLimit": self.zaiLimit(snapshot.tokenLimit),
            "sessionTokenLimit": self.zaiLimit(snapshot.sessionTokenLimit),
            "timeLimit": self.zaiLimit(snapshot.timeLimit),
            "planName": self.string(snapshot.planName),
            "modelUsage": self.zaiModelUsage(snapshot.modelUsage),
            "updatedAt": self.date(snapshot.updatedAt),
        ])
    }

    private static func zaiLimit(_ limit: ZaiLimitEntry?) -> CollectorValue {
        guard let limit else { return .null }
        return .object([
            "type": .string(limit.type.rawValue),
            "unit": self.int(limit.unit.rawValue),
            "number": self.int(limit.number),
            "usage": self.int(limit.usage),
            "currentValue": self.int(limit.currentValue),
            "remaining": self.int(limit.remaining),
            "percentage": .number(limit.percentage),
            "usageDetails": .array(limit.usageDetails.map {
                .object([
                    "modelCode": .string($0.modelCode),
                    "usage": self.int($0.usage),
                ])
            }),
            "nextResetTime": self.date(limit.nextResetTime),
        ])
    }

    private static func zaiModelUsage(_ value: ZaiModelUsageData?) -> CollectorValue {
        guard let value else { return .null }
        return .object([
            "xTime": .array(value.xTime.map(CollectorValue.string)),
            "modelDataList": .array(value.modelDataList.map { item in
                .object([
                    "modelName": self.string(item.modelName),
                    "tokensUsage": .array(item.tokensUsage.map { self.int($0) }),
                ])
            }),
        ])
    }

    private static func minimax(_ snapshot: MiniMaxUsageSnapshot) -> CollectorValue {
        .object([
            "planName": self.string(snapshot.planName),
            "availablePrompts": self.int(snapshot.availablePrompts),
            "currentPrompts": self.int(snapshot.currentPrompts),
            "remainingPrompts": self.int(snapshot.remainingPrompts),
            "windowMinutes": self.int(snapshot.windowMinutes),
            "usedPercent": self.number(snapshot.usedPercent),
            "resetsAt": self.date(snapshot.resetsAt),
            "updatedAt": self.date(snapshot.updatedAt),
            "services": snapshot.services.map {
                .array($0.map(self.minimaxService))
            } ?? .null,
            "billingSummary": snapshot.billingSummary.map(self.minimaxBilling) ?? .null,
            "pointsBalance": self.number(snapshot.pointsBalance),
            "subscriptionExpiresAt": self.date(snapshot.subscriptionExpiresAt),
            "subscriptionRenewsAt": self.date(snapshot.subscriptionRenewsAt),
        ])
    }

    private static func minimaxService(_ value: MiniMaxServiceUsage) -> CollectorValue {
        .object([
            "serviceType": .string(value.serviceType),
            "windowType": .string(value.windowType),
            "timeRange": .string(value.timeRange),
            "usage": self.int(value.usage),
            "limit": self.int(value.limit),
            "percent": .number(value.percent),
            "isUnlimited": .bool(value.isUnlimited),
            "resetsAt": self.date(value.resetsAt),
            "resetDescription": .string(value.resetDescription),
        ])
    }

    private static func minimaxBilling(_ value: MiniMaxBillingSummary) -> CollectorValue {
        .object([
            "todayTokens": self.int(value.todayTokens),
            "last30DaysTokens": self.int(value.last30DaysTokens),
            "todayCash": self.number(value.todayCash),
            "last30DaysCash": self.number(value.last30DaysCash),
            "daily": .array(value.daily.map {
                .object([
                    "day": .string($0.day),
                    "tokens": self.int($0.tokens),
                    "cash": self.number($0.cash),
                ])
            }),
            "topMethods": .array(value.topMethods.map(self.minimaxBreakdown)),
            "topModels": .array(value.topModels.map(self.minimaxBreakdown)),
            "updatedAt": self.date(value.updatedAt),
        ])
    }

    private static func minimaxBreakdown(_ value: MiniMaxBillingBreakdown) -> CollectorValue {
        .object([
            "name": .string(value.name),
            "tokens": self.int(value.tokens),
            "cash": self.number(value.cash),
        ])
    }

    private static func deepseek(_ snapshot: UsageSnapshot) -> CollectorValue {
        .object([
            "usage": snapshot.deepseekUsage.map(self.deepseekSummary) ?? .null,
            "detailedUsageState": .string(self.deepseekState(snapshot.deepseekDetailedUsageState)),
            "platformProfiles": .array(snapshot.deepseekPlatformProfiles.map {
                .object([
                    "id": .string($0.id),
                    "name": .string($0.name),
                ])
            }),
        ])
    }

    private static func deepseekSummary(_ value: DeepSeekUsageSummary) -> CollectorValue {
        .object([
            "todayTokens": self.int(value.todayTokens),
            "currentMonthTokens": self.int(value.currentMonthTokens),
            "todayCost": self.number(value.todayCost),
            "currentMonthCost": self.number(value.currentMonthCost),
            "requestCount": self.int(value.requestCount),
            "currentMonthRequestCount": self.int(value.currentMonthRequestCount),
            "topModel": self.string(value.topModel),
            "categoryBreakdown": .array(value.categoryBreakdown.map {
                .object([
                    "category": .string($0.category.rawValue),
                    "tokens": self.int($0.tokens),
                    "cost": self.number($0.cost),
                ])
            }),
            "daily": .array(value.daily.map {
                .object([
                    "date": .string($0.date),
                    "totalTokens": self.int($0.totalTokens),
                    "cost": self.number($0.cost),
                    "requestCount": self.int($0.requestCount),
                ])
            }),
            "currency": .string(value.currency),
            "updatedAt": self.date(value.updatedAt),
        ])
    }

    private static func deepseekState(_ value: DeepSeekDetailedUsageState) -> String {
        switch value {
        case .notRequested: "notRequested"
        case .available: "available"
        case .webSessionRequired: "webSessionRequired"
        case .profileSelectionRequired: "profileSelectionRequired"
        case .unavailable: "unavailable"
        }
    }

    private static func openCodeGo(_ value: OpenCodeGoUsageSnapshot) -> CollectorValue {
        .object([
            "isBalanceOnly": .bool(value.isBalanceOnly),
            "hasWeeklyUsage": .bool(value.hasWeeklyUsage),
            "hasMonthlyUsage": .bool(value.hasMonthlyUsage),
            "rollingUsagePercent": .number(value.rollingUsagePercent),
            "weeklyUsagePercent": .number(value.weeklyUsagePercent),
            "monthlyUsagePercent": .number(value.monthlyUsagePercent),
            "rollingResetInSec": self.int(value.rollingResetInSec),
            "weeklyResetInSec": self.int(value.weeklyResetInSec),
            "monthlyResetInSec": self.int(value.monthlyResetInSec),
            "zenBalanceUSD": self.number(value.zenBalanceUSD),
            "renewsAt": self.date(value.renewsAt),
            "daily": .array(value.daily.map(self.costDailyEntry)),
            "updatedAt": self.date(value.updatedAt),
        ])
    }

    private static func costDailyEntry(_ value: CostUsageDailyReport.Entry) -> CollectorValue {
        .object([
            "date": .string(value.date),
            "inputTokens": self.int(value.inputTokens),
            "cacheReadTokens": self.int(value.cacheReadTokens),
            "cacheCreationTokens": self.int(value.cacheCreationTokens),
            "outputTokens": self.int(value.outputTokens),
            "totalTokens": self.int(value.totalTokens),
            "requestCount": self.int(value.requestCount),
            "costUSD": self.number(value.costUSD),
            "modelsUsed": value.modelsUsed.map {
                .array($0.map(CollectorValue.string))
            } ?? .null,
            "modelBreakdowns": value.modelBreakdowns.map {
                .array($0.map(self.costModelBreakdown))
            } ?? .null,
        ])
    }

    private static func costModelBreakdown(
        _ value: CostUsageDailyReport.ModelBreakdown) -> CollectorValue
    {
        .object([
            "modelName": .string(value.modelName),
            "costUSD": self.number(value.costUSD),
            "totalTokens": self.int(value.totalTokens),
            "requestCount": self.int(value.requestCount),
            "standardCostUSD": self.number(value.standardCostUSD),
            "priorityCostUSD": self.number(value.priorityCostUSD),
            "standardTokens": self.int(value.standardTokens),
            "priorityTokens": self.int(value.priorityTokens),
        ])
    }

    private static func codable<T: Encodable>(_ value: T) -> CollectorValue? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return nil }
        return try? JSONDecoder().decode(CollectorValue.self, from: data)
    }

    private static func int(_ value: Int) -> CollectorValue {
        .integer(Int64(value))
    }

    private static func int(_ value: Int?) -> CollectorValue {
        value.map { .integer(Int64($0)) } ?? .null
    }

    private static func number(_ value: Double?) -> CollectorValue {
        value.map(CollectorValue.number) ?? .null
    }

    private static func string(_ value: String?) -> CollectorValue {
        value.map(CollectorValue.string) ?? .null
    }

    private static func date(_ value: Date?) -> CollectorValue {
        guard let value else { return .null }
        return .string(ISO8601DateFormatter().string(from: value))
    }

    private static func date(_ value: Date) -> CollectorValue {
        .string(ISO8601DateFormatter().string(from: value))
    }
}
