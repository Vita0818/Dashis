# Dashis CodexBar Collector

This collection package is wired into Dashis through an isolated XPC worker.
The Dashis app target links only the Foundation-only contract; the worker
target links the live collector and pinned Core. The provider Store and UI
consume 41 exact live routes for 30 extended providers; Codex, Claude, Gemini,
and OpenRouter keep their existing native implementations.

The package provides:

- a Foundation-only `DashisCollectorContract` product;
- a bounded, versioned, Data-only XPC request/reply contract;
- a shared rollout inventory for 34 selected providers, 52 pinned strategies,
  and 50 exact non-automatic source bindings;
- a separately frozen executable catalog of 41 exact routes for 30 extended
  providers;
- a one-operation reverse-XPC configuration broker;
- a `CodexBarCollector` facade over the pinned CodexBar Core snapshot;
- a catalog for all 63 registered providers;
- separate request, strategy-planning, and exact-strategy policy checks;
- a versioned result envelope that preserves source, strategy, attempts,
  component timestamps, raw percentages, resets, credits, confidence,
  provider artifacts, dashboard data, and sanitized diagnostics;
- an explicit host account resolver plus provider-reported identity
  expectation that must verify every non-ambient result before attribution;
- synthetic, offline tests.

## Safety defaults

`CodexBarCollector()` is inert by default:

- request policy defaults to deny;
- strategy-planning policy defaults to deny before the upstream resolver runs;
- strategy policy defaults to deny;
- allowed capabilities default to none;
- the facade-supplied environment starts empty;
- the facade does not load or create CodexBar's default config;
- token-update callbacks are not installed;
- the context disables persistent CLI sessions and rejects settings that
  explicitly request them;
- verbose logging and HTML debug dumps are disabled.

The policy is an acknowledgement and routing gate, not an operating-system
sandbox. Once an upstream strategy is explicitly allowed, CodexBar Core may
use its own network client and may read local provider files, Keychain items,
browser profiles, or start subprocesses. Some provider implementations can
read `ProcessInfo.processInfo.environment` directly, use CodexBar-namespaced
storage, or refresh and rewrite credentials. Review `CAPABILITIES.md` before
connecting the package to a host application.

## Current host boundary

The Dashis app depends on `DashisCollectorContract` at the anti-corruption
boundary and keeps `CodexBarCore` types out of the app target and existing
`ProviderSnapshot` model. `DashisCollectorWorker.xpc` is the only Xcode target
that links `CodexBarCollector` and the pinned Core.

The v4 XPC wire rejects `.auto` sources, bounds requests to 256 KiB and replies
to 2 MiB, encodes dates as Unix milliseconds, and limits requested budgets to
1–120000 ms. Every collect request must also carry the exact route ID,
strategy ID/kind, route-manifest SHA-256, pinned upstream revision, live
catalog revision, one-use broker lease, and per-run consent state. The worker
revalidates those fields against its own registry before invoking the
collector. The handshake binds both processes to the same rollout revision,
34/52/50 staging counts, 41-route live revision, and route-set digest. Unknown
or mismatched routes remain default-deny.

For an authorized operation, the production worker obtains only the selected
route's declared configuration keys through the reverse broker and constructs
a fresh collector with one request rule, one planning rule, and one exact
strategy rule. The worker removes non-runtime inherited environment variables
at startup, temporarily installs the brokered route values into both the
facade context and real process environment, then removes them after the run.

`CollectorRolloutCatalog` records exact strategy identities and source-code
audit observations without importing Core into the app. Its observed effects
are intentionally incomplete review clues, not effect manifests or policy
rules. `opencodego.local`, `kimi.cli`, and `mimo.local` have no explicit source
entry in the pinned Core, so they remain automatic-only and cannot become
Dashis routes while release requests reject `.auto`. `CollectorLiveRouteCatalog`
separately repeats the exact authorized binding IDs; adding a staging binding
does not make it executable.

An explicit policy must allow the exact request scope, upstream planning, and
each exact resolved strategy. Until a reviewed per-strategy effect manifest
exists, planning and execution conservatively require the complete capability
set:

```swift
let policy = StaticCollectorSourcePolicy(
    allowedCapabilities: Set(CollectorCapability.allCases),
    requestRules: [
        CollectorRequestRule(
            id: "openrouter-user-action",
            provider: "openrouter",
            account: .ambient,
            source: .api,
            runtime: .app,
            includeCredits: false,
            includeOptionalUsage: false,
            interaction: .userInitiated,
            allow: true,
            reason: "User explicitly requested an OpenRouter refresh."),
    ],
    planningRules: [
        CollectorPlanningRule(
            id: "openrouter-api-planning",
            provider: "openrouter",
            account: .ambient,
            source: .api,
            runtime: .app,
            includeCredits: false,
            includeOptionalUsage: false,
            interaction: .userInitiated,
            allow: true,
            reason: "This pinned provider/source planner was reviewed."),
    ],
    strategyRules: [
        CollectorStrategyRule(
            id: "openrouter-api-token",
            provider: "openrouter",
            account: .ambient,
            source: .api,
            runtime: .app,
            includeCredits: false,
            includeOptionalUsage: false,
            interaction: .userInitiated,
            strategyID: "openrouter.api",
            kind: .apiToken,
            allow: true,
            reason: "This exact strategy was reviewed by the host."),
    ])
```

The example is illustrative. The exact upstream strategy ID and its endpoint,
credential, mutation, and billing behavior must be verified against the pinned
source before it is allowed.

Use `CollectorConfiguration.ambientProcess(...)` only when the host has
explicitly decided that inherited environment credentials are in scope.
Provider-specific `ProviderSettingsSnapshot` values and token persistence
callbacks can be supplied through `CodexBarHostConfiguration`; its default is
`.disabled`. That advanced boundary intentionally stays in the live collector
module while all result and policy types remain Core-independent.

Any request with a selected account ID is rejected unless
`CodexBarHostConfiguration.accountResolver` returns a matching
`CodexBarResolvedAccountContext`. That callback is where a future live Dashis
route must map its account store to reviewed environment/settings/token-account
inputs and an exact `CodexBarAccountIdentityExpectation`. Its environment and
settings replace the ambient host values to prevent facade-level credential
bleed between accounts. After fetch, the provider-reported identity and any
dashboard email must satisfy that expectation before a selected-account
payload is exposed; only then is the outcome marked `.resultVerified`.
Insufficient or conflicting evidence rejects the entire payload without
fallback. A display label alone never selects credentials. Selected-account
token-account updates are forwarded only when the callback UUID matches the
confirmed account; the account-less manual token updater is disabled for
selected accounts.

The result strategy ID/kind must also equal the exact strategy that passed the
policy gate. A different upstream provenance is rejected instead of being
published under an allowed attempt.

## Deliberate live-route limitations

- Thirty ambient-account provider integrations are live only after the user
  selects an exact method and clicks `Check usage`; app launch, catalog
  browsing, and opening a detail page do not collect.
- Dashis maps validated `CollectorOutcome` values through
  `ProviderObservation` into the existing `ProviderSnapshot` UI.
- Selected-account mode requires the provider to report a stable account email
  or provider account ID. Providers without enough result identity evidence
  remain ambient-only; the current 41 UI routes all use ambient account slots.
- Route-declared environment fields are present in the UI and kept only in app
  memory. CodexBar config import and per-provider
  `ProviderSettingsSnapshot` mapping are not present.
- The Claude watchdog can be built from the vendored package, but it is not
  embedded, signed, or launched by Dashis.
- CodexBar Core's HTTP behavior does not yet use Dashis
  `ProviderEndpointPolicy` or ephemeral session configuration.
- The current authority envelope deliberately grants all declared
  capabilities for a reviewed planner/strategy. It is safe-by-denial but not a
  fine-grained sandbox. The route-manifest digest binds executable route
  fields; the observed-effect list is not a complete effect manifest.
- Operation deadlines cancel the task, call `collector.shutdown()`, wait two
  seconds, then terminate the worker-owned process group and exit the worker.
  This is a hard-stop fallback, not proof that every detached descendant is
  contained.
- `RateWindow` remaining is recomputed from raw `usedPercent` without clamping.
  Values already normalized inside an upstream provider-specific model (for
  example parts of `CodexCreditLimitSnapshot`) cannot be reconstructed.
- Selected-account verification is a post-fetch attribution gate. It prevents
  publishing data under the wrong account, but it cannot undo Core reads,
  prompts, subprocesses, network calls, or credential writes that already
  occurred inside an explicitly allowed strategy.

These limits are intentional. The backend, Store, and UI are live, while real
provider execution remains a user-initiated action and automated validation
uses synthetic outcomes only.

## Standalone validation

Keep all build output outside the repository:

```sh
env \
  CLANG_MODULE_CACHE_PATH=/private/tmp/dashis-clang-module-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/dashis-swiftpm-module-cache \
  swift test \
  --package-path Packages/DashisCodexBarCollector \
  --scratch-path /private/tmp/dashis-codexbar-collector-build \
  --disable-sandbox
```
