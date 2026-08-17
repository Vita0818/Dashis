import CodexBarCore
import DashisCollectorContract
import Foundation

enum CodexBarResultMapper {
    static func usage(
        _ snapshot: UsageSnapshot,
        metadata: ProviderMetadata) -> CollectorUsage
    {
        var windows: [CollectorWindow] = []
        if let primary = snapshot.primary {
            windows.append(self.window(
                primary,
                role: .primary,
                id: "primary",
                title: metadata.sessionLabel,
                usageKnown: true))
        }
        if let secondary = snapshot.secondary {
            windows.append(self.window(
                secondary,
                role: .secondary,
                id: "secondary",
                title: metadata.weeklyLabel,
                usageKnown: true))
        }
        if let tertiary = snapshot.tertiary {
            windows.append(self.window(
                tertiary,
                role: .tertiary,
                id: "tertiary",
                title: metadata.opusLabel,
                usageKnown: true))
        }
        for named in snapshot.extraRateWindows ?? [] {
            windows.append(self.window(
                named.window,
                role: .extra,
                id: named.id,
                title: named.title,
                usageKnown: named.usageKnown))
        }

        let identity = self.identity(snapshot.identity)
        let cost = snapshot.providerCost.map {
            CollectorCost(
                used: $0.used,
                limit: $0.limit,
                currencyCode: $0.currencyCode,
                period: $0.period,
                resetsAt: $0.resetsAt,
                nextRegenAmount: $0.nextRegenAmount,
                personalUsed: $0.personalUsed,
                observedAt: $0.updatedAt)
        }

        return CollectorUsage(
            observedAt: snapshot.updatedAt,
            confidence: self.confidence(snapshot.dataConfidence),
            identity: identity,
            windows: windows,
            cost: cost,
            subscriptionExpiresAt: snapshot.subscriptionExpiresAt,
            subscriptionRenewsAt: snapshot.subscriptionRenewsAt,
            extensions: self.extensions(snapshot))
    }

    static func identity(_ snapshot: ProviderIdentitySnapshot?) -> CollectorIdentity? {
        snapshot.map {
            CollectorIdentity(
                providerID: $0.providerID.map(CodexBarTypeMapping.provider),
                accountEmail: $0.accountEmail,
                accountOrganization: $0.accountOrganization,
                loginMethod: $0.loginMethod,
                accountID: $0.accountID)
        }
    }

    static func credits(
        _ snapshot: CreditsSnapshot?,
        dashboard: OpenAIDashboardSnapshot?) -> CollectorCredits?
    {
        guard let snapshot else { return nil }
        let limit = snapshot.codexCreditLimit.map {
            CollectorCreditLimit(
                title: $0.title,
                used: $0.used,
                limit: $0.limit,
                remaining: $0.remaining,
                remainingPercent: $0.remainingPercent,
                resetsAt: $0.resetsAt,
                observedAt: $0.updatedAt)
        }
        let remaining: Double? = if let dashboard {
            dashboard.creditsRemaining
        } else if snapshot.codexCreditLimit != nil,
                  snapshot.remaining == 0,
                  snapshot.events.isEmpty
        {
            nil
        } else {
            snapshot.remaining
        }
        return CollectorCredits(
            remaining: remaining,
            events: snapshot.events.map {
                CollectorCreditEvent(
                    id: $0.id,
                    date: $0.date,
                    service: $0.service,
                    creditsUsed: $0.creditsUsed)
            },
            observedAt: snapshot.updatedAt,
            limit: limit)
    }

    private static func window(
        _ window: RateWindow,
        role: CollectorWindowRole,
        id: String,
        title: String?,
        usageKnown: Bool) -> CollectorWindow
    {
        CollectorWindow(
            role: role,
            id: id,
            title: title,
            usedPercent: window.usedPercent,
            remainingPercent: 100 - window.usedPercent,
            windowMinutes: window.windowMinutes,
            resetsAt: window.resetsAt,
            resetDescription: window.resetDescription,
            nextRegenPercent: window.nextRegenPercent,
            isSyntheticPlaceholder: window.isSyntheticPlaceholder,
            usageKnown: usageKnown)
    }

    private static func confidence(_ confidence: UsageDataConfidence) -> CollectorDataConfidence {
        switch confidence {
        case .exact: .exact
        case .estimated: .estimated
        case .percentOnly: .percentOnly
        case .unknown: .unknown
        }
    }

    private static func extensions(_ snapshot: UsageSnapshot) -> [String: CollectorValue] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot),
              let value = try? JSONDecoder().decode(CollectorValue.self, from: data)
        else {
            return [:]
        }
        return ["codexbar.persisted-usage.v1": value]
    }
}
