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
  let collectionRuntime: ProviderCollectionRuntime

  init(
    httpClient: ProviderHTTPClient = ProviderHTTPClient(),
    collectionRuntime runtimeOverride: ProviderCollectionRuntime? = nil
  ) {
    let codex = CodexUsageClient(httpClient: httpClient)
    let claude = ClaudeUsageClient()
    let googleConsumer = GoogleConsumerUsageClient()
    let googleProject = GeminiAPIProjectUsageClient(httpClient: httpClient)
    let openRouter = OpenRouterUsageClient(httpClient: httpClient)
    self.codex = codex
    self.claude = claude
    self.googleConsumer = googleConsumer
    self.googleProject = googleProject
    self.openRouter = openRouter
    googleConnections = ProviderConnectionCoordinator(httpClient: httpClient)
    openRouterConnections = ProviderConnectionCoordinator(httpClient: httpClient)
    let nativeExecutor = NativeProviderObservationExecutor(
      codex: codex,
      claude: claude,
      googleConsumer: googleConsumer,
      googleProject: googleProject,
      openRouter: openRouter)
    if let runtimeOverride {
      collectionRuntime = runtimeOverride
    } else {
      collectionRuntime = .production { step, context in
        try await nativeExecutor.execute(step, context: context)
      }
    }
  }
}
