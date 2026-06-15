import Foundation
import Testing
@testable import QuickMeeting

struct WaveformExtractorTests {
    func writeWAV(samples: [Float], sampleRate: Int = 44100, to url: URL) throws {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample) / 8
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = UInt32(samples.count) * 2
        let chunkSize = UInt32(36) + dataSize

        var bytes = Data()
        func le<T: FixedWidthInteger>(_ v: T) {
            withUnsafeBytes(of: v.littleEndian) { bytes.append(contentsOf: $0) }
        }
        bytes.append(contentsOf: "RIFF".utf8); le(chunkSize)
        bytes.append(contentsOf: "WAVE".utf8)
        bytes.append(contentsOf: "fmt ".utf8); le(UInt32(16))
        le(UInt16(1)); le(numChannels)
        le(UInt32(sampleRate)); le(byteRate); le(blockAlign); le(bitsPerSample)
        bytes.append(contentsOf: "data".utf8); le(dataSize)
        for s in samples {
            le(Int16(max(-32_768, min(32_767, Int(s * 32_767)))))
        }
        try bytes.write(to: url)
    }

    @Test
    func extractReturnsExactly300ValuesForAValidFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let samples = [Float](repeating: 0.5, count: 44100 * 2)
        try writeWAV(samples: samples, to: url)

        let result = await WaveformExtractor().extract(from: url)
        let values = try #require(result)
        #expect(values.count == 300)
    }

    @Test
    func extractNormalisesResultSoMaxIsOne() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        var samples = [Float](repeating: 0.2, count: 44100)
        samples += [Float](repeating: 0.8, count: 44100)
        try writeWAV(samples: samples, to: url)

        let result = await WaveformExtractor().extract(from: url)
        let values = try #require(result)
        let peak = values.max() ?? 0
        #expect(abs(peak - 1.0) < 0.01)
    }

    @Test
    func extractResultValuesAreAllInZeroToOneRange() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let samples: [Float] = (0..<44100 * 3).map { Float($0 % 100) / 100.0 }
        try writeWAV(samples: samples, to: url)

        let result = await WaveformExtractor().extract(from: url)
        let values = try #require(result)
        for v in values {
            #expect(v >= 0.0)
            #expect(v <= 1.0)
        }
    }

    @Test
    func extractSilenceReturnsAllZeros() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let samples = [Float](repeating: 0.0, count: 44100)
        try writeWAV(samples: samples, to: url)

        let result = await WaveformExtractor().extract(from: url)
        let values = try #require(result)
        for v in values {
            #expect(v == 0.0)
        }
    }

    @Test
    func extractMissingFileReturnsNil() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-missing.wav")
        let result = await WaveformExtractor().extract(from: url)
        #expect(result == nil)
    }
}
