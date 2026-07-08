import Foundation

/// Minimal test harness, since the CLT toolchain has no XCTest/Testing.
final class TestHarness: @unchecked Sendable {
    private(set) var passed = 0
    private(set) var failed = 0
    private var currentTest = ""

    func test(_ name: String, _ body: () async throws -> Void) async {
        currentTest = name
        do {
            try await body()
            print("  ✅ \(name)")
            passed += 1
        } catch {
            print("  ❌ \(name) — \(error)")
            failed += 1
        }
    }

    func expect(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) throws {
        if !condition {
            throw TestFailure(message: "\(message) (\(file):\(line))")
        }
    }

    func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) throws {
        if a != b {
            throw TestFailure(message: "\(a) != \(b) (\(file):\(line))")
        }
    }

    func unwrap<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) throws -> T {
        guard let value else { throw TestFailure(message: "nil value (\(file):\(line))") }
        return value
    }

    func summary() -> Int {
        print("\n\(passed) passed, \(failed) failed")
        return failed > 0 ? 1 : 0
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
