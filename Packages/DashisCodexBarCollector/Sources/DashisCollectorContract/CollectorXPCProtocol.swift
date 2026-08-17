import Foundation

public enum DashisCollectorXPC {
    public static let serviceName = "com.Vita0818.DashisMac.CollectorWorker"
    public static let errorDomain = "com.Vita0818.DashisMac.CollectorWorker.Transport"
}

@objc public protocol DashisCollectorXPCProtocol {
    func send(
        _ requestData: Data,
        withReply reply: @escaping (Data?, NSError?) -> Void)
}

/// Reverse, connection-scoped channel used by the Worker to request only the
/// configuration keys declared by the exact authorized live route.
@objc public protocol DashisCollectorHostBrokerXPCProtocol {
    func resolve(
        _ requestData: Data,
        withReply reply: @escaping (Data?, NSError?) -> Void)
}
