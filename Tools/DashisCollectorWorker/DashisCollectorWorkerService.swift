import DashisCollectorContract
import Foundation

final class DashisCollectorWorkerService: NSObject, DashisCollectorXPCProtocol {
  private let coordinator: CollectorWorkerCoordinator
  private let broker: CollectorWorkerHostBroker

  init(
    coordinator: CollectorWorkerCoordinator = .shared,
    broker: CollectorWorkerHostBroker
  ) {
    self.coordinator = coordinator
    self.broker = broker
    super.init()
  }

  func send(
    _ requestData: Data,
    withReply reply: @escaping (Data?, NSError?) -> Void
  ) {
    let request: CollectorWireRequest
    do {
      request = try CollectorWireCodec.decodeRequest(requestData)
    } catch {
      reply(nil, Self.transportError(code: 1, reason: "invalid_request"))
      return
    }

    let replyBox = CollectorWorkerReplyBox(reply)
    let coordinator = self.coordinator
    let broker = self.broker
    Task.detached { @Sendable [coordinator, request, replyBox, broker] in
      let response = await coordinator.handle(request, broker: broker)
      do {
        replyBox.send(
          data: try CollectorWireCodec.encodeReply(response),
          error: nil)
      } catch {
        let fallback = CollectorWireReply(
          requestID: request.requestID,
          status: .internalFailure,
          failure: CollectorWireFailure(
            code: "response_encoding_failed",
            message: "The worker could not encode a bounded response."))
        if let data = try? CollectorWireCodec.encodeReply(fallback) {
          replyBox.send(data: data, error: nil)
        } else {
          replyBox.send(
            data: nil,
            error: Self.transportError(code: 2, reason: "response_encoding_failed"))
        }
      }
    }
  }

  private static func transportError(code: Int, reason: String) -> NSError {
    NSError(
      domain: DashisCollectorXPC.errorDomain,
      code: code,
      userInfo: [NSLocalizedDescriptionKey: reason])
  }
}

private final class CollectorWorkerReplyBox: @unchecked Sendable {
  private let lock = NSLock()
  private var reply: ((Data?, NSError?) -> Void)?

  init(_ reply: @escaping (Data?, NSError?) -> Void) {
    self.reply = reply
  }

  func send(data: Data?, error: NSError?) {
    let reply: ((Data?, NSError?) -> Void)?
    lock.lock()
    reply = self.reply
    self.reply = nil
    lock.unlock()
    reply?(data, error)
  }
}
