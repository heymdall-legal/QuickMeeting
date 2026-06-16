import AVFoundation
import CoreMedia
import Foundation

actor WaveformExtractor {
    static let sampleCount = 300

    func extract(from url: URL) async -> [Double]? {
        let asset = AVURLAsset(url: url)

        async let durationLoad = asset.load(.duration)
        async let tracksLoad  = asset.loadTracks(withMediaType: .audio)

        guard let duration = try? await durationLoad,
              let tracks   = try? await tracksLoad,
              let track    = tracks.first,
              duration.seconds > 0 else { return nil }

        let outputSettings: [String: Any] = [
            AVFormatIDKey:               Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey:      32,
            AVLinearPCMIsFloatKey:       true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey:   false,
        ]

        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { return nil }

        let bucketDuration = duration.seconds / Double(Self.sampleCount)
        var buckets = [BucketAccumulator](repeating: BucketAccumulator(), count: Self.sampleCount)

        var sampleRate       = 48_000.0
        var channelsPerFrame = 2
        var rateDetected     = false
        var framesRead       = 0

        while let cmBuffer = output.copyNextSampleBuffer() {
            if !rateDetected,
               let fmt  = CMSampleBufferGetFormatDescription(cmBuffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee {
                sampleRate       = asbd.mSampleRate > 0 ? asbd.mSampleRate : 48_000
                channelsPerFrame = Int(asbd.mChannelsPerFrame) > 0 ? Int(asbd.mChannelsPerFrame) : 2
                rateDetected     = true
            }

            guard let block = CMSampleBufferGetDataBuffer(cmBuffer) else { continue }
            let byteLen     = CMBlockBufferGetDataLength(block)
            let totalFloats = byteLen / MemoryLayout<Float>.size
            let frames      = totalFloats / max(channelsPerFrame, 1)
            guard frames > 0 else { continue }

            var raw = [Float](repeating: 0, count: totalFloats)
            raw.withUnsafeMutableBytes { ptr in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteLen,
                                              destination: ptr.baseAddress!)
            }

            for frame in 0 ..< frames {
                let t  = Double(framesRead + frame) / sampleRate
                let bi = min(Int(t / bucketDuration), Self.sampleCount - 1)
                var s2 = 0.0
                for ch in 0 ..< channelsPerFrame {
                    let v = Double(raw[frame * channelsPerFrame + ch])
                    s2 += v * v
                }
                buckets[bi].add(squareSum: s2 / Double(channelsPerFrame))
            }
            framesRead += frames
        }

        guard reader.status == .completed else { return nil }

        var rms = buckets.map(\.rms)
        let peak = rms.max() ?? 0
        if peak > 0 { rms = rms.map { $0 / peak } }
        return rms
    }
}

nonisolated private struct BucketAccumulator {
    var sumOfSquares = 0.0
    var count        = 0

    mutating func add(squareSum: Double) {
        sumOfSquares += squareSum
        count        += 1
    }

    var rms: Double {
        count > 0 ? sqrt(sumOfSquares / Double(count)) : 0
    }
}
