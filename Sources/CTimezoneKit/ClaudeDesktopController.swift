import AppKit
import Foundation

/// Controls the installed Claude Desktop app: reports its startup environment
/// and launches/relaunches it with an explicit `TZ`.
///
/// This never uses `open -n` (Electron's single-instance lock makes it
/// unreliable and can spawn duplicate profiles) and never force-quits. When a
/// running instance has the wrong environment, the caller must confirm, then we
/// `terminate()` gracefully and wait a bounded time before launching.
public final class ClaudeDesktopController {
    public static let bundleIdentifier = "com.anthropic.claudefordesktop"
    public static let appPath = "/Applications/Claude.app"

    public struct Status: Equatable {
        public let isRunning: Bool
        /// Observed `TZ` of the running main instance (never logged raw).
        public let observedTZ: ProcessTZProbe.Result
    }

    public enum LaunchOutcome: Equatable {
        /// A running instance already had the desired `TZ`; brought to front.
        case activated
        /// No instance was running; launched fresh.
        case launched
        /// The user declined to relaunch the running instance; nothing changed.
        case cancelled
        /// A running instance had a different/unknown `TZ`; relaunched.
        case relaunched
        /// Launch or relaunch failed (message is non-sensitive).
        case failed(String)
    }

    public init() {}

    private var runningMains: [NSRunningApplication] {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier)
        let mains = apps.filter { $0.activationPolicy == .regular }
        return mains.isEmpty ? apps : mains
    }

    /// Reports whether Claude Desktop is running and its observed `TZ`.
    public func status() -> Status {
        guard let main = runningMains.first else {
            return Status(isRunning: false, observedTZ: .absent)
        }
        return Status(isRunning: true, observedTZ: ProcessTZProbe.read(pid: main.processIdentifier))
    }

    /// Brings the running instance forward without touching its environment.
    /// Returns false when Claude is not running.
    @discardableResult
    public func activateRunning() -> Bool {
        guard let main = runningMains.first else { return false }
        return main.activate(options: [])
    }

    /// True when the running instance's observed `TZ` already matches `desired`.
    public func matches(desired: String) -> Bool {
        if case .value(let current) = status().observedTZ { return current == desired }
        return false
    }

    /// Ensures Desktop is running with `desired` TZ. `confirmTerminate` is only
    /// invoked when a running instance must be replaced; returning `false`
    /// aborts without touching the process.
    public func activateOrLaunch(
        desired: String,
        confirmTerminate: @Sendable () async -> Bool
    ) async -> LaunchOutcome {
        let mains = runningMains
        if let main = mains.first {
            if case .value(let current) = ProcessTZProbe.read(pid: main.processIdentifier),
               current == desired {
                main.activate(options: [])
                return .activated
            }
            guard await confirmTerminate() else { return .cancelled }
            for app in mains {
                await terminateAndWait(app, timeout: 8)
            }
        }
        let status = await Self.runOpen(["-a", Self.appPath, "--env", "TZ=\(desired)"])
        if status == 0 {
            return mains.isEmpty ? .launched : .relaunched
        }
        return .failed("open exited with status \(status)")
    }

    // MARK: - Internals

    /// Graceful terminate with a bounded wait. Never force-quits.
    private func terminateAndWait(_ app: NSRunningApplication, timeout: TimeInterval) async {
        guard !app.isTerminated else { return }
        app.terminate()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.isTerminated { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    /// Runs `/usr/bin/open` without capturing output (null device, so no pipe
    /// can block) and without `waitUntilExit` on the main thread.
    private static func runOpen(_ arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }
    }
}
