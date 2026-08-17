import DashisCollectorContract
import Darwin
import Foundation

let collectorWorkerSafeAmbientEnvironmentKeys: Set<String> = [
  "CI",
  "CODEXBAR_DISABLE_KEYCHAIN_ACCESS",
  "CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS",
  "HOME",
  "LANG",
  "LC_COLLATE",
  "LC_ALL",
  "LC_CTYPE",
  "LC_MESSAGES",
  "LC_MONETARY",
  "LC_NUMERIC",
  "LC_TIME",
  "LOGNAME",
  "OS_ACTIVITY_DT_MODE",
  "PATH",
  "PWD",
  "SHELL",
  "SWIFT_TESTING",
  "SWIFT_TESTING_ENABLED",
  "TESTING_LIBRARY_VERSION",
  "TMPDIR",
  "USER",
  "XDG_CACHE_HOME",
  "XDG_CONFIG_HOME",
  "XDG_DATA_HOME",
  "XPC_FLAGS",
  "XPC_SERVICE_NAME",
  "XCTestBundlePath",
  "XCTestConfigurationFilePath",
  "XCTestSessionIdentifier",
  "__CF_USER_TEXT_ENCODING",
]

// Keep provider subprocesses in a Worker-owned process group so the hard
// deadline can terminate the service and any still-attached descendants
// without signaling the parent Dashis app.
let collectorWorkerOwnsProcessGroup =
  setpgid(0, 0) == 0 && getpgrp() == getpid()

// XPC services inherit the parent environment. Start from an explicit runtime
// allowlist so aliases or future provider variables cannot bypass the broker.
// Route-scoped values are installed only for one authorized operation.
for key in ProcessInfo.processInfo.environment.keys
where !collectorWorkerSafeAmbientEnvironmentKeys.contains(key)
{
  unsetenv(key)
}

let delegate = CollectorWorkerListener()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
dispatchMain()
