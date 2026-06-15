//
//  WaveformPlayerBar.swift
//  QuickMeeting
//

import SwiftUI

struct WaveformPlayerBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let isAvailable: Bool
    let waveformSamples: [Double]
    let onToggle: () -> Void
    /// Called with a 0...1 fraction of the timeline.
    let onSeek: (Double) -> Void

    private var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, currentTime / duration))
    }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(QMTheme.sage, in: Circle())
                    .shadow(color: QMTheme.sage.opacity(0.45), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(!isAvailable)
            .opacity(isAvailable ? 1 : 0.5)

            waveform

            Text("\(timeString(currentTime)) / \(timeString(duration))")
                .font(.system(size: 12.5).monospacedDigit())
                .foregroundStyle(QMTheme.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(QMTheme.cardBorder, lineWidth: 1))
        .shadow(color: Color(hex: "#28241e").opacity(0.18), radius: 16, y: 10)
    }

    private var waveform: some View {
        GeometryReader { proxy in
            let barStride: CGFloat = 5  // 3 px bar + 2 px gap
            let displayCount = max(1, Int(proxy.size.width / barStride))
            let heights = waveformDisplayHeights(from: waveformSamples, displayCount: displayCount)
            HStack(spacing: 2) {
                ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                    Capsule()
                        .fill(Double(index) / Double(displayCount) < fraction
                              ? QMTheme.sage : QMTheme.recordedDot)
                        .frame(width: 3, height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard isAvailable, proxy.size.width > 0 else { return }
                        onSeek(min(1, max(0, value.location.x / proxy.size.width)))
                    }
            )
        }
        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
    }

    private func timeString(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Converts stored amplitude samples into `displayCount` bar heights
/// in the 4...30 pt range used by `WaveformPlayerBar`.
/// Returns the sine placeholder when `samples` is empty (not yet extracted).
func waveformDisplayHeights(from samples: [Double], displayCount: Int) -> [CGFloat] {
    guard !samples.isEmpty else {
        return QMWaveform.resized(to: displayCount)
    }
    guard displayCount > 0 else { return [] }
    let ratio = Double(samples.count) / Double(displayCount)
    return (0..<displayCount).map { i in
        let start = Int((Double(i) * ratio).rounded(.down))
        let end   = min(Int((Double(i + 1) * ratio).rounded(.up)), samples.count)
        let slice = samples[start..<end]
        let avg   = slice.reduce(0, +) / Double(slice.count)
        return CGFloat(4 + avg * 26)
    }
}
