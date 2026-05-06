import Combine
import Foundation
import Testing
@testable import QuickMeeting

struct WhisperKitTranscriptionBackendTests {
    @Test
    func observedProgressForwardsFractionCompletedUpdates() {
        let progress = Progress(totalUnitCount: 100)
        var reported = [Double]()

        let cancellable = observeTranscriptionProgress(progress) { value in
            reported.append(value)
        }

        progress.completedUnitCount = 25
        progress.completedUnitCount = 25
        progress.completedUnitCount = 70
        progress.completedUnitCount = 100
        cancellable.cancel()

        #expect(reported == [0.25, 0.7, 1.0])
    }
}
