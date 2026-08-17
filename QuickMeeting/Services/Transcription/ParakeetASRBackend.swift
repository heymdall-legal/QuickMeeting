import FluidAudio
import Foundation

/// FluidAudio/Parakeet adapter. No FluidAudio ASR result type crosses this
/// boundary; the rest of the app only sees backend-neutral timed words.
actor ParakeetASRBackend: ASRBackend {
    private let version: AsrModelVersion
    private var manager: AsrManager?

    init(version: AsrModelVersion = .v3) {
        self.version = version
    }

    func transcribe(
        _ request: ASRBackendRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ASRBackendOutput {
        let configuration = ParakeetLongFormConfiguration(
            languageCode: request.languageCode,
            modelVersion: version
        )
        let wasColdStart = manager == nil
        let modelLoadStart = ProcessInfo.processInfo.systemUptime
        let manager = try await loadManager(config: configuration.asrConfig)
        let modelLoadingSeconds = ProcessInfo.processInfo.systemUptime - modelLoadStart
        var decoderState = try TdtDecoderState()

        let progressStream = await manager.transcriptionProgressStream
        let progressTask = Task {
            for try await value in progressStream {
                progress(value)
            }
        }

        let asrStart = ProcessInfo.processInfo.systemUptime
        let fluidResult: ASRResult
        do {
            fluidResult = try await manager.transcribe(
                request.samples,
                decoderState: &decoderState,
                language: configuration.language
            )
        } catch {
            progressTask.cancel()
            throw error
        }
        let asrWallSeconds = ProcessInfo.processInfo.systemUptime - asrStart
        progressTask.cancel()
        progress(1)

        var adjustedText: String?
        var replacements: [ASRTextReplacement] = []
        var resolvedCTCMode: TranscriptionCTCMode?
        var warnings: [String] = []
        let ctcStart = ProcessInfo.processInfo.systemUptime
        if request.ctcMode != .off, !request.glossaryTerms.isEmpty {
            do {
                let ctcResult = try await applyCTCRescoring(
                    fluidResult: fluidResult,
                    samples: request.samples,
                    glossaryTerms: request.glossaryTerms,
                    mode: request.ctcMode
                )
                adjustedText = ctcResult.text
                replacements = ctcResult.replacements
                resolvedCTCMode = ctcResult.resolvedMode
            } catch {
                warnings.append("CTC vocabulary stage skipped: \(error.localizedDescription)")
            }
        }

        return ASRBackendOutput(
            transcript: Self.makeTimedTranscript(from: fluidResult),
            adjustedText: adjustedText,
            replacements: replacements,
            modelName: "Parakeet TDT v3",
            resolvedCTCMode: resolvedCTCMode,
            warnings: warnings,
            wasColdStart: wasColdStart,
            modelLoadingSeconds: modelLoadingSeconds,
            asrWallSeconds: asrWallSeconds,
            ctcWallSeconds: ProcessInfo.processInfo.systemUptime - ctcStart,
            nativeProcessingSeconds: fluidResult.processingTime
        )
    }

    nonisolated static func makeTimedTranscript(from result: ASRResult) -> TimedTranscript {
        guard let tokens = result.tokenTimings, !tokens.isEmpty else {
            return TimedTranscript(text: result.text)
        }

        var words: [TimedWord] = []
        for token in tokens {
            let startsWord = token.token.hasPrefix(" ")
                || token.token.hasPrefix("\u{2581}")
                || words.isEmpty
            if startsWord {
                words.append(
                    TimedWord(
                        text: token.token,
                        startTime: token.startTime,
                        endTime: token.endTime,
                        confidence: token.confidence
                    )
                )
            } else {
                let index = words.index(before: words.endIndex)
                words[index].text += token.token
                words[index].endTime = token.endTime
                if let current = words[index].confidence {
                    words[index].confidence = min(current, token.confidence)
                }
            }
        }
        return TimedTranscript(text: result.text, words: words)
    }

    private func loadManager(config: ASRConfig) async throws -> AsrManager {
        if let manager { return manager }
        let models = try await AsrModels.downloadAndLoad(version: version)
        let loadedManager = AsrManager(config: config)
        try await loadedManager.loadModels(models)
        manager = loadedManager
        return loadedManager
    }

    private func applyCTCRescoring(
        fluidResult: ASRResult,
        samples: [Float],
        glossaryTerms: [TranscriptionGlossaryTerm],
        mode: TranscriptionCTCMode
    ) async throws -> (
        text: String,
        replacements: [ASRTextReplacement],
        resolvedMode: TranscriptionCTCMode
    ) {
        guard let tokenTimings = fluidResult.tokenTimings, !tokenTimings.isEmpty else {
            return (fluidResult.text, [], .off)
        }

        let resolvedMode: TranscriptionCTCMode = mode == .auto ? .ctc110m : mode
        let variant: CtcModelVariant = resolvedMode == .ctc06b ? .ctc06b : .ctc110m
        let models = try await CtcModels.downloadAndLoad(variant: variant)
        let tokenizer = try await CtcTokenizer.load(from: CtcModels.defaultCacheDirectory(for: variant))
        let tokenizedTerms = glossaryTerms.compactMap { term -> CustomVocabularyTerm? in
            let text = term.normalizedText
            guard !text.isEmpty else { return nil }
            let tokenIDs = tokenizer.encode(text)
            guard !tokenIDs.isEmpty else { return nil }
            return CustomVocabularyTerm(
                text: text,
                weight: term.weight,
                aliases: term.normalizedAliases.isEmpty ? nil : term.normalizedAliases,
                ctcTokenIds: tokenIDs
            )
        }
        guard !tokenizedTerms.isEmpty else {
            return (fluidResult.text, [], resolvedMode)
        }

        let vocabulary = CustomVocabularyContext(terms: tokenizedTerms)
        let spotter = CtcKeywordSpotter(models: models)
        let spotted = try await spotter.spotKeywordsWithLogProbs(
            audioSamples: samples,
            customVocabulary: vocabulary
        )
        let rescorer = try await VocabularyRescorer.create(
            spotter: spotter,
            vocabulary: vocabulary,
            ctcModelDirectory: CtcModels.defaultCacheDirectory(for: variant)
        )
        let output = rescorer.ctcTokenRescore(
            transcript: fluidResult.text,
            tokenTimings: tokenTimings,
            logProbs: spotted.logProbs,
            frameDuration: spotted.frameDuration
        )
        return (
            output.text,
            output.replacements.map {
                ASRTextReplacement(
                    originalText: $0.originalWord,
                    replacementText: $0.replacementWord ?? "",
                    shouldReplace: $0.shouldReplace && $0.replacementWord != nil
                )
            },
            resolvedMode
        )
    }
}

/// Pure selection object used by the adapter and unit tests.
nonisolated struct ParakeetLongFormConfiguration: Sendable {
    let language: Language?
    let asrConfig: ASRConfig

    init(languageCode: String?, modelVersion: AsrModelVersion) {
        language = languageCode.flatMap(Language.init(rawValue:))
        switch modelVersion {
        case .v3:
            asrConfig = ASRConfig(melChunkContext: false, seamGapRepair: true)
        case .v2, .tdtCtc110m, .tdtJa:
            asrConfig = .default
        }
    }
}
