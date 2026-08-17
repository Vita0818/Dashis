import Foundation

public enum CollectorWireLimits {
    public static let maximumRequestBytes = 256 * 1024
    public static let maximumResponseBytes = 2 * 1024 * 1024
    public static let minimumBudgetMilliseconds = 1
    public static let maximumBudgetMilliseconds = 120_000
}

public enum CollectorWireCodecError: Error, Equatable, LocalizedError {
    case requestTooLarge(Int)
    case responseTooLarge(Int)
    case unsupportedWireVersion(Int)
    case invalidBudget(Int)
    case invalidEnvelope(String)
    case encodingFailed
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case let .requestTooLarge(size):
            "Collector request exceeded the \(CollectorWireLimits.maximumRequestBytes)-byte limit (\(size) bytes)."
        case let .responseTooLarge(size):
            "Collector response exceeded the \(CollectorWireLimits.maximumResponseBytes)-byte limit (\(size) bytes)."
        case let .unsupportedWireVersion(version):
            "Collector wire version \(version) is unsupported."
        case let .invalidBudget(milliseconds):
            "Collector budget \(milliseconds) ms is outside the supported range."
        case let .invalidEnvelope(reason):
            "Collector wire envelope is invalid: \(reason)."
        case .encodingFailed:
            "Collector wire encoding failed."
        case .decodingFailed:
            "Collector wire decoding failed."
        }
    }
}

public enum CollectorWireCodec {
    public static func encodeRequest(_ request: CollectorWireRequest) throws -> Data {
        try self.validate(request)
        let data: Data
        do {
            data = try self.encoder().encode(request)
        } catch {
            throw CollectorWireCodecError.encodingFailed
        }
        guard data.count <= CollectorWireLimits.maximumRequestBytes else {
            throw CollectorWireCodecError.requestTooLarge(data.count)
        }
        return data
    }

    public static func decodeRequest(_ data: Data) throws -> CollectorWireRequest {
        guard data.count <= CollectorWireLimits.maximumRequestBytes else {
            throw CollectorWireCodecError.requestTooLarge(data.count)
        }
        let request: CollectorWireRequest
        do {
            request = try self.decoder().decode(CollectorWireRequest.self, from: data)
        } catch {
            throw CollectorWireCodecError.decodingFailed
        }
        try self.validate(request)
        return request
    }

    public static func encodeReply(_ reply: CollectorWireReply) throws -> Data {
        try self.validate(reply)
        let data: Data
        do {
            data = try self.encoder().encode(reply)
        } catch {
            throw CollectorWireCodecError.encodingFailed
        }
        guard data.count <= CollectorWireLimits.maximumResponseBytes else {
            throw CollectorWireCodecError.responseTooLarge(data.count)
        }
        return data
    }

    public static func decodeReply(_ data: Data) throws -> CollectorWireReply {
        guard data.count <= CollectorWireLimits.maximumResponseBytes else {
            throw CollectorWireCodecError.responseTooLarge(data.count)
        }
        let reply: CollectorWireReply
        do {
            reply = try self.decoder().decode(CollectorWireReply.self, from: data)
        } catch {
            throw CollectorWireCodecError.decodingFailed
        }
        try self.validate(reply)
        return reply
    }

    private static func validate(_ request: CollectorWireRequest) throws {
        guard request.wireVersion == CollectorWireRequest.currentWireVersion else {
            throw CollectorWireCodecError.unsupportedWireVersion(request.wireVersion)
        }
        guard (CollectorWireLimits.minimumBudgetMilliseconds...CollectorWireLimits.maximumBudgetMilliseconds)
            .contains(request.budgetMilliseconds)
        else {
            throw CollectorWireCodecError.invalidBudget(request.budgetMilliseconds)
        }

        switch request.operation {
        case .handshake, .catalog:
            guard request.collectorRequest == nil,
                  request.authorization == nil,
                  request.cancellationRequestID == nil
            else {
                throw CollectorWireCodecError.invalidEnvelope(
                    "\(request.operation.rawValue) cannot carry collection fields")
            }
        case .collect:
            guard let collectorRequest = request.collectorRequest else {
                throw CollectorWireCodecError.invalidEnvelope("collect requires a CollectorRequest")
            }
            guard request.authorization != nil else {
                throw CollectorWireCodecError.invalidEnvelope(
                    "collect requires an exact route authorization")
            }
            guard collectorRequest.source != .auto else {
                throw CollectorWireCodecError.invalidEnvelope(
                    "release collection requests must use an explicit source")
            }
            guard self.isBoundedStableID(collectorRequest.provider.rawValue),
                  collectorRequest.account.id != nil
                    || collectorRequest.account.label == nil,
                  collectorRequest.account.label.map(self.isBoundedStableID) ?? true
            else {
                throw CollectorWireCodecError.invalidEnvelope(
                    "collector request contains an invalid provider or account identity")
            }
            guard request.cancellationRequestID == nil else {
                throw CollectorWireCodecError.invalidEnvelope(
                    "collect cannot carry a cancellation target")
            }
        case .cancel:
            guard request.collectorRequest == nil,
                  request.authorization == nil,
                  request.cancellationRequestID != nil
            else {
                throw CollectorWireCodecError.invalidEnvelope(
                    "cancel requires only a cancellation target")
            }
        }

        if let authorization = request.authorization {
            guard !authorization.routeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !authorization.expectedStrategyID
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  authorization.routeID.utf8.count <= 256,
                  authorization.expectedStrategyID.utf8.count <= 256,
                  self.isLowercaseSHA256(authorization.manifestDigest),
                  authorization.upstreamPin == CollectorWireIdentity.codexBarUpstreamPin,
                  authorization.liveCatalogRevision == CollectorLiveRouteCatalog.revision
            else {
                throw CollectorWireCodecError.invalidEnvelope(
                    "route authorization is not an exact pinned manifest identity")
            }
        }
    }

    private static func validate(_ reply: CollectorWireReply) throws {
        guard reply.wireVersion == CollectorWireRequest.currentWireVersion else {
            throw CollectorWireCodecError.unsupportedWireVersion(reply.wireVersion)
        }
        let payloadCount = [
            reply.handshake != nil,
            reply.catalog != nil,
            reply.outcome != nil,
            reply.failure != nil,
        ].filter(\.self).count
        guard payloadCount == 1 else {
            throw CollectorWireCodecError.invalidEnvelope(
                "reply must carry exactly one payload")
        }

        if let handshake = reply.handshake {
            guard reply.status == .success,
                  handshake.wireVersion == CollectorWireRequest.currentWireVersion,
                  handshake.outcomeSchemaVersion == CollectorOutcome.currentSchemaVersion,
                  !handshake.workerBundleIdentifier.isEmpty,
                  !handshake.workerBundleVersion.isEmpty,
                  handshake.maximumRequestBytes == CollectorWireLimits.maximumRequestBytes,
                  handshake.maximumResponseBytes == CollectorWireLimits.maximumResponseBytes,
                  handshake.upstreamPin == CollectorWireIdentity.codexBarUpstreamPin,
                  handshake.rolloutCatalogRevision == CollectorRolloutCatalog.revision,
                  handshake.stagedProviderCount
                    == CollectorRolloutCatalog.selectedProviderIDs.count,
                  handshake.stagedStrategyCount
                    == CollectorRolloutCatalog.strategies.count,
                  handshake.stagedBindingCount
                    == CollectorRolloutCatalog.bindings.count,
                  handshake.liveRouteCount == CollectorLiveRouteCatalog.routes.count,
                  handshake.liveCatalogRevision == CollectorLiveRouteCatalog.revision,
                  self.isLowercaseSHA256(handshake.liveManifestSetDigest)
            else {
                throw CollectorWireCodecError.invalidEnvelope(
                    "reply carries an incompatible worker handshake")
            }
            return
        }

        if let catalog = reply.catalog {
            guard reply.status == .success,
                  catalog.count == Set(catalog.map(\.id)).count
            else {
                throw CollectorWireCodecError.invalidEnvelope(
                    "reply carries an invalid provider catalog")
            }
            return
        }

        if let outcome = reply.outcome {
            guard outcome.schemaVersion == CollectorOutcome.currentSchemaVersion else {
                throw CollectorWireCodecError.invalidEnvelope(
                    "reply carries an unsupported CollectorOutcome schema")
            }
            switch reply.status {
            case .success:
                guard outcome.failure == nil else {
                    throw CollectorWireCodecError.invalidEnvelope(
                        "successful outcome carries a provider failure")
                }
            case .denied, .cancelled, .internalFailure:
                guard outcome.failure != nil,
                      outcome.usage == nil,
                      outcome.credits == nil,
                      outcome.artifacts.isEmpty
                else {
                    throw CollectorWireCodecError.invalidEnvelope(
                        "failed outcome carries usable provider data")
                }
            case .deadlineExceeded, .busy, .invalidRequest:
                throw CollectorWireCodecError.invalidEnvelope(
                    "transport status cannot carry a CollectorOutcome")
            }
            return
        }

        guard reply.status != .success else {
            throw CollectorWireCodecError.invalidEnvelope(
                "successful reply cannot carry a failure payload")
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { character in
            ("0"..."9").contains(character) || ("a"..."f").contains(character)
        }
    }

    private static func isBoundedStableID(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 1_024
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(
                where: CharacterSet.controlCharacters.contains)
    }
}
