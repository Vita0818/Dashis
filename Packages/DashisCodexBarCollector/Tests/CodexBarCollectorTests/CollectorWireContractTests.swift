import DashisCollectorContract
import Foundation
import XCTest

final class CollectorWireContractTests: XCTestCase {
    func testCollectRequestRoundTripsWithStableWireVersion() throws {
        let requestID = UUID()
        let request = CollectorWireRequest.collect(
            CollectorRequest(
                provider: "openrouter",
                source: .api,
                interaction: .userInitiated),
            authorization: CollectorRouteAuthorization(
                routeID: "test.openrouter",
                expectedStrategyID: "openrouter.api",
                expectedStrategyKind: .apiToken,
                manifestDigest: String(repeating: "a", count: 64),
                upstreamPin: CollectorWireIdentity.codexBarUpstreamPin),
            requestID: requestID,
            budgetMilliseconds: 5_000)

        let encoded = try CollectorWireCodec.encodeRequest(request)
        let decoded = try CollectorWireCodec.decodeRequest(encoded)

        XCTAssertEqual(decoded, request)
        XCTAssertEqual(decoded.wireVersion, 4)
        XCTAssertLessThan(encoded.count, CollectorWireLimits.maximumRequestBytes)
    }

    func testReleaseWireRejectsAutomaticSource() {
        let request = CollectorWireRequest.collect(
            CollectorRequest(provider: "codex", source: .auto),
            authorization: self.authorization(),
            budgetMilliseconds: 5_000)

        XCTAssertThrowsError(try CollectorWireCodec.encodeRequest(request)) { error in
            XCTAssertEqual(
                error as? CollectorWireCodecError,
                .invalidEnvelope(
                    "release collection requests must use an explicit source"))
        }
    }

    func testCollectRequiresExactPinnedAuthorization() {
        let missing = CollectorWireRequest(
            operation: .collect,
            budgetMilliseconds: 5_000,
            collectorRequest: CollectorRequest(
                provider: "openrouter",
                source: .api))
        XCTAssertThrowsError(try CollectorWireCodec.encodeRequest(missing)) { error in
            XCTAssertEqual(
                error as? CollectorWireCodecError,
                .invalidEnvelope("collect requires an exact route authorization"))
        }

        let unicodeDigitDigest = String(repeating: "１", count: 64)
        let invalidDigest = CollectorWireRequest.collect(
            CollectorRequest(provider: "openrouter", source: .api),
            authorization: CollectorRouteAuthorization(
                routeID: "test.openrouter",
                expectedStrategyID: "openrouter.api",
                expectedStrategyKind: .apiToken,
                manifestDigest: unicodeDigitDigest,
                upstreamPin: CollectorWireIdentity.codexBarUpstreamPin),
            budgetMilliseconds: 5_000)
        XCTAssertThrowsError(try CollectorWireCodec.encodeRequest(invalidDigest)) { error in
            XCTAssertEqual(
                error as? CollectorWireCodecError,
                .invalidEnvelope(
                    "route authorization is not an exact pinned manifest identity"))
        }
    }

    func testReplyRequiresOneStatusCompatiblePayload() {
        let requestID = UUID()
        let handshake = CollectorWorkerHandshake(
            wireVersion: CollectorWireRequest.currentWireVersion,
            outcomeSchemaVersion: CollectorOutcome.currentSchemaVersion,
            workerBundleIdentifier: DashisCollectorXPC.serviceName,
            workerBundleVersion: "1",
            maximumRequestBytes: CollectorWireLimits.maximumRequestBytes,
            maximumResponseBytes: CollectorWireLimits.maximumResponseBytes,
            upstreamPin: CollectorWireIdentity.codexBarUpstreamPin,
            rolloutCatalogRevision: CollectorRolloutCatalog.revision,
            stagedProviderCount: CollectorRolloutCatalog.selectedProviderIDs.count,
            stagedStrategyCount: CollectorRolloutCatalog.strategies.count,
            stagedBindingCount: CollectorRolloutCatalog.bindings.count,
            liveRouteCount: CollectorLiveRouteCatalog.routes.count,
            liveCatalogRevision: CollectorLiveRouteCatalog.revision,
            liveManifestSetDigest: String(repeating: "a", count: 64))
        let multiplePayloads = CollectorWireReply(
            requestID: requestID,
            status: .success,
            handshake: handshake,
            catalog: [])
        XCTAssertThrowsError(
            try CollectorWireCodec.encodeReply(multiplePayloads)) { error in
                XCTAssertEqual(
                    error as? CollectorWireCodecError,
                    .invalidEnvelope("reply must carry exactly one payload"))
            }

        let successWithFailure = CollectorWireReply(
            requestID: requestID,
            status: .success,
            failure: CollectorWireFailure(code: "invalid", message: "invalid"))
        XCTAssertThrowsError(
            try CollectorWireCodec.encodeReply(successWithFailure)) { error in
                XCTAssertEqual(
                    error as? CollectorWireCodecError,
                    .invalidEnvelope(
                        "successful reply cannot carry a failure payload"))
            }
    }

    func testHandshakeRejectsRolloutCatalogMismatch() {
        let handshake = CollectorWorkerHandshake(
            wireVersion: CollectorWireRequest.currentWireVersion,
            outcomeSchemaVersion: CollectorOutcome.currentSchemaVersion,
            workerBundleIdentifier: DashisCollectorXPC.serviceName,
            workerBundleVersion: "1",
            maximumRequestBytes: CollectorWireLimits.maximumRequestBytes,
            maximumResponseBytes: CollectorWireLimits.maximumResponseBytes,
            upstreamPin: CollectorWireIdentity.codexBarUpstreamPin,
            rolloutCatalogRevision: "stale-catalog",
            stagedProviderCount: CollectorRolloutCatalog.selectedProviderIDs.count,
            stagedStrategyCount: CollectorRolloutCatalog.strategies.count,
            stagedBindingCount: CollectorRolloutCatalog.bindings.count,
            liveRouteCount: CollectorLiveRouteCatalog.routes.count,
            liveCatalogRevision: CollectorLiveRouteCatalog.revision,
            liveManifestSetDigest: String(repeating: "a", count: 64))
        let reply = CollectorWireReply(
            requestID: UUID(),
            status: .success,
            handshake: handshake)

        XCTAssertThrowsError(try CollectorWireCodec.encodeReply(reply)) { error in
            XCTAssertEqual(
                error as? CollectorWireCodecError,
                .invalidEnvelope("reply carries an incompatible worker handshake"))
        }
    }

    func testReplyCapRejectsOversizedPayloadInsteadOfTruncating() {
        let reply = CollectorWireReply(
            requestID: UUID(),
            status: .internalFailure,
            failure: CollectorWireFailure(
                code: "oversized",
                message: String(
                    repeating: "x",
                    count: CollectorWireLimits.maximumResponseBytes + 1)))

        XCTAssertThrowsError(try CollectorWireCodec.encodeReply(reply)) { error in
            guard case .responseTooLarge = error as? CollectorWireCodecError else {
                return XCTFail("Expected responseTooLarge, got \(error)")
            }
        }
    }

    func testHostBrokerCodecRoundTripsBoundedAllowlistedEnvironment() throws {
        let request = CollectorHostBrokerRequest(
            requestID: UUID(),
            leaseID: UUID(),
            routeID: "collector.live.openai.api.openai.api.balance",
            provider: "openai",
            requestedKeys: ["OPENAI_ADMIN_KEY", "OPENAI_PROJECT_ID"])
        XCTAssertEqual(
            try CollectorHostBrokerCodec.decodeRequest(
                CollectorHostBrokerCodec.encodeRequest(request)),
            request)

        let reply = CollectorHostBrokerReply(environment: [
            "OPENAI_ADMIN_KEY": "session-only-test-value",
        ])
        XCTAssertEqual(
            try CollectorHostBrokerCodec.decodeReply(
                CollectorHostBrokerCodec.encodeReply(reply)),
            reply)
        XCTAssertThrowsError(try CollectorHostBrokerCodec.encodeReply(
            CollectorHostBrokerReply(environment: [
                "not-an-env-key": "value",
            ])))
        XCTAssertThrowsError(try CollectorHostBrokerCodec.encodeReply(
            CollectorHostBrokerReply(environment: [
                "OPENAI_API_KEY": "prefix\u{0000}suffix",
            ])))
    }

    private func authorization() -> CollectorRouteAuthorization {
        CollectorRouteAuthorization(
            routeID: "test.codex",
            expectedStrategyID: "codex.oauth",
            expectedStrategyKind: .oauth,
            manifestDigest: String(repeating: "a", count: 64),
            upstreamPin: CollectorWireIdentity.codexBarUpstreamPin)
    }
}
