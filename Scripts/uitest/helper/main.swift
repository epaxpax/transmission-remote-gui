// TRGUI UITest Helper — runs an AppleScript file on behalf of the UI test harness.
//
// Why an .app: macOS grants Accessibility per *responsible app*. Processes spawned by
// Claude Code / a terminal are attributed to `osascript` itself, which the System Settings
// picker cannot select. Launched with `open`, this app is the responsible process for the
// `osascript` it spawns, so ONE Accessibility toggle for this app covers every UI test.
//
// Usage: open -W -n -a "TRGUI UITest Helper" --args <script.applescript> <result.json>
import ApplicationServices
import Foundation

let args = CommandLine.arguments
// First run: registers the app in System Settings → Accessibility (with the system prompt).
let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)

guard args.count >= 3 else { exit(trusted ? 0 : 2) }
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
p.arguments = [args[1]]
let out = Pipe(), err = Pipe()
p.standardOutput = out; p.standardError = err
try p.run(); p.waitUntilExit()
let result: [String: Any] = [
    "trusted": trusted,
    "status": Int(p.terminationStatus),
    "stdout": String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
    "stderr": String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
]
try JSONSerialization.data(withJSONObject: result).write(to: URL(fileURLWithPath: args[2]))
