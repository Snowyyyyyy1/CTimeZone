@testable import CTimezoneKit
import XCTest

final class ProcessTZProbeTests: XCTestCase {
    /// Builds a minimal `KERN_PROCARGS2`-style buffer:
    /// Int32 argc, exec path, NUL, argv entries, then the env block.
    private func makeBuffer(argc: Int32, execPath: String, argv: [String], env: [String]) -> [UInt8] {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: argc) { bytes.append(contentsOf: $0) }
        bytes.append(contentsOf: Array(execPath.utf8)); bytes.append(0)
        bytes.append(0) // padding NUL between path and argv
        for arg in argv { bytes.append(contentsOf: Array(arg.utf8)); bytes.append(0) }
        for e in env { bytes.append(contentsOf: Array(e.utf8)); bytes.append(0) }
        return bytes
    }

    func testExtractsTZFromEnvironment() {
        let buffer = makeBuffer(
            argc: 1,
            execPath: "/Applications/Claude.app/Contents/MacOS/Claude",
            argv: ["Claude"],
            env: ["PATH=/usr/bin", "TZ=Europe/Amsterdam", "HOME=/Users/x"]
        )
        XCTAssertEqual(ProcessTZProbe.extractTZ(from: buffer), "Europe/Amsterdam")
    }

    func testReturnsNilWhenTZAbsent() {
        let buffer = makeBuffer(
            argc: 1,
            execPath: "/bin/zsh",
            argv: ["zsh"],
            env: ["PATH=/usr/bin", "HOME=/Users/x"]
        )
        XCTAssertNil(ProcessTZProbe.extractTZ(from: buffer))
    }

    func testShortBufferReturnsNil() {
        XCTAssertNil(ProcessTZProbe.extractTZ(from: [0x01]))
    }

    func testReadOnSelfIsNotUnavailable() {
        // Reading our own environment should succeed (value or absent), never unavailable.
        let result = ProcessTZProbe.read(pid: getpid())
        XCTAssertNotEqual(result, .unavailable)
    }
}
