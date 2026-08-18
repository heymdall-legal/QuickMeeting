import CryptoKit
import Foundation
import AudioCommon
@preconcurrency import Qwen3ASR
import NativeTranscribeRuntime

nonisolated enum NativeOfflineASRError: LocalizedError {
    case invalidModelFile(String)
    case downloadFailed(String)
    case nativeRuntime(String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .invalidModelFile(let message):
            return "Downloaded model is invalid: \(message)"
        case .downloadFailed(let message):
            return "Model download failed: \(message)"
        case .nativeRuntime(let message):
            return "Native ASR failed: \(message)"
        case .emptyTranscript:
            return "The native ASR model returned an empty transcript."
        }
    }
}

nonisolated struct NativeAudioChunk: Equatable, Sendable {
    var range: Range<Int>
    var startTime: TimeInterval
}

nonisolated enum NativeAudioChunker {
    static func chunks(
        samples: [Float],
        sampleRate: Int = 16_000,
        maximumDuration: TimeInterval,
        silenceSearchDuration: TimeInterval,
        minimumDuration: TimeInterval
    ) -> [NativeAudioChunk] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }
        let maximumSamples = max(1, Int(maximumDuration * Double(sampleRate)))
        let searchSamples = max(0, Int(silenceSearchDuration * Double(sampleRate)))
        let minimumSamples = max(1, Int(minimumDuration * Double(sampleRate)))
        var result: [NativeAudioChunk] = []
        var start = 0

        while start < samples.count {
            let nominalEnd = min(samples.count, start + maximumSamples)
            var end = nominalEnd
            if nominalEnd < samples.count, nominalEnd - start > minimumSamples {
                let searchStart = max(start + minimumSamples, nominalEnd - searchSamples)
                end = quietestBoundary(
                    in: samples,
                    searchRange: searchStart..<nominalEnd,
                    sampleRate: sampleRate
                ) ?? nominalEnd
            }
            if end <= start { end = nominalEnd }
            result.append(
                NativeAudioChunk(
                    range: start..<end,
                    startTime: Double(start) / Double(sampleRate)
                )
            )
            start = end
        }
        return result
    }

    private static func quietestBoundary(
        in samples: [Float],
        searchRange: Range<Int>,
        sampleRate: Int
    ) -> Int? {
        let window = max(80, Int(0.04 * Double(sampleRate)))
        let step = max(40, window / 2)
        guard searchRange.count >= window else { return nil }
        var bestIndex: Int?
        var bestEnergy = Double.greatestFiniteMagnitude
        var center = searchRange.lowerBound + window / 2
        let lastCenter = searchRange.upperBound - window / 2

        while center <= lastCenter {
            let lower = center - window / 2
            let upper = min(samples.count, lower + window)
            var energy = 0.0
            for index in lower..<upper {
                let sample = Double(samples[index])
                energy += sample * sample
            }
            energy /= Double(max(1, upper - lower))
            if energy < bestEnergy {
                bestEnergy = energy
                bestIndex = center
            }
            center += step
        }
        return bestIndex
    }
}

private nonisolated enum NativeOfflineASRPaths {
    static func rootDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuickMeeting", isDirectory: true)
            .appendingPathComponent("OfflineASR", isDirectory: true)
    }
}

private nonisolated struct NativeAlignedWord: Sendable {
    var text: String
    var startTime: Float
    var endTime: Float
}

private nonisolated final class QwenNativeModelBundle: @unchecked Sendable {
    private let lock = NSLock()
    private let asr: Qwen3ASRModel
    private let aligner: Qwen3ForcedAligner

    init(asr: Qwen3ASRModel, aligner: Qwen3ForcedAligner) {
        self.asr = asr
        self.aligner = aligner
    }

    func transcribeAndAlign(
        samples: [Float],
        language: String,
        context: String?
    ) -> (text: String, words: [NativeAlignedWord]) {
        lock.lock()
        defer { lock.unlock() }
        let text = asr.transcribe(
            audio: samples,
            sampleRate: 16_000,
            language: language,
            context: context
        )
        guard !text.isEmpty else { return (text, []) }
        let aligned = aligner.alignLong(
                audio: samples,
                text: text,
                sampleRate: 16_000,
                language: language
            )
        return (
            text,
            aligned.map {
                NativeAlignedWord(text: $0.text, startTime: $0.startTime, endTime: $0.endTime)
            }
        )
    }
}

actor NativeQwenASRBackend: ASRBackend, ASRModelPreparing {
    nonisolated static let asrModelID = "aufklarer/Qwen3-ASR-1.7B-MLX-5bit"
    nonisolated static let alignerModelID = "aufklarer/Qwen3-ForcedAligner-0.6B-8bit"

    private let rootDirectoryURL: URL
    private var models: QwenNativeModelBundle?

    init(rootDirectoryURL: URL? = nil) {
        self.rootDirectoryURL = rootDirectoryURL ?? NativeOfflineASRPaths.rootDirectory()
            .appendingPathComponent(OfflineASRModelID.qwen3ASR17B.rawValue, isDirectory: true)
    }

    func prepare(
        modelID: OfflineASRModelID,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        guard modelID == .qwen3ASR17B else {
            throw ASRBackendRouterError.unavailable(modelID)
        }
        _ = try await loadModels(progress: progress)
        progress(1, "Ready")
    }

    func transcribe(
        _ request: ASRBackendRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ASRBackendOutput {
        guard request.modelID == .qwen3ASR17B else {
            throw ASRBackendRouterError.unavailable(request.modelID)
        }
        let wasColdStart = models == nil
        let loadStartedAt = ProcessInfo.processInfo.systemUptime
        let models = try await loadModels { fraction, _ in progress(fraction * 0.08) }
        let modelLoadingSeconds = ProcessInfo.processInfo.systemUptime - loadStartedAt
        let language = Self.qwenLanguage(for: request.languageCode)
        let glossary = request.glossaryTerms
            .filter(\.isEnabled)
            .map(\.normalizedText)
            .filter { !$0.isEmpty }
        let context = glossary.isEmpty ? nil : "Возможные термины: " + glossary.joined(separator: ", ")
        let chunks = NativeAudioChunker.chunks(
            samples: request.samples,
            maximumDuration: 230,
            silenceSearchDuration: 8,
            minimumDuration: 30
        )
        let asrStartedAt = ProcessInfo.processInfo.systemUptime
        var texts: [String] = []
        var words: [TimedWord] = []
        var warnings: [String] = []

        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let pcm = Array(request.samples[chunk.range])
            let result = await Task.detached(priority: .userInitiated) {
                models.transcribeAndAlign(samples: pcm, language: language, context: context)
            }.value
            if !result.text.isEmpty { texts.append(result.text) }
            if result.words.isEmpty, !result.text.isEmpty {
                warnings.append("Qwen ForcedAligner returned no words for chunk \(index + 1).")
            }
            words.append(contentsOf: result.words.map {
                TimedWord(
                    text: $0.text,
                    startTime: chunk.startTime + TimeInterval($0.startTime),
                    endTime: chunk.startTime + TimeInterval($0.endTime),
                    confidence: nil
                )
            })
            progress(0.08 + 0.92 * Double(index + 1) / Double(max(1, chunks.count)))
        }

        let text = texts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw NativeOfflineASRError.emptyTranscript }
        if request.ctcMode != .off {
            warnings.append("FluidAudio CTC vocabulary rescoring is available only with Parakeet.")
        }
        progress(1)
        return ASRBackendOutput(
            transcript: TimedTranscript(text: text, words: words),
            adjustedText: nil,
            replacements: [],
            modelName: Self.snapshot.modelName,
            backendSnapshot: Self.snapshot,
            resolvedCTCMode: nil,
            warnings: warnings,
            wasColdStart: wasColdStart,
            modelLoadingSeconds: modelLoadingSeconds,
            asrWallSeconds: ProcessInfo.processInfo.systemUptime - asrStartedAt,
            ctcWallSeconds: 0,
            nativeProcessingSeconds: nil
        )
    }

    private func loadModels(
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> QwenNativeModelBundle {
        if let models { return models }
        let asrDirectory = rootDirectoryURL.appendingPathComponent("asr", isDirectory: true)
        let alignerDirectory = rootDirectoryURL.appendingPathComponent("aligner", isDirectory: true)
        let asr = try await Qwen3ASRModel.fromPretrained(
            modelId: Self.asrModelID,
            cacheDir: asrDirectory,
            progressHandler: { fraction, phase in
                progress(fraction * 0.72, "Qwen3-ASR · \(phase)")
            }
        )
        let aligner = try await Qwen3ForcedAligner.fromPretrained(
            modelId: Self.alignerModelID,
            cacheDir: alignerDirectory,
            progressHandler: { fraction, phase in
                progress(0.72 + fraction * 0.28, "ForcedAligner · \(phase)")
            }
        )
        let loaded = QwenNativeModelBundle(asr: asr, aligner: aligner)
        models = loaded
        return loaded
    }

    private nonisolated static func qwenLanguage(for code: String?) -> String {
        guard let code else { return "Russian" }
        switch code.lowercased().split(separator: "-").first {
        case "en": return "English"
        case "de": return "German"
        case "fr": return "French"
        case "es": return "Spanish"
        case "it": return "Italian"
        case "pt": return "Portuguese"
        case "zh": return "Chinese"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        default: return "Russian"
        }
    }

    nonisolated static let snapshot = ASRBackendSnapshot(
        backendID: "native.mlx.qwen3-asr",
        modelID: .qwen3ASR17B,
        modelName: "Qwen3-ASR 1.7B + ForcedAligner",
        modelVersion: "\(asrModelID) + \(alignerModelID)",
        runtime: "speech-swift@f9af2f34/MLX/Metal",
        configuration: [
            "asrQuantization": "5-bit",
            "alignerQuantization": "8-bit",
            "chunkSeconds": "230, silence-aware",
            "timestamps": "Qwen3-ForcedAligner",
        ]
    )
}

private nonisolated struct NativeGigaToken: Sendable {
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var confidence: Float?
}

private nonisolated struct NativeGigaResult: Sendable {
    var text: String
    var tokens: [NativeGigaToken]
    var loadSeconds: TimeInterval
    var processingSeconds: TimeInterval?
}

private nonisolated final class NativeGigaSession: @unchecked Sendable {
    private let lock = NSLock()
    private let session: OpaquePointer

    init(modelURL: URL) throws {
        let version = String(cString: transcribe_version())
        guard version.hasPrefix("0.2.") else {
            throw NativeOfflineASRError.nativeRuntime("transcribe.cpp \(version) is incompatible with 0.2.x bindings")
        }
        try Self.requireSuccess(transcribe_init_backends_default(), operation: "initializing Metal backend")
        var loadParams = transcribe_model_load_params()
        transcribe_model_load_params_init(&loadParams)
        loadParams.backend = transcribe_backend_available(TRANSCRIBE_BACKEND_METAL)
            ? TRANSCRIBE_BACKEND_METAL
            : TRANSCRIBE_BACKEND_CPU
        var sessionParams = transcribe_session_params()
        transcribe_session_params_init(&sessionParams)
        var output: OpaquePointer?
        let status = modelURL.path.withCString {
            transcribe_open($0, &loadParams, &sessionParams, &output)
        }
        try Self.requireSuccess(status, operation: "loading GigaAM")
        guard let output else {
            throw NativeOfflineASRError.nativeRuntime("transcribe.cpp returned a null session")
        }
        session = output
    }

    deinit {
        transcribe_session_free(session)
    }

    func transcribe(_ samples: [Float]) throws -> NativeGigaResult {
        lock.lock()
        defer { lock.unlock() }
        var params = transcribe_run_params()
        transcribe_run_params_init(&params)
        params.timestamps = TRANSCRIBE_TIMESTAMPS_TOKEN
        let status = "ru".withCString { language in
            params.language = language
            return samples.withUnsafeBufferPointer {
                transcribe_run(session, $0.baseAddress, Int32($0.count), &params)
            }
        }
        try Self.requireSuccess(status, operation: "transcribing with GigaAM")

        var tokens: [NativeGigaToken] = []
        for index in 0..<Int(transcribe_n_tokens(session)) {
            var token = transcribe_token()
            transcribe_token_init(&token)
            try Self.requireSuccess(
                transcribe_get_token(session, Int32(index), &token),
                operation: "reading GigaAM token"
            )
            let confidence = token.p.isFinite ? token.p : nil
            tokens.append(
                NativeGigaToken(
                    text: token.text.map(String.init(cString:)) ?? "",
                    startTime: Double(token.t0_ms) / 1_000,
                    endTime: Double(token.t1_ms) / 1_000,
                    confidence: confidence
                )
            )
        }
        var timings = transcribe_timings()
        transcribe_timings_init(&timings)
        _ = transcribe_get_timings(session, &timings)
        let processingMilliseconds = timings.mel_ms + timings.encode_ms + timings.decode_ms
        return NativeGigaResult(
            text: String(cString: transcribe_full_text(session)),
            tokens: tokens,
            loadSeconds: Double(timings.load_ms) / 1_000,
            processingSeconds: processingMilliseconds > 0 ? Double(processingMilliseconds) / 1_000 : nil
        )
    }

    private static func requireSuccess(
        _ status: transcribe_status,
        operation: String
    ) throws {
        guard status == TRANSCRIBE_OK else {
            let message = String(cString: transcribe_status_string(Int32(bitPattern: status.rawValue)))
            throw NativeOfflineASRError.nativeRuntime("\(operation): \(message)")
        }
    }
}

private nonisolated final class ProgressDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destinationURL: URL
    private let expectedBytes: Int64
    private let expectedSHA256: String
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDownloadTask?
    private var session: URLSession?

    init(
        destinationURL: URL,
        expectedBytes: Int64,
        expectedSHA256: String,
        progress: @escaping @Sendable (Double) -> Void
    ) {
        self.destinationURL = destinationURL
        self.expectedBytes = expectedBytes
        self.expectedSHA256 = expectedSHA256
        self.progress = progress
    }

    func download(from sourceURL: URL) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let configuration = URLSessionConfiguration.default
                configuration.timeoutIntervalForRequest = 120
                configuration.timeoutIntervalForResource = 86_400
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.downloadTask(with: sourceURL)
                lock.lock()
                self.continuation = continuation
                self.task = task
                self.session = session
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            self.lock.lock()
            let task = self.task
            self.lock.unlock()
            task?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
        progress(min(max(Double(totalBytesWritten) / Double(max(1, total)), 0), 1))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if let response = downloadTask.response as? HTTPURLResponse,
               !(200...299).contains(response.statusCode) {
                throw NativeOfflineASRError.downloadFailed("HTTP \(response.statusCode)")
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
            let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard byteCount == expectedBytes else {
                throw NativeOfflineASRError.invalidModelFile(
                    "expected \(expectedBytes) bytes, received \(byteCount)"
                )
            }
            let digest = try Self.sha256(of: location)
            guard digest == expectedSHA256 else {
                throw NativeOfflineASRError.invalidModelFile("SHA-256 mismatch")
            }
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            progress(1)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(.failure((error as? URLError)?.code == .cancelled ? CancellationError() : error))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        self.task = nil
        let session = self.session
        self.session = nil
        lock.unlock()
        guard let continuation else { return }
        session?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 8 * 1_024 * 1_024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

actor NativeGigaAMASRBackend: ASRBackend, ASRModelPreparing {
    nonisolated static let modelFileName = "gigaam-v3-e2e-rnnt-Q8_0.gguf"
    nonisolated static let modelBytes: Int64 = 273_724_832
    nonisolated static let modelSHA256 = "78d63b47723b7f8d78c6113a6ef983b5a86e2a86f6c273e1f5cb6967b1c4467a"
    nonisolated static let modelURL = URL(
        string: "https://huggingface.co/handy-computer/gigaam-v3-e2e-rnnt-gguf/resolve/main/\(modelFileName)"
    )!

    private let rootDirectoryURL: URL
    private var nativeSession: NativeGigaSession?

    init(rootDirectoryURL: URL? = nil) {
        self.rootDirectoryURL = rootDirectoryURL ?? NativeOfflineASRPaths.rootDirectory()
            .appendingPathComponent(OfflineASRModelID.gigaAMV3.rawValue, isDirectory: true)
    }

    func prepare(
        modelID: OfflineASRModelID,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        guard modelID == .gigaAMV3 else {
            throw ASRBackendRouterError.unavailable(modelID)
        }
        _ = try await loadSession(progress: progress)
        progress(1, "Ready")
    }

    func transcribe(
        _ request: ASRBackendRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ASRBackendOutput {
        guard request.modelID == .gigaAMV3 else {
            throw ASRBackendRouterError.unavailable(request.modelID)
        }
        let wasColdStart = nativeSession == nil
        let loadStartedAt = ProcessInfo.processInfo.systemUptime
        let nativeSession = try await loadSession { fraction, _ in progress(fraction * 0.05) }
        let modelLoadingSeconds = ProcessInfo.processInfo.systemUptime - loadStartedAt
        let chunks = NativeAudioChunker.chunks(
            samples: request.samples,
            maximumDuration: 24,
            silenceSearchDuration: 5,
            minimumDuration: 8
        )
        let startedAt = ProcessInfo.processInfo.systemUptime
        var texts: [String] = []
        var words: [TimedWord] = []
        var nativeSeconds = 0.0

        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let pcm = Array(request.samples[chunk.range])
            let result = try await Task.detached(priority: .userInitiated) {
                try nativeSession.transcribe(pcm)
            }.value
            if !result.text.isEmpty { texts.append(result.text) }
            words.append(contentsOf: Self.words(from: result.tokens, offset: chunk.startTime))
            nativeSeconds += result.processingSeconds ?? 0
            progress(0.05 + 0.95 * Double(index + 1) / Double(max(1, chunks.count)))
        }

        let text = texts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw NativeOfflineASRError.emptyTranscript }
        var warnings: [String] = []
        if request.ctcMode != .off {
            warnings.append("FluidAudio CTC vocabulary rescoring is available only with Parakeet.")
        }
        progress(1)
        return ASRBackendOutput(
            transcript: TimedTranscript(text: text, words: words),
            adjustedText: nil,
            replacements: [],
            modelName: Self.snapshot.modelName,
            backendSnapshot: Self.snapshot,
            resolvedCTCMode: nil,
            warnings: warnings,
            wasColdStart: wasColdStart,
            modelLoadingSeconds: modelLoadingSeconds,
            asrWallSeconds: ProcessInfo.processInfo.systemUptime - startedAt,
            ctcWallSeconds: 0,
            nativeProcessingSeconds: nativeSeconds > 0 ? nativeSeconds : nil
        )
    }

    private func loadSession(
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> NativeGigaSession {
        if let nativeSession { return nativeSession }
        let modelFileURL = rootDirectoryURL.appendingPathComponent(Self.modelFileName)
        let markerURL = rootDirectoryURL.appendingPathComponent(".ready-\(Self.modelSHA256)")
        if !isDownloadedModelValid(modelURL: modelFileURL, markerURL: markerURL) {
            progress(0, "GigaAM · Downloading 261 MB model")
            let downloader = ProgressDownloadDelegate(
                destinationURL: modelFileURL,
                expectedBytes: Self.modelBytes,
                expectedSHA256: Self.modelSHA256
            ) { fraction in
                progress(fraction * 0.92, "GigaAM · Downloading 261 MB model")
            }
            try await downloader.download(from: Self.modelURL)
            try FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
            try Data(Self.modelSHA256.utf8).write(to: markerURL, options: .atomic)
        }
        progress(0.94, "GigaAM · Loading Metal model")
        let loaded = try await Task.detached(priority: .userInitiated) {
            try NativeGigaSession(modelURL: modelFileURL)
        }.value
        nativeSession = loaded
        progress(1, "Ready")
        return loaded
    }

    private func isDownloadedModelValid(modelURL: URL, markerURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: markerURL.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
              (attributes[.size] as? NSNumber)?.int64Value == Self.modelBytes else {
            return false
        }
        return true
    }

    private nonisolated static func words(
        from tokens: [NativeGigaToken],
        offset: TimeInterval
    ) -> [TimedWord] {
        var words: [TimedWord] = []
        let punctuation = CharacterSet.punctuationCharacters
        for token in tokens {
            var text = token.text
            guard !text.isEmpty, !text.hasPrefix("<") else { continue }
            let startsWord = text.hasPrefix("▁") || text.first?.isWhitespace == true || words.isEmpty
            text = text.replacingOccurrences(of: "▁", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let punctuationOnly = text.unicodeScalars.allSatisfy { punctuation.contains($0) }
            if startsWord && !punctuationOnly {
                words.append(
                    TimedWord(
                        text: text,
                        startTime: offset + token.startTime,
                        endTime: offset + token.endTime,
                        confidence: token.confidence
                    )
                )
            } else if let last = words.indices.last {
                words[last].text += text
                words[last].endTime = offset + token.endTime
                if let current = words[last].confidence, let confidence = token.confidence {
                    words[last].confidence = min(current, confidence)
                }
            } else {
                words.append(
                    TimedWord(
                        text: text,
                        startTime: offset + token.startTime,
                        endTime: offset + token.endTime,
                        confidence: token.confidence
                    )
                )
            }
        }
        return words
    }

    nonisolated static let snapshot = ASRBackendSnapshot(
        backendID: "native.ggml.gigaam",
        modelID: .gigaAMV3,
        modelName: "GigaAM v3 e2e_rnnt",
        modelVersion: "handy-computer/gigaam-v3-e2e-rnnt-gguf@Q8_0",
        runtime: "transcribe.cpp@0.2.0/ggml/Metal",
        configuration: [
            "language": "ru",
            "chunkSeconds": "24, silence-aware",
            "timestamps": "token, 40ms",
            "quantization": "Q8_0",
        ]
    )
}
