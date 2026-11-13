import Foundation

/// Whether the measurement tools are on: the HUD, the gesture log, scripted demos
/// and the stress test. Always on in debug builds. In release builds (the only builds
/// whose performance numbers mean anything) they are off unless the app is launched
/// with `-hud`, `-stress` or one of the demo arguments.
enum Diagnostics {
    static let enabled: Bool = {
        #if DEBUG
        return true
        #else
        let args = ProcessInfo.processInfo.arguments
        return ["-hud", "-stress", "-stress-cap", "-demo", "-demo3", "-demo4", "-demo5"].contains { args.contains($0) }
        #endif
    }()
}
