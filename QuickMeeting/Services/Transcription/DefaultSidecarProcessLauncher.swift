import Foundation

struct DefaultSidecarProcessLauncher: SidecarProcessLaunching {
    func run(
        _ request: SidecarLaunchRequest,
        onLine: @escaping @Sendable (String) async throws -> Void
    ) async throws {
        guard FileManager.default.fileExists(atPath: request.executableURL.path) else {
            throw SidecarLaunchError.executableMissing
        }

        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.currentDirectoryURL = request.executableURL.deletingLastPathComponent()
        process.environment = ProcessInfo.processInfo.environment.merging(request.environment) { _, new in
            new
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutTask = Task {
            for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                try await onLine(String(line))
            }
        }

        do {
            try process.run()
        } catch {
            stdoutTask.cancel()
            throw SidecarLaunchError.launchFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        do {
            try await stdoutTask.value
        } catch {
            throw error
        }

        if process.terminationStatus != 0 {
            let stderrData = try stderrPipe.fileHandleForReading.readToEnd() ?? Data()
            let stderr = String(decoding: stderrData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SidecarLaunchError.launchFailed(stderr.isEmpty ? "Sidecar process failed." : stderr)
        }
    }
}
