import Foundation

protocol ProviderUsageClient {
  associatedtype Context

  var providerID: ProviderID { get }
  func fetchSnapshot(context: Context) async -> ProviderSnapshot
}

