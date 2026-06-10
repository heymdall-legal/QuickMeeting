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
            for await line in Self.lineStream(from: stdoutPipe.fileHandleForReading) {
                try await onLine(line)
            }
        }
        let stderrTask = Task {
            var lines = [String]()
            for await line in Self.lineStream(from: stderrPipe.fileHandleForReading) {
                lines.append(line)
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

    /// Streams newline-delimited UTF-8 lines from a file handle.
    ///
    /// Reads in chunks via `readabilityHandler` rather than `FileHandle.AsyncBytes`,
    /// which iterates one byte at a time and is orders of magnitude slower for
    /// high-volume output (e.g. verbose sidecar diagnostics on stderr).
    private static func lineStream(from handle: FileHandle) -> AsyncStream<String> {
        AsyncStream { continuation in
            var buffer = Data()
            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty else {
                    if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
                        continuation.yield(line)
                    }
                    fileHandle.readabilityHandler = nil
                    continuation.finish()
                    return
                }

                buffer.append(data)
                while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<newlineIndex)
                    buffer.removeSubrange(buffer.startIndex...newlineIndex)
                    if let line = String(data: lineData, encoding: .utf8) {
                        continuation.yield(line)
                    }
                }
            }
            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
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
