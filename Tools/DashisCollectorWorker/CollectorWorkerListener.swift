import DashisCollectorContract
import Foundation

final class CollectorWorkerListener: NSObject, NSXPCListenerDelegate {
  func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    connection.exportedInterface = NSXPCInterface(
      with: DashisCollectorXPCProtocol.self)
    connection.remoteObjectInterface = NSXPCInterface(
      with: DashisCollectorHostBrokerXPCProtocol.self)
    let brokerClient = CollectorWorkerBrokerClient(connection: connection)
    connection.exportedObject = DashisCollectorWorkerService(
      broker: CollectorWorkerHostBroker { requestID, authorization, route in
        try await brokerClient.resolve(
          requestID: requestID,
          authorization: authorization,
          route: route)
      })
    connection.resume()
    return true
  }
}

private final class CollectorWorkerBrokerClient: @unchecked Sendable {
  private let connection: NSXPCConnection

  init(connection: NSXPCConnection) {
    self.connection = connection
  }

  func resolve(
    requestID: UUID,
    authorization: CollectorRouteAuthorization,
    route: CollectorLiveRouteDefinition
  ) async throws -> [String: String] {
    let request = CollectorHostBrokerRequest(
      requestID: requestID,
      leaseID: authorization.brokerLeaseID,
      routeID: route.id,
      provider: route.provider,
      requestedKeys: route.allowedConfigurationKeys.sorted())
    let requestData = try CollectorHostBrokerCodec.encodeRequest(request)
    let reply: CollectorHostBrokerReply = try await withCheckedThrowingContinuation {
      continuation in
      guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
        continuation.resume(throwing: error)
      }) as? DashisCollectorHostBrokerXPCProtocol else {
        continuation.resume(throwing: CollectorWorkerBrokerError.proxyUnavailable)
        return
      }
      proxy.resolve(requestData) { responseData, responseError in
        if let responseError {
          continuation.resume(throwing: responseError)
          return
        }
        guard let responseData else {
          continuation.resume(throwing: CollectorWorkerBrokerError.missingReply)
          return
        }
        do {
          continuation.resume(
            returning: try CollectorHostBrokerCodec.decodeReply(responseData))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
    let allowedKeys = Set(route.allowedConfigurationKeys)
    guard Set(reply.environment.keys).isSubset(of: allowedKeys) else {
      throw CollectorWorkerBrokerError.unexpectedConfigurationKey
    }
    return reply.environment
  }
}

private enum CollectorWorkerBrokerError: Error {
  case proxyUnavailable
  case missingReply
  case unexpectedConfigurationKey
}
