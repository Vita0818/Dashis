# Capability policy

CodexBar unifies orchestration, not provider behavior. A strategy's reported
kind is display metadata, not a trustworthy permission boundary. In the pinned
Core, an API/OAuth strategy can start a CLI, a CLI strategy can inspect
Keychain/browser state, and a web strategy can refresh credentials.

The collector facade therefore uses three fail-closed gates:

| Phase | Happens before | Required match |
| --- | --- | --- |
| Request | host account resolution and Core context construction | exact provider, account scope, source, runtime, credits scope, optional-usage scope, interaction |
| Planning | `resolveStrategies` | exact planning rule plus the complete conservative capability envelope |
| Strategy | `isAvailable` and `fetch` | exact strategy ID/kind rule plus the complete conservative capability envelope |
| Result attribution | public payload construction | returned strategy ID/kind equals the approved strategy; selected-account identity and dashboard claims satisfy the host expectation |

The conservative envelope is `Set(CollectorCapability.allCases)`. It includes
strategy resolution, opaque upstream execution, network, provider local state,
browser session, Keychain, subprocess, credential mutation, and potentially
billable probes. This intentionally over-authorizes the acknowledged effect
set while still denying execution unless the request, planner, and exact
strategy all have matching rules. A newly introduced strategy ID cannot match
an old exact rule.

This is not an operating-system sandbox. A custom `CollectorSourcePolicy`
implementation is host authority and must honor every candidate's
`requiredCapabilities`; returning `allow` without doing so deliberately
bypasses the static capability check.

## Rollout inventory is not authorization

`CollectorRolloutCatalog` is the App/Worker-shared inventory for the selected
34 providers. It pins 52 exact upstream strategy identities and derives 50
explicit, non-`.auto` source bindings. `CollectorObservedEffect` values record
effects found during source review so risky adapters cannot look harmless in
staging; they are not complete phase-by-phase effect manifests and never grant
a capability. Every staged binding still carries effect-manifest, brokered
host-services, operation-scoped hard-termination, and signed-release review
reminders; those fields are not themselves the production authorization set.

`CollectorLiveRouteCatalog` separately repeats a frozen list of 41 executable
binding IDs for 30 extended providers. Each route has a digest over its
execution-affecting fields, but that route manifest must not be described as a
complete phase-by-phase effect manifest. Adding or changing the staging
inventory does not automatically authorize another route.

`opencodego.local`, `kimi.cli`, and `mimo.local` are recorded but have no
explicit source binding in the pinned Core. They require an upstream split or
another exact entry point; a host must not enable `.auto` or invent a source to
make them appear routable.

## Required review before a rule is added

For the pinned implementation, record:

1. exact provider, source, runtime, strategy ID/kind, credits scope, and
   optional-usage scope;
2. resolver work and fallback order;
3. HTTP methods, hosts, paths, redirects, body, and response limits;
4. whether the endpoint is official, private, or inferred;
5. environment variables, config files, auth files, Keychain items, browser
   stores, databases, and logs it reads;
6. every credential or config writeback;
7. subprocess executable, arguments, inherited environment, timeout, and
   cancellation behavior;
8. whether a probe can create usage or cost;
9. account-selection, identity proof, and multi-account behavior;
10. provider terms, user consent, and the user-facing source label.

Only then should the host add matching request, planning, and exact-strategy
rules. `includeCredits` and `includeOptionalUsage` default to `false`; enabling
either requires separate exact rules because it can add network, local-history,
or subprocess work.

## Account boundary

Ambient collection is distinct from selected-account collection. A selected
account must contain a stable UUID and must be confirmed by the host
`accountResolver`. The resolver returns account-specific environment/settings
and, when applicable, the upstream token-account UUID, together with an exact
`CodexBarAccountIdentityExpectation`. The selected-account environment and
settings replace the ambient host values rather than merging with them. A
missing resolver, label-only selection, mismatched confirmed UUID, wrong
provider expectation, or expectation without a non-empty email/provider
account-ID anchor fails before strategy resolution.

The result retains the requested account, an explicit resolution status, and
the provider-reported identity. After fetch, the usage identity and any
dashboard signed-in email must agree with the expectation. Missing,
conflicting, or wrong-provider evidence rejects the entire payload, stops
fallback, and leaves the resolution at `.hostResolved`; selected success is
marked `.resultVerified`. Consumers must not infer credential ownership from a
display label. Selected-account token updates are forwarded only for the
confirmed UUID; the account-less manual-token callback is disabled in that
mode.

This verification happens after the authorized fetch. It prevents wrong
attribution but cannot prevent or reverse HOME/file, login-shell, browser,
Keychain, network, subprocess, or credential-mutation effects inside Core.

## Result boundary

The normalized result preserves raw quota values and component timestamps.
Live-only provider state that CodexBar deliberately excludes from its
persistent `UsageSnapshot` encoding is emitted as versioned
`CollectorProviderArtifact` records for Z.ai, MiniMax, DeepSeek, OpenCode Go,
Cursor request plans, and Command Code. The optional OpenAI dashboard is a
separate artifact. Usable data plus an upstream diagnostic remains a success
with a sanitized warning, not a terminal failure.

The transient Claude Keychain persistent-reference hash is intentionally not
placed in the Codable result. The one-way history owner identifier and
credential comparison state, including `matched` and `notApplicable`, are
preserved.

## Important non-guarantees

- Some pinned Core paths directly read
  `ProcessInfo.processInfo.environment`. Dashis therefore clears non-runtime
  inherited Worker variables and installs only the selected route's brokered
  keys for the operation. A login shell can still source user rc files.
- Upstream fetchers use their own HTTP/session behavior and do not inherit
  Dashis endpoint allowlists.
- Nil token-update callbacks prevent facade-owned callback persistence, but
  cannot undo provider implementations that refresh their own credential
  files.
- Core contains CodexBar-namespaced caches, Keychain services, and filesystem
  paths. Browser and Keychain operations can trigger macOS privacy prompts.
- The facade disables persistent CLI context and rejects
  `debugKeepCLISessionsAlive`. The current Dashis Worker cancels the task,
  calls `collector.shutdown()`, waits two seconds, then kills its own process
  group and exits. This is an operation hard-stop fallback, but detached
  descendants are not yet proven contained.
- App Sandbox rules can make an adapter compile yet fail at runtime.
- Source-code licenses do not grant permission to use private provider APIs or
  another product's browser session.

The XPC transport, 41-route exact authorization catalog, one-operation
configuration broker, environment lease, and Worker hard-stop fallback are
implemented. They are not a complete OS sandbox: per-strategy effect manifests,
host-owned HTTP/file/Keychain/browser/subprocess brokers, detached-child
containment, and Developer ID release validation remain separate work.
