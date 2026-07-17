import Foundation

/// Composition root for provider adapters. It intentionally contains no
/// provider-specific parsing, credential persistence, or network policy.
final class DashisProviderService {
  let codex: CodexUsageClient
  let claude: ClaudeUsageClient
  let googleConsumer: GoogleConsumerUsageClient
  let googleProject: GeminiAPIProjectUsageClient
  let openRouter: OpenRouterUsageClient
  let googleConnections: ProviderConnectionCoordinator
  let openRouterConnections: ProviderConnectionCoordinator

  init(httpClient: ProviderHTTPClient = ProviderHTTPClient()) {
    codex = CodexUsageClient(httpClient: httpClient)
    claude = ClaudeUsageClient()
    googleConsumer = GoogleConsumerUsageClient()
    googleProject = GeminiAPIProjectUsageClient(httpClient: httpClient)
    openRouter = OpenRouterUsageClient(httpClient: httpClient)
    googleConnections = ProviderConnectionCoordinator(httpClient: httpClient)
    openRouterConnections = ProviderConnectionCoordinator(httpClient: httpClient)
  }
}
