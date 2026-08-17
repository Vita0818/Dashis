import Foundation

public enum CollectorWireIdentity {
    public static let codexBarUpstreamPin =
        "91560ca98e776b96fdf910d4a0423c2f0c07a3b9"
}

public enum CollectorWireOperation: String, Codable, Sendable {
    case handshake
    case catalog
    case collect
    case cancel
}

public enum CollectorWireStatus: String, Codable, Sendable {
    case success
    case denied
    case cancelled
    case deadlineExceeded
    case busy
    case invalidRequest
    case internalFailure
}

public struct CollectorRouteAuthorization: Codable, Equatable, Sendable {
    public let routeID: String
    public let expectedStrategyID: String
    public let expectedStrategyKind: CollectorStrategyKind
    public let manifestDigest: String
    public let upstreamPin: String
    public let liveCatalogRevision: String
    public let brokerLeaseID: UUID
    public let consentGranted: Bool

    public init(
        routeID: String,
        expectedStrategyID: String,
        expectedStrategyKind: CollectorStrategyKind,
        manifestDigest: String,
        upstreamPin: String,
        liveCatalogRevision: String = CollectorLiveRouteCatalog.revision,
        brokerLeaseID: UUID = UUID(),
        consentGranted: Bool = false)
    {
        self.routeID = routeID
        self.expectedStrategyID = expectedStrategyID
        self.expectedStrategyKind = expectedStrategyKind
        self.manifestDigest = manifestDigest
        self.upstreamPin = upstreamPin
        self.liveCatalogRevision = liveCatalogRevision
        self.brokerLeaseID = brokerLeaseID
        self.consentGranted = consentGranted
    }
}

public struct CollectorWireRequest: Codable, Equatable, Sendable {
    public static let currentWireVersion = 4

    public let wireVersion: Int
    public let requestID: UUID
    public let operation: CollectorWireOperation
    public let budgetMilliseconds: Int
    public let collectorRequest: CollectorRequest?
    public let authorization: CollectorRouteAuthorization?
    public let cancellationRequestID: UUID?

    public init(
        wireVersion: Int = CollectorWireRequest.currentWireVersion,
        requestID: UUID = UUID(),
        operation: CollectorWireOperation,
        budgetMilliseconds: Int,
        collectorRequest: CollectorRequest? = nil,
        authorization: CollectorRouteAuthorization? = nil,
        cancellationRequestID: UUID? = nil)
    {
        self.wireVersion = wireVersion
        self.requestID = requestID
        self.operation = operation
        self.budgetMilliseconds = budgetMilliseconds
        self.collectorRequest = collectorRequest
        self.authorization = authorization
        self.cancellationRequestID = cancellationRequestID
    }

    public static func handshake(
        requestID: UUID = UUID(),
        budgetMilliseconds: Int = 5_000) -> CollectorWireRequest
    {
        CollectorWireRequest(
            requestID: requestID,
            operation: .handshake,
            budgetMilliseconds: budgetMilliseconds)
    }

    public static func catalog(
        requestID: UUID = UUID(),
        budgetMilliseconds: Int = 5_000) -> CollectorWireRequest
    {
        CollectorWireRequest(
            requestID: requestID,
            operation: .catalog,
            budgetMilliseconds: budgetMilliseconds)
    }

    public static func collect(
        _ request: CollectorRequest,
        authorization: CollectorRouteAuthorization,
        requestID: UUID = UUID(),
        budgetMilliseconds: Int) -> CollectorWireRequest
    {
        CollectorWireRequest(
            requestID: requestID,
            operation: .collect,
            budgetMilliseconds: budgetMilliseconds,
            collectorRequest: request,
            authorization: authorization)
    }

    public static func cancel(
        _ targetRequestID: UUID,
        requestID: UUID = UUID(),
        budgetMilliseconds: Int = 1_000) -> CollectorWireRequest
    {
        CollectorWireRequest(
            requestID: requestID,
            operation: .cancel,
            budgetMilliseconds: budgetMilliseconds,
            cancellationRequestID: targetRequestID)
    }
}

public struct CollectorWorkerHandshake: Codable, Equatable, Sendable {
    public let wireVersion: Int
    public let outcomeSchemaVersion: Int
    public let workerBundleIdentifier: String
    public let workerBundleVersion: String
    public let maximumRequestBytes: Int
    public let maximumResponseBytes: Int
    public let upstreamPin: String
    public let rolloutCatalogRevision: String
    public let stagedProviderCount: Int
    public let stagedStrategyCount: Int
    public let stagedBindingCount: Int
    public let liveRouteCount: Int
    public let liveCatalogRevision: String
    public let liveManifestSetDigest: String

    public init(
        wireVersion: Int,
        outcomeSchemaVersion: Int,
        workerBundleIdentifier: String,
        workerBundleVersion: String,
        maximumRequestBytes: Int,
        maximumResponseBytes: Int,
        upstreamPin: String,
        rolloutCatalogRevision: String,
        stagedProviderCount: Int,
        stagedStrategyCount: Int,
        stagedBindingCount: Int,
        liveRouteCount: Int,
        liveCatalogRevision: String,
        liveManifestSetDigest: String)
    {
        self.wireVersion = wireVersion
        self.outcomeSchemaVersion = outcomeSchemaVersion
        self.workerBundleIdentifier = workerBundleIdentifier
        self.workerBundleVersion = workerBundleVersion
        self.maximumRequestBytes = maximumRequestBytes
        self.maximumResponseBytes = maximumResponseBytes
        self.upstreamPin = upstreamPin
        self.rolloutCatalogRevision = rolloutCatalogRevision
        self.stagedProviderCount = stagedProviderCount
        self.stagedStrategyCount = stagedStrategyCount
        self.stagedBindingCount = stagedBindingCount
        self.liveRouteCount = liveRouteCount
        self.liveCatalogRevision = liveCatalogRevision
        self.liveManifestSetDigest = liveManifestSetDigest
    }
}

public struct CollectorWireFailure: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct CollectorWireReply: Codable, Equatable, Sendable {
    public let wireVersion: Int
    public let requestID: UUID
    public let status: CollectorWireStatus
    public let handshake: CollectorWorkerHandshake?
    public let catalog: [CollectorProvider]?
    public let outcome: CollectorOutcome?
    public let failure: CollectorWireFailure?

    public init(
        wireVersion: Int = CollectorWireRequest.currentWireVersion,
        requestID: UUID,
        status: CollectorWireStatus,
        handshake: CollectorWorkerHandshake? = nil,
        catalog: [CollectorProvider]? = nil,
        outcome: CollectorOutcome? = nil,
        failure: CollectorWireFailure? = nil)
    {
        self.wireVersion = wireVersion
        self.requestID = requestID
        self.status = status
        self.handshake = handshake
        self.catalog = catalog
        self.outcome = outcome
        self.failure = failure
    }
}
