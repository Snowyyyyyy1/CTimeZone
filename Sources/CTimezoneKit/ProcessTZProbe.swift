import Darwin
import Foundation

/// Reads the `TZ` environment variable of a running process.
///
/// Uses `KERN_PROCARGS2` via `sysctl`, so there is no child process and no
/// pipe that could block or truncate. Only `TZ` is extracted; the rest of the
/// process environment is never surfaced or logged.
public enum ProcessTZProbe {
    public enum Result: Equatable {
        /// `TZ` was present with this value.
        case value(String)
        /// `TZ` was absent from the process environment.
        case absent
        /// The environment could not be read (permissions, process gone, size).
        case unavailable
    }

    public static func read(pid: pid_t) -> Result {
        guard pid > 0 else { return .unavailable }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else {
            return .unavailable
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else {
            return .unavailable
        }
        guard let value = extractTZ(from: buffer) else { return .absent }
        return .value(value)
    }

    /// Layout: `argc` (Int32), exec path, NUL, then `argc` argv strings, then the
    /// environment block of `KEY=VALUE` NUL-terminated strings.
    static func extractTZ(from buffer: [UInt8]) -> String? {
        guard buffer.count >= MemoryLayout<Int32>.size else { return nil }
        let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        var index = MemoryLayout<Int32>.size

        // Skip the exec path.
        while index < buffer.count && buffer[index] != 0 { index += 1 }
        while index < buffer.count && buffer[index] == 0 { index += 1 }

        // Skip argv.
        for _ in 0..<max(argc, 0) {
            while index < buffer.count && buffer[index] != 0 { index += 1 }
            index += 1
        }

        // Walk the environment block.
        while index < buffer.count {
            var entry = ""
            while index < buffer.count && buffer[index] != 0 {
                entry.append(Character(UnicodeScalar(buffer[index])))
                index += 1
            }
            index += 1
            if entry.hasPrefix("TZ=") {
                return String(entry.dropFirst(3))
            }
        }
        return nil
    }
}
