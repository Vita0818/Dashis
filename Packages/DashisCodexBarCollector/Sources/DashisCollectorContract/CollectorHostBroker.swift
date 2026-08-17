import Foundation

public struct CollectorHostBrokerRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let leaseID: UUID
    public let routeID: String
    public let provider: CollectorProviderID
    public let requestedKeys: [String]

    public init(
        requestID: UUID,
        leaseID: UUID,
        routeID: String,
        provider: CollectorProviderID,
        requestedKeys: [String])
    {
        self.requestID = requestID
        self.leaseID = leaseID
        self.routeID = routeID
        self.provider = provider
        self.requestedKeys = requestedKeys
    }
}

public struct CollectorHostBrokerReply: Codable, Equatable, Sendable {
    public let environment: [String: String]

    public init(environment: [String: String]) {
        self.environment = environment
    }
}

public enum CollectorHostBrokerCodecError: Error, Equatable {
    case payloadTooLarge
    case invalidPayload
    case encodingFailed
    case decodingFailed
}

public enum CollectorHostBrokerCodec {
    public static let maximumPayloadBytes = 65_536
    public static let maximumEntryCount = 32
    public static let maximumValueBytes = 16_384

    public static func encodeRequest(_ request: CollectorHostBrokerRequest) throws -> Data {
        guard validID(request.routeID),
              validID(request.provider.rawValue),
              request.requestedKeys.count <= maximumEntryCount,
              Set(request.requestedKeys).count == request.requestedKeys.count,
              request.requestedKeys.allSatisfy(validKey)
        else {
            throw CollectorHostBrokerCodecError.invalidPayload
        }
        return try encode(request)
    }

    public static func decodeRequest(_ data: Data) throws -> CollectorHostBrokerRequest {
        let request: CollectorHostBrokerRequest = try decode(data)
        _ = try encodeRequest(request)
        return request
    }

    public static func encodeReply(_ reply: CollectorHostBrokerReply) throws -> Data {
        guard reply.environment.count <= maximumEntryCount,
              reply.environment.keys.allSatisfy(validKey),
              reply.environment.values.allSatisfy({
                  $0.utf8.count <= maximumValueBytes
                      && !$0.unicodeScalars.contains(where: { $0.value == 0 })
              })
        else {
            throw CollectorHostBrokerCodecError.invalidPayload
        }
        return try encode(reply)
    }

    public static func decodeReply(_ data: Data) throws -> CollectorHostBrokerReply {
        let reply: CollectorHostBrokerReply = try decode(data)
        _ = try encodeReply(reply)
        return reply
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw CollectorHostBrokerCodecError.encodingFailed
        }
        guard data.count <= maximumPayloadBytes else {
            throw CollectorHostBrokerCodecError.payloadTooLarge
        }
        return data
    }

    private static func decode<T: Decodable>(_ data: Data) throws -> T {
        guard data.count <= maximumPayloadBytes else {
            throw CollectorHostBrokerCodecError.payloadTooLarge
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CollectorHostBrokerCodecError.decodingFailed
        }
    }

    private static func validID(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 1_024
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(
                where: CharacterSet.controlCharacters.contains)
    }

    private static func validKey(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 128
            && value.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
                    .contains($0)
            }
    }
}
