import Foundation

struct ShellResult {
    let status: Int32
    let output: String

    var ok: Bool { status == 0 }
}

enum Shell {
    /// Runs a process and returns its combined stdout/stderr.
    /// Callers that can block on a password dialog must do so off the main thread.
    @discardableResult
    static func run(_ path: String, _ arguments: [String]) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ShellResult(status: -1, output: error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ShellResult(status: process.terminationStatus, output: output)
    }
}
