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
        process.currentDirectoryURL = request.workingDirectoryURL
        process.environment = request.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutTask = Task {
            for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                try await onLine(String(line))
            }
        }
        let stderrTask = Task {
            var lines = [String]()
            for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                lines.append(String(line))
            }
            return lines.joined(separator: "\n")
        }

        let terminationStatus: Int32
        do {
            terminationStatus = try await runUntilTermination(process)
        } catch {
            stdoutTask.cancel()
            stderrTask.cancel()
            throw SidecarLaunchError.launchFailed(error.localizedDescription)
        }

        do {
            try await stdoutTask.value
        } catch {
            stderrTask.cancel()
            throw error
        }

        let stderr = (try? await stderrTask.value)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if terminationStatus != 0 {
            throw SidecarLaunchError.launchFailed(stderr.isEmpty ? "Sidecar process failed." : stderr)
        }
    }

    private func runUntilTermination(_ process: Process) async throws -> Int32 {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { process in
                    continuation.resume(returning: process.terminationStatus)
                }

                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}
