# Local patches

No CodexBar upstream source files are patched.

The only Dashis-owned source/build-definition file is the reduced
`Package.swift`, which preserves the upstream Core target settings while
excluding unrelated application products and dependencies. The
Dashis-owned `Package.resolved` lock file fixes the reviewed dependency
revisions.
