import Foundation
import KeelhavenCore

// Keelhaven's privileged helper: a launchd daemon, registered by the app with
// SMAppService and approved once by the user in System Settings › Login
// Items, that runs `restic backup` as root for plans set to read files as
// administrator. launchd starts it on demand when the app connects, and it
// exits again once nothing has been connected for a while — so after an app
// update the next backup always reaches the new binary.
//
// docs/ARCHITECTURE.md § "Reading as administrator" has the design.

let listenerDelegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: PrivilegedHelper.machServiceName)
listener.delegate = listenerDelegate
listener.resume()
dispatchMain()
