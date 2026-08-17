# CodexBar Core upstream snapshot

This directory contains an unmodified source snapshot of CodexBar's collection
engine. Dashis-authored integration code lives outside this directory.

- Repository: <https://github.com/steipete/CodexBar>
- Release: `v0.45.2`
- Annotated tag object: `64495789e096307e8d723a98623bf22cdb2d9c28`
- Source commit: `91560ca98e776b96fdf910d4a0423c2f0c07a3b9`
- Retrieved: `2026-07-26`
- `Sources/CodexBarCore` Git tree: `73ca3e9124b69066afd99ed1c6a47a0e565c0f4f`
- `Sources/CSQLite3` Git tree: `d21b6967fc8998c5c230c785b544fca56719696a`
- Core Swift source count: `474`
- Registered providers: `63`

The local `Package.swift` is intentionally smaller than the upstream package
manifest. It declares only the verified runtime closure for `CodexBarCore` and
the optional Claude process watchdog; it does not include the CodexBar app,
CLI, updater, UI, widgets, diagnostic web probe, or their dependencies.

The upstream source directories and `LICENSE` are byte-for-byte copies from the
source commit above. Local changes to those files are prohibited. Any future
exception must be documented in `PATCHES.md`.

## Refresh procedure

1. Select an immutable release tag and record its peeled source commit.
2. Review changes to providers, endpoints, credential reads and writes,
   subprocesses, storage namespaces, dependencies, and licenses.
3. Replace the upstream source directories without carrying local edits.
4. Update the tree hashes, provider count, dependency pins, notices, and
   `PATCHES.md`.
5. Run the standalone package tests with build output outside the repository.
6. Confirm the Dashis app target links only `DashisCollectorContract`, the XPC
   worker is the sole target linking `CodexBarCollector`/Core, and the pinned
   upstream source directories remain byte-for-byte unchanged.

CodexBar is licensed under MIT. Provider APIs, browser sessions, local
credentials, and private endpoints can have additional terms that are not
granted by the source-code license.
