import Testing
@testable import QuickMeeting

struct WaveformDisplayTests {
    // MARK: QMWaveform.resized

    @Test
    func resizedToSameCountReturnsOriginalValues() {
        let result = QMWaveform.resized(to: 74)
        #expect(result.count == 74)
        #expect(result == QMWaveform.heights)
    }

    @Test
    func resizedToMoreBarsInterpolatesWithinHeightRange() {
        let result = QMWaveform.resized(to: 150)
        #expect(result.count == 150)
        for h in result {
            #expect(h >= 4)
            #expect(h <= 30)
        }
    }

    @Test
    func resizedToFewerBarsAveragesWithinHeightRange() {
        let result = QMWaveform.resized(to: 30)
        #expect(result.count == 30)
        for h in result {
            #expect(h >= 4)
            #expect(h <= 30)
        }
    }

    @Test
    func resizedToZeroReturnsEmpty() {
        #expect(QMWaveform.resized(to: 0) == [])
    }

    // MARK: waveformDisplayHeights

    @Test
    func displayHeightsFromEmptySamplesReturnsSinePlaceholder() {
        let result = waveformDisplayHeights(from: [], displayCount: 74)
        #expect(result.count == 74)
        #expect(result == QMWaveform.heights)
    }

    @Test
    func displayHeightsFromNormalisedSamplesMapIntoExpectedRange() {
        let samples = [Double](repeating: 0.5, count: 300)
        let result = waveformDisplayHeights(from: samples, displayCount: 100)
        #expect(result.count == 100)
        for h in result {
            #expect(h >= 4)
            #expect(h <= 30)
        }
    }

    @Test
    func displayHeightsFromAllOnesReturnsMaxHeight() {
        let samples = [Double](repeating: 1.0, count: 300)
        let result = waveformDisplayHeights(from: samples, displayCount: 50)
        for h in result {
            #expect(abs(h - 30) < 0.01)
        }
    }

    @Test
    func displayHeightsFromAllZerosReturnsMinHeight() {
        let samples = [Double](repeating: 0.0, count: 300)
        let result = waveformDisplayHeights(from: samples, displayCount: 50)
        for h in result {
            #expect(abs(h - 4) < 0.01)
        }
    }

    @Test
    func displayHeightsCountMatchesRequestedDisplayCount() {
        let samples = [Double](repeating: 0.5, count: 300)
        #expect(waveformDisplayHeights(from: samples, displayCount: 1).count == 1)
        #expect(waveformDisplayHeights(from: samples, displayCount: 74).count == 74)
        #expect(waveformDisplayHeights(from: samples, displayCount: 200).count == 200)
        #expect(waveformDisplayHeights(from: samples, displayCount: 0).count == 0)
    }
}
